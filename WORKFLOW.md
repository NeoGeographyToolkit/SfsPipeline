# End-to-end SfS workflow

This is the practical, runnable sequence for producing a large-scale
Shape-from-Shading (SfS) DEM with the Ames Stereo Pipeline, from terrain
preparation through bundle adjustment, SfS, re-registration to LOLA, and
blending. It follows the large-scale section of the
[ASP SfS guide](https://stereopipeline.readthedocs.io/en/latest/sfs_usage.html)
and drives the scripts in `bin/`.

## Conventions

- Every heavy step runs on a compute node through `qsub`. The head node is used
  only for trivial list-building and inspection. Do not run multi-thread work on
  a front-end node.
- Worker scripts are plain `.sh` (or `.py`). They do the work and take the
  project work directory as their last positional argument, always passed as
  `$(pwd)`. There are no self-submitting `.pbs` scripts.
- Workers thread to the PBS-provided core count (`$NCPUS`), not `nproc` (which
  can report 1 inside a PBS job). Set `NCPUS`/`MODEL` where a step takes them.
- Set the PBS allocation once as an environment variable, the group_list for your
  project, and pass it to every `qsub`. Nothing hardcodes an allocation.

```bash
export groupName=your_allocation
```

- The canonical submission form is:

```bash
qsub -V -m n -r n -N <name> -q normal \
  -W group_list=$groupName -j oe -S /bin/bash \
  -l select=<N>:ncpus=<C>:model=<model> -l walltime=<HH:MM:SS> \
  -- <script>.sh <args...> $(pwd)
```

  Node models and core counts (`bro_ele` 28, `cas_ait` 40, `rom_ait` 128) and the
  suggested walltimes below are starting points. Tune them to your site size.
  The `rom_ait` and Athena nodes are much more expensive per node-hour and are
  best avoided. On a non-interactive ssh, `qsub` may not be on PATH. Use
  `/PBS/bin/qsub` (Pleiades) or `/opt/pbs/bin/qsub` (Athena front end).

- Activate the environment first (`source init_asp.sh`), which puts `bin/` plus
  the ASP and ISIS tools on PATH and sets `ASPROOT`, `ISISROOT`, `ISISDATA`.
- Always pass `-V` to `qsub` (as shown in the canonical submission form above).
  A `qsub` job starts with a fresh environment by default, so without `-V` the
  submitting shell's `ASPROOT`/`ISISROOT`/`ISISDATA`/`ALESPICEROOT` do not reach
  the compute node, causing workers to fall back to hardcoded default paths and
  fail. Submitter scripts that fan out per-chunk jobs (`batch_mapproject.sh`,
  `launch_sfs_tiles.sh`) forward these variables automatically.
- Gate each stage on the PBS job reaching `job_state=F`, never on an output file
  appearing (a product shows up while still half-written). Inspect each product
  (hillshade, geodiff, red/green overlay) before moving on, not ten steps later.

## 1. Reference terrain preparation

Regrid a LOLA source DEM (e.g. the Barker et al. 2023 `LDEM_83S_10MPP_ADJ.TIF`)
to the target projection, resolution, and a half-integer extent. See the
[terrain preparation section](https://stereopipeline.readthedocs.io/en/latest/sfs_usage.html#sfs-initial-terrain)
in the [reference documentation](https://stereopipeline.readthedocs.io/en/latest/sfs_usage.html),
including [ensuring extents are offset by 0.5 pixels](https://stereopipeline.readthedocs.io/en/latest/sfs_usage.html#terrain-bounds)
so pixel centers are integer multiples of the grid (required by `sfs_blend`).
`make_ref_dem.sh` wraps `gdalwarp` (cubic spline, 256-block tiling). Build it on
a compute node, not the head node. Suggested walltime 1:00:00.

Two conventions matter here:
- **Pad the extent beyond the delivery box** (footprints spill past the ROI).
  The padded DEM is the one used for mapprojection and as the `--heights-from-dem`
  constraint. It is a genuine LOLA regrid over a larger area, not a fabricated
  pad.
- **Do not blur.** A small-sigma blur is a no-op on km-scale relief and only adds
  bias, so the height constraint is the honest, unblurred DEM. If you ever do
  blur (pass a non-zero last argument), `make_ref_dem.sh` writes a separate
  `_blur.tif`. Use that only for mapprojection, never as the height constraint,
  and let the name say so.

```bash
qsub -V -m n -r n -N ref_dem -q normal \
  -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=20:model=bro_ele -l walltime=1:00:00 \
  -- make_ref_dem.sh src_lola.tif ref/lola_1mpp.tif \
     "71240.5 162789.5 90731.5 178256.5" 1 $(pwd) \
     "+proj=stere +lat_0=-90 +lon_0=0 +R=1737400 +units=m +no_defs"
```

Confirm 100% valid and a half-integer origin with `gdalinfo -stats`.

## 2. Fetch and calibrate LRO NAC images

Query candidate NAC observations for the ROI, download the EDRs, and calibrate
each to a `.cal.echo.cub` plus a CSM `.json` camera.

Discovery finds the NAC observations covering the ROI and their ids and URLs. Two
ways, use either.

Cumulative-index method (local, offline after a one-time index build). `make-index`
builds geoparquet index files from `CUMINDEX.LBL`/`CUMINDEX.TAB` (about two minutes,
embeds provenance), then `sfs-cover` selects the ROI polygon into a GeoPackage:

```bash
make-index
sfs-cover \
  --db_path lroc_cumulative_south_polar.parquet \
  -p "POLYGON((72471 158818,128309 158818,128309 119030,72471 119030,72471 158818))" \
  -t my_roi --gpkg my_roi.gpkg
```

ODE method (live network query, no index). `query_lro.sh` queries the PDS Orbital
Data Explorer by DEM extent (`--dem`, optional `--margin-km`) or `--lat-lon` box,
optionally filtering by incidence, and writes the `.IMG` URLs (`--output-urls`, for
download) and the product ids (`--output-products`, for ingest):

```bash
query_lro.sh --dem ref/lola_1mpp.tif --margin-km 1.0 \
  --min-incidence 70 --max-incidence 90 \
  --output-urls lists/urls.txt --output-products lists/products.txt
```

Download the EDRs on a front end (compute nodes have no network). A site is roughly
600 GB and fetching it serially can take the better part of a day or more.

Fetch serially, one cube at a time, which is gentlest on the server:

```bash
download_all.sh lists/urls.txt
```

To speed this up, split `lists/urls.txt` into two or three sublists and launch
one instance on each of a few NAS head nodes. More than three instances is not
recommended.

Less recommended is three parallel fetches at once, acceptable only against the CDN
default or the `im` mirror, never the ODE service (`oderest.rsl.wustl.edu`) or ASU
PDS node (`pds.lroc.asu.edu`), the primary archive:

```bash
db_to_urls.sh my_roi.gpkg im | xargs -n 1 -P 3 -I {} wget {} -P img/
```

Batch ingest turns each id into a calibrated cube and CSM camera. Per id,
`batch_prepare_lro.sh` runs: fetch the EDR `.IMG` (`fetch_lro_nac.sh`: ODE query
then one download), `lronac2isis`, `spiceinit`, `lronaccal`, `lronacecho`, and
`isd_generate --reduction linear` (the CSM `.json`, reduced linearly to about a
tenth the size with sub-mm `cam_test` agreement, and these cameras ship at
delivery). The runner is serial (one id, one process, one thread, `SLEEP_SECONDS`
default 10 between) and resumable (skips finished ids).

Run it under qsub. To go faster, split the id list the same way as above (two or
three serial runners on separate front ends, no more), each writing `img/`. Walltime
2:00:00 per runner:

```bash
split -n l/3 -d --additional-suffix=.txt lists/products.txt lists/part
qsub -V -m n -r n -N calib -q normal \
  -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=40:model=cas_ait -l walltime=2:00:00 \
  -- batch_prepare_lro.sh lists/part00.txt img $(pwd)
```

### 2a. USGS-registered (controlled) south-polar images

For the Lunar South Pole a large set of NAC images has USGS-provided, well-registered
camera geometry (bundle-adjusted and controlled to LOLA). Holding these fixed in the
first bundle adjustment (section 5b) registers the rest of the cameras to the LOLA frame
without a separate alignment step.

The list of registered images ships in this repo:
`data/updated_SPole_2023_ImageGCPAdd_root.lis` (18323 NAC root ids, LE and RE, acquired
July 2009 to August 2013). Find the registered subset for a site by intersecting it with
the site's NAC candidate list:

```bash
M=data/updated_SPole_2023_ImageGCPAdd_root.lis
grep -Fxf "$M" lists/products.txt | sort -u > lists/usgs_registered.txt
```

Build the registered CSM cameras by running `spiceinit` with the USGS polar SPICE kernels
and regenerating the camera. For a fresh ingest, pass `--usgs-polar` to the batch ingest;
for cubs already prepared with standard kernels, re-register a copy in place (no re-fetch)
with `redo_spiceinit_usgs.sh`:

```bash
batch_prepare_lro.sh lists/usgs_registered.txt usgs_south --usgs-polar
redo_spiceinit_usgs.sh lists/usgs_registered.txt img usgs_south $(pwd)
```

The matching polar SPICE kernels (CK `.bc` + SPK `.bsp`) are referenced by the
`usgs_polar_ck.mk` / `usgs_polar_spk.mk` meta-kernels under `$ISISDATA/lro_south` on a
populated ISIS data area, or can be downloaded from the [USGS data release (south pole item)](https://www.sciencebase.gov/catalog/item/688a51d7d4be02367c9c1271).

Data release citation: Weller, L.A., et al., 2025, Improved camera pointing and spacecraft
ephemeris data for Lunar Reconnaissance Orbiter Camera (LROC) Narrow Angle Camera (NAC)
images of the lunar poles: [U.S. Geological Survey data release](https://doi.org/10.5066/P1OASYRV).
See [data/README.md](data/README.md) for the full citation. The registered-camera workflow is
described in the ASP documentation under [Incorporation of well-registered images](https://stereopipeline.readthedocs.io/en/latest/sfs_usage.html#usgs-reg).

## 3. Image selection and sorting by illumination

Get each camera's Sun azimuth and sort the list by it, so that the later
`--overlap-limit` in bundle adjustment pairs images of similar illumination
(matched shadows). Low-signal / shadowed frames are culled by their max value
(0.005 is the LRO NAC lit-vs-shadow cutoff). Inspect the max-value distribution
first and drop all-shadow and non-intersecting frames.

```bash
sfs_query.sh img/*.cal.echo.cub > lists/azimuth_tables.txt
sort -k3,3 -n lists/azimuth_tables.txt > lists/azimuth.txt
awk '{print $1}' lists/azimuth.txt > lists/azimuth_images.txt
filter_by_max.sh lists/azimuth_map.txt lists/filtered_map.txt $(pwd) 0.005
```

Keep every `lists/*.txt` in azimuth order and 1-to-1 between images and cameras.

Visualize the azimuth distribution as a polar rose with `plot_sfs_azimuth.py` (it
reads the `sfs_query.sh` table) to judge how the illumination clusters and whether
coverage is representative. At the poles the low Sun is usually strongly clustered,
often bimodal with near-empty gaps, which matters later when forming subset groups.

Camera-graph connectivity (optional, a useful downselect): refresh the
GeoPackage footprints to the actual mapprojected, shadow-masked extents, then
check connectivity with `find-image-overlaps`. The matcher in bundle adjustment
is the azimuth-sort plus `--overlap-limit`, not this overlap graph, but the graph
is a good way to find and drop images that cannot connect. After mapprojection
(step 4):

```bash
source sfs_utilities.sh
collect_geojson_stream img 'map.mask.geojson' > mask_footprints.geojson
update-db SOURCE.gpkg my_roi_mask.gpkg mask_footprints.geojson
find-image-overlaps --check_connectivity -d ./my_roi_mask.gpkg --max_diff_slrgaz=8
```

Here `--max_diff_slrgaz` is the sub-solar ground-azimuth difference over which
connectivity is reported. `find-image-overlaps` reports `is_connected`,
`num_components`, and `component_sizes` (largest first). Raise `--max_diff_slrgaz`
until the graph is a single connected component without producing too many pairs
(6 to 8 degrees is usually a good range). Images outside the largest component are
dropped.

## 4. Mapprojection

Mapproject every image onto the reference DEM. `batch_mapproject.sh` slices the
list into chunks and submits one node per chunk. `mapproject_chunk.sh` is the
per-node worker it `qsub`s (so you run `batch_mapproject.sh` on the head node and
it submits the chunks). Control the grid and extent through environment
variables. Chunks finish in a few hours at most.

Leave `TR` unset so mapproject uses `--tr 1` and names outputs
`<id>.cal.echo.map.tr1.tif`, which is what `bundle_adjust.sh` expects (setting
`TR=1` names them `.map.tif` and bundle adjust then finds none).

```bash
export QSUB_BIN=/PBS/bin/qsub
export PROJWIN="71240.5 162789.5 90731.5 178256.5"
export NO_MOSAIC=1 CHUNK_SIZE=121 MODEL=bro_ele WALLTIME=4:00:00
batch_mapproject.sh ref/lola_1mpp.tif \
  lists/azimuth_images.txt ignored maps $(pwd) lists/azimuth_cameras.txt
```

## 5. Bundle adjustment

### 5a. Matches-only harvest

Harvest interest-point matches with `NUM_ITERATIONS=0` (no drift-prone free
solve yet). We use our own IP detection (`--ip-detect-method 0`, OBALoG, which
beats SIFT on these shadowed cross-illumination scenes, `--match-first-to-last`)
and `--overlap-limit` over the azimuth-sorted list. The raw `.match` files are
the reusable deliverable of this step. Suggested walltime up to a day on 8-16
nodes (matching parallelizes well, often finishes in a few hours).

```bash
qsub -V -m n -r n -N ba_match -q normal \
  -W group_list=$groupName -j oe -S /bin/bash \
  -l select=10:ncpus=28:model=bro_ele -l walltime=8:00:00 \
  -v "IMG_DIR=img,OVERLAP_LIMIT=100,NUM_ITERATIONS=0,PROCESSES=10,THREADS=8" \
  -- bundle_adjust.sh lists/filtered_map.txt ref/lola_1mpp.tif maps ba/run $(pwd)
```

### 5b. Controlled refine chain (fixed -> free -> heights-from-dem)

`bundle_adjust_refine.sh` reuses the harvested matches and runs one stage per
call, from most-constrained to least and back to the ground. Run each as its own
single-node job. Each waits for the previous. Suggested walltime 8:00:00 each
(`bro_ele` rejects more than 8 hours). The three stages are:

- **Stage 1, fixed.** A set of well-registered cameras is held fixed and pulls
  the rest into their frame. On the Moon these are the USGS South-Pole controlled
  cameras.
- **Stage 2, free.** All cameras are relaxed with no external constraint, reusing
  stage 1's clean matches so the network settles. It feeds on `ba_fix`.
- **Stage 3, heights-from-dem.** A final tighten to the reference terrain. It
  feeds on `ba_free` and reuses stage 1's clean matches.

```bash
qsub -V -m n -r n -N ba_fix -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=8:00:00 \
  -v "FIXED_LIST=lists/usgs_fixed_images.txt" \
  -- bundle_adjust_refine.sh lists/filtered_images.txt lists/filtered_cameras.txt \
     ba/run ba_fix $(pwd)

qsub -V -m n -r n -N ba_free -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=8:00:00 \
  -v "USE_CLEAN=1" \
  -- bundle_adjust_refine.sh ba_fix/run-image_list.txt ba_fix/run-camera_list.txt \
     ba_fix/run ba_free $(pwd)

qsub -V -m n -r n -N ba_htdem -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=8:00:00 \
  -v "USE_CLEAN=1,REF_DEM=ref/lola_1mpp.tif" \
  -- bundle_adjust_refine.sh ba_free/run-image_list.txt ba_free/run-camera_list.txt \
     ba_fix/run ba_htdem $(pwd)
```

Stage 1 uses the raw harvested matches (the `NUM_ITERATIONS=0` clean matches are
over-culled against un-optimized cameras). Stages 2 and 3 reuse stage 1's clean
matches, which were filtered against a real registered solve. The final cameras
are `ba_htdem/run-...-adjusted_state.json`.

Validate each stage: the median reprojection error per camera in
`<outDir>/run-final_residuals_stats.txt` should fall to about 1-2 px. Then check
the camera graph with `verify-ba`, which uses the match-offset and residual
stats to report the largest connected component. Iterate `--min_match_count` to
see how it changes:

```bash
verify-ba ba_htdem/run --min_match_count=10 --max_residual_error=2.0 | jq '.component_sizes'
verify-ba ba_htdem/run --min_match_count=10 --max_residual_error=2.0 > ba_htdem_comps.json
```

## 6. Post-bundle evaluation and camera prune

Before SfS, confirm the cameras co-register and remove the misaligned ones,
meaning images with large outliers or an insufficient match count in
`run-mapproj_match_offset_stats.txt`. This is the go/no-go gate. The ASP manual
discusses this validation at length in its
[registration validation section](https://stereopipeline.readthedocs.io/en/latest/sfs_usage.html#sfs-reg-valid).

Mapproject the survivors with the final `ba_htdem` cameras, then build a max-lit
mosaic of each azimuth half and overlay them red/green: coincident terrain means
the cameras co-register. Red/green only on opposite crater walls is an
illumination difference (fine). A uniform offset of whole crater outlines is a
real misregistration. Then rank the per-camera bundle-adjust stats and prune.

Flag the misaligned cameras from the `ba_htdem` per-camera stats. The file
`run-mapproj_match_offset_stats.txt` (meters off consensus) is the primary
detector: a high error percentile or a low match count there marks a misaligned
image. The file `run-camera_offsets.txt` plus a low match count catches cameras
that drifted. The reprojection stats in `run-final_residuals_stats.txt` are blind
to a self-consistent-but-wrong pose. The defaults flag a camera when its offset
p95 exceeds 5 m, its median reprojection error exceeds 0.75 px, it moved more than
1000 m, or it has fewer than 50 matches.

```bash
sfs_flag_bad_cameras.py ba_htdem/run -o lists/removed_ids.txt
```

Rebuild the max-lit mosaic without re-mapprojecting, since the per-image
`*.map.tr1.tif` survive. The removed ids are dropped from each chunk list, then
`dem_mosaic --max` is re-run per chunk, per half, and for the total.

```bash
sfs_prune_and_remosaic.sh map_htdem lists/removed_ids.txt $(pwd) 500 28
```

After a per-line jitter solve (especially with a loose orientation guard or finer
orientation knots), also screen for cameras with a catastrophic pose change using
`cam_test`. Compare the pre-jitter camera against the jitter camera per image and
drop any in the SfS set with a max pixel difference over about 250 px (severe over
1000 px). Such poses still fit their own tie points, so reprojection and
mapproj-offset stay flat and the bundle-stats prune above misses them, but they
smear their own localized footprint in the max-lit. They are a handful, and redundant frames cover
the gap, so pruning loses no coverage. Confirm by differencing the pruned max-lit
against the full one. The difference should be a tiny fraction of pixels confined
to those footprints, with the scene-wide sharpness unchanged.

Verify a couple of flagged cameras visually before pruning, and after rebuilding
confirm the streaks are gone and the terrain did not move.

## 7. SfS image subset

The full image set is too expensive for the SfS solve, so pick a minimal-but-
covering subset. The grouping axis is the Sun azimuth angle, not equal counts.
Plot the rose first (`plot_sfs_azimuth.py`), then cut the site into fixed angle
slices of roughly 45 degrees, respecting the natural gaps. Keep a rare illumination
direction as its own whole group, drop empty slices, and merge a lone stray frame
into the adjacent slice. Do not blind-cut into four 90-degree quadrants. Each slice
is then thinned by `image_subset` (a crowded angle is thinned hardest, since it
only has to fill the same ground), for a primary cover plus an extra (2x) cover on
the remainder, driven by `sfs_select_full_site.sh` over low-resolution sub8 images.
Build the sub8 copies with `make_sub8.sh` (`gdal_translate -outsize 12.5% -r average`,
which preserves the data type and georeferencing so the reduced images stay
registered). The old `prepare_lowres.sh` stereo_gui-pyramid path is retired, as
stereo_gui no longer writes `_subN.tif` pyramids. Validate with a max-lit of the
selection against the full-set max-lit.

```bash
make_sub8.sh lists/filtered_map.txt sub8 lists/sub8_map.txt $(pwd)
sfs_select_full_site.sh lists/filtered_map.txt lists/azimuth.txt selection $(pwd) 0.01 28
```

Note on GSD: coarse frames hurt SfS and the max-lit mosaic. Ground area per pixel
scales as GSD squared, so a 2 m/pixel frame covers about 4x the real estate of a
1 m/pixel one, which is exactly why `image_subset`'s coverage-greedy ranking tends
to prefer the coarse frame when a finer one would be better. `query_gsd.sh` reports
each image's native ground sample distance. It also correlates with high
`mapproj_match_offset` (partly a coarseness proxy), so the coarsest tend to be
caught by the prune in step 6. Treat GSD over about 1.75 m as suspect and over 2 m
as a drop from the SfS subset, preferring a finer frame and keeping a coarse one
only as a last resort where it is the sole cover (gate on coverage holes first).
Drop only from the SfS subset, never from the bundle solve, where the large
footprints are tie-point coverage assets.

The `image_subset` coverage threshold (last arg above) should stay at 0.01 for a
shadow-calibrated reflectance like LRO NAC, where the lit/shadow cutoff is about
0.005, so 0.01 means weak-but-solidly-lit. It will not thin the set dramatically,
and that is correct: at a grazing polar site much real terrain is only ever weakly
lit, and raising the threshold drops genuinely-lit terrain the SfS solve needs. The
lever for fewer images is the grouping, not the threshold. Change it only as a
deliberate user decision, tuning by clicking pixel values in stereo_gui, never
raising it on your own to thin more.

```bash
query_gsd.sh lists/filtered_images.txt lists/filtered_cameras.txt ref/lola_1mpp.tif \
  lists/gsd 2.0 $(pwd)
```

## 8. Shape-from-Shading

### 8a. Compute exposures (do this first)

`sfs --compute-exposures-only` writes one `run-exposures.txt` that every tile and
every later simulation reuses. Run it once over the selected set before tiling.

```bash
qsub -V -m n -r n -N sfs_exp -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=2:00:00 \
  -- sfs_exposures.sh lists/secondary_images.txt ba_htdem/run ref/lola_1mpp.tif \
     exposures_sec $(pwd)
```

### 8b. Tile the reference DEM

Tile into roughly 4k x 4k padded tiles so SfS runs as many independent per-tile
jobs that are merged afterwards. Local, fast (run under the `geo` conda env):

```bash
tile_dem.py ref/lola_1mpp.tif 4000 4000 tiles 200
```

### 8c. Run parallel_sfs per tile

`launch_sfs_tiles.sh` submits one SfS job per tile (`parallel_sfs.sh` is the
per-tile worker, which bakes in the Lunar-Lambert reflectance, smoothness, and
initial-DEM-constraint weights). Pass the exposures from 8a. A 4k tile is roughly
6-10 h on 2 `bro_ele` nodes. Use the `long` queue. The trailing `0` is
`estimError=0` (the SfS pass, no error map).

```bash
export MODEL=bro_ele NCPUS=28 QUEUE=long WALLTIME=16:00:00
launch_sfs_tiles.sh tiles lists/secondary_images.txt ba_htdem/run \
  exposures_sec/run-exposures.txt sfs 0 $(pwd)
```

### 8d. Merge the tiles

Merge with a blended `dem_mosaic` (no `--max`, so tile seams stay smooth). The
output product name is `sfs_dem.tif`.

```bash
qsub -V -m n -r n -N sfs_merge -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=4:00:00 \
  -- dem_mosaic_list.sh lists/sfs_tiles.txt sfs_dem.tif $(pwd)
```

Inspect: `geodiff` the SfS DEM against the reference and hillshade both. Expect
mean dz near zero, sub-meter std, and no tile seams.

## 9. Re-register the SfS terrain to LOLA

The SfS DEM can carry a residual, spatially-varying shift against LOLA. Measure
it, and if it is real, re-register the cameras and redo SfS. This per-line GCP
re-registration is the committed final refine. `jitter_solve.sh` (no GCP) is only
for removing intrinsic jitter when there is no re-registration target.

Measure the shift two ways. Per image, render an SfS-simulated view, `image_align`
it to the real mapprojected image, and record the pixel shift (set `ALIGN_THRESH=0`
to force a GCP for every image, not just the large-shift ones):

First recompute exposures over the full set on the final `sfs_dem`.

```bash
sfs_exposures.sh lists/filtered_images.txt ba_htdem/run sfs_dem.tif exposures_all $(pwd)
```

Then render and align, one GCP per image.

```bash
qsub -V -m n -r n -N sim_align -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=8:00:00 \
  -v "ALIGN_THRESH=0,EXPOSURES_PREFIX=exposures_all/run" \
  -- batch_sfs_sim.sh lists/filtered_images.txt 1 99999 sfs_dem.tif lronac_all \
     ba_htdem sim_eval $(pwd)
```

Globally, correlate the SfS and LOLA hillshades (ASP `hillshade -e 10`, grazing,
which gives more valid disparity than a washed-out multidirectional hillshade),
and read the robust median of the dx/dy disparity (ignore the pc_align matrix, an
origin-vs-centroid artifact). Add `geodiff` for dz:

```bash
qsub -V -m n -r n -N hcorr -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=20:model=bro_ele -l walltime=1:00:00 \
  -- hillshade_correlator.sh sfs_dem.tif ref/lola_1mpp.tif $(pwd) hcorr_sfs_lola 25
```

`hillshade_correlator.sh` hillshades its two inputs (grazing `hillshade -e 10`) before
correlating, which is right for comparing two DEMs. When the inputs are already textured
images rather than DEMs (two mapprojected orthoimages, or two max-lit mosaics, as in the
old-vs-new check after re-registration), pass `SKIP_HILLSHADE=1` so it correlates them
directly. Hillshading a reflectance image, whose values sit near zero and are read as an
elevation over 1 m pixels, yields a flat textureless raster and the correlation then
produces no tiles and no run-F. Note the correlator can exit 0 with no output in that
failure mode, so always confirm run-F exists and run-D is megabytes, not bytes.

If the shift is real (a roughly uniform few meters beyond LOLA's own uncertainty), turn
the disparity into a GCP with `dem2gcp.sh` and run the GCP-driven per-line refine
`jitter_gcp.sh`. A rigid `bundle_adjust` under-corrects a spatially-structured
shift because the dense match network pins the relative geometry. The per-line
flex of jitter reproduces the structure a rigid shift cannot.

```bash
dem2gcp.sh sfs_dem.tif ref/lola_1mpp.tif hcorr_sfs_lola/run-F.tif \
  ba_htdem/run-image_list.txt ba_htdem/run-camera_list.txt ba_htdem/run 20 \
  sfs_ref_corr/run.gcp $(pwd)
```

Run the jitter re-registration over the full image set, the same list as bundle
adjustment, never the thinned SfS subset. The dense tie-point network is what the
per-line solve needs, so feed every image. Finer orientation knots track the
shift better. Keep the anchor strength through `--anchor-dem-uncertainty` (a
large value is light), over-provision anchors, and let the ratio caps prune.

For a set with borderline or edge frames, set `ANCHOR_DEM` to a genuine DEM
padded well beyond the domain (4 km per side here) so the out-of-domain
orientation knots still get anchors. Keep the heights and mapprojection on the
domain DEM. Build that padded anchor DEM with `make_ref_dem.sh` (same source,
resolution, and projection as the domain DEM, with a `te` extent extended by the
pad) on the head node, or as a short devel job. It is a single-thread
cubic-spline `gdalwarp` (`GDAL_NUM_THREADS=1`, no `-multi`), so it is
head-node-compliant and finishes in one to two minutes even for a 25k by 18k
output. A normal-queue `qsub` for this trivial regrid is wasteful and can land on
a wedged node (a stuck job that even `qdel -W force` will not reap) while the
head-node run would have finished in under two minutes.

```bash
qsub -V -m n -r n -N jitter -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=8:00:00 \
  -v "NUM_ITER=75,NUM_PASSES=2,NUM_LINES_POS=15000,NUM_LINES_ORIENT=2000,DEM_UNC=20,\
ANCHOR_DEM_UNC=20,NUM_ANCHOR=5000,MAX_PAIRWISE=5000,MAX_NUM_TRI=300000,\
MAX_GCP_TO_TRI_RATIO=2.0,MAX_ANCHOR_TO_TRI_RATIO=4.0,\
ANCHOR_DEM=ref/lola_1mpp_pad4k.tif" \
  -- jitter_gcp.sh ba_htdem/run-image_list.txt ba_htdem/run-camera_list.txt \
     ref/lola_1mpp.tif sfs_ref_corr/run.gcp ba_htdem/run jitter $(pwd)
```

`CAM_POS_UNC` is 20,20. A reasonably tight camera position uncertainty such as
20,20 is suggested, because the dominant effect of this refinement is a change in
camera orientation, not position, so clamping the position hard while the
orientations do the work prevents wild oscillations of the camera centers. It is
applied through the script default rather than `-v`, because its comma would
break the `qsub` comma-delimited variable list (the job would then run with a
single wrong value).

`MAX_NUM_TRI` is the main control: at `--max-gcp-to-tri-points-ratio 2.0` and
`--max-anchor-points-to-tri-points-ratio 4.0` it sets the GCP cap at twice its
value and the anchor cap at four times it. `dem2gcp` emits up to 1M GCP, so GCP
availability never binds, the ratio does. Size it by the number of orientation
knots, which scales with the image count (knots per image is the image line count
divided by `NUM_LINES_ORIENT`), not by domain area. A roughly 14 by 10 km lunar-polar site
with 300 to 1000 full-resolution NAC images runs well around 300k tri,
which keeps a few tri per knot and lifts the GCP cap to 600k and the anchor cap to
1.2M, dense enough to resolve a smooth few-meter shift. Fewer or smaller
images need less, a site larger than about 15 by 15 km, or a longer track with
more frames, needs more. Read the actual tri, GCP, and anchor counts that
`jitter_solve` prints at startup on the first run and
retune rather than guessing. Runtime scales with image count times residual-block
count: a validated reference point is about 1000 images at 80k tri finishing in
roughly 3.5 h on one 28-core node, so 1200 images at 120k tri is about 5 to 6 h,
within an 8 h wall. Record the elapsed time and peak memory of each solve so the
next estimate has a basis.

Then redo SfS (repeat step 8, reusing the exposures since the pose change is
sub-pixel) with the `jitter/run-...-adjusted_state.json` cameras. Run a few spread
tiles first to confirm the bias collapsed, then run the full set.
Verify: `geodiff` versus LOLA (dz near zero) and `hillshade_correlator.sh` dx/dy
versus LOLA now near zero, plus `geodiff` versus the original `sfs_dem.tif`
showing the corrective move.

## 10. Blending and mosaics

On the final (re-registered) SfS DEM, build the ortho mosaics and blend the DEM
back toward the reference where there is little illumination signal
(`sfs_blend.sh`, keeping the tuned parameters from the ASP manual). The blended
DEM's hillshade is the delivery hillshade. Build it with
`gdaldem hillshade -multidirectional -compute_edges -alt 20 sfs_dem_blend.tif sfs_dem_blend_hill.tif`,
which gives a clean, readable delivery hillshade. A grazing-light hillshade (low
sun elevation, e.g. ASP `hillshade -e 10`) is kept only for the DEM-to-DEM
correlation step and for artifact QC, not for delivery.

Both ortho mosaics are delivered, with distinct roles:
- The **max-lit** mosaic (`dem_mosaic --max`) keeps the brightest pixel per
  location. It is the matching orthoimage shipped with the DEM, the input to
  `sfs_blend`, and the best view for spotting shadow coverage and camera
  misregistration.
- The **average (blend)** mosaic (`blend_img_mosaic.sh`, a seamless grassfire
  blend with shadow pixels masked) is an additional product customers have asked
  to receive as well as the max-lit one.

Build the max-lit mosaic, which is the matching ortho and the `sfs_blend` input.

```bash
qsub -V -m n -r n -N maxlit -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=1:00:00 \
  -- dem_mosaic_list.sh lists/sfs_maps.txt max_lit.tif $(pwd) --max
```

Build the average (blend) ortho mosaic, an additional delivered product, over the
same images as the max-lit mosaic (the SfS set). Then snap it onto the delivered
LOLA grid with `regrid_to_grid.sh` so it matches the max-lit mosaic pixel for
pixel.

```bash
qsub -V -m n -r n -N blendmos -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=1:00:00 \
  -- blend_img_mosaic.sh lists/sfs_maps.txt average_mosaic_raw.tif 0.005 $(pwd)
regrid_to_grid.sh average_mosaic_raw.tif average_mosaic.tif \
  "<xmin ymin xmax ymax>" 1 $(pwd)
```

Blend the SfS DEM with the reference DEM in permanently shadowed areas.

```bash
qsub -V -m n -r n -N sfs_blend -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=1:00:00 \
  -- sfs_blend.sh ref/lola_1mpp.tif sfs_dem.tif max_lit.tif $(pwd)
```

`sfs_blend.sh` defaults to `SHADOW_FILL_MODE=lola-curved`, which fills the
holes with the per-pixel minimum of the SfS, LOLA, and a surface grown from the
surrounding SfS that curves gently downward, so LOLA does not pop up above
the terrain. This needs an ASP build that supports `sfs_blend
--shadow-fill-mode`. Set `SHADOW_FILL_MODE=lola` for a plain LOLA fill.

Inspect the blended DEM's hillshade. The fill in some shadowed areas may need
to be touched up. Because the blend is local, a chosen area can be re-blended
on a padded clip with different settings, then merged back into the full result
with `dem_mosaic --priority-blending-length`. See `sfs_usage.rst`.

## 11. Height-uncertainty map

Re-run the SfS worker with `estimError=1` to write a `-height-error.tif` per tile.
This pass evaluates height perturbations on the final produced SfS DEM (the blend),
not on LOLA, so run it only after the blend is settled: tile the final blended DEM
into the same tile grid, then launch with `estimError=1`. It is single-core per tile
and slower. Budget it separately. Finally mosaic the per-tile error maps into the
delivered `height_uncertainty.tif`.

Tile the final blended SfS DEM onto the same tile grid.

```bash
tile_dem.py sfs_dem_blend.tif 4000 4000 tiles_blend 200
```

Run the uncertainty pass with `estimError=1`, over the tiles from the blend, not
LOLA.

```bash
export QUEUE=long
launch_sfs_tiles.sh tiles_blend lists/secondary_images.txt ba_htdem/run \
  exposures_sec/run-exposures.txt sfs_err 1 $(pwd)
```

Mosaic the per-tile error maps into the delivered product.

```bash
ls sfs_err/clip*/run-height-error.tif > lists/height_error_tiles.txt
dem_mosaic_list.sh lists/height_error_tiles.txt height_uncertainty.tif $(pwd)
```

## 12. Delivery

Assemble a self-describing results directory and fill in `inventory.yaml` so the
project is self-describing when handed off.

Make the results directory (`<site>_results/`) self-contained: it holds everything,
the rasters, lists, manifest files, and as subdirectories the cameras, the two
per-image ortho sets, and the disparity illustration. Do not scatter the ortho sets
into peer directories that refer back to the parent, so the whole delivery tars and
ships as one unit:

- Terrains: `sfs_dem.tif` (raw SfS), `sfs_dem_blend.tif` (blended with LOLA) and its
  hillshade `sfs_dem_blend_hill.tif`, `sfs_dem_weight.tif`, `lola_1mpp.tif`, and the
  `sfs_dem_blend_lola-diff.tif` geodiff, and `height_uncertainty.tif`.
- Ortho mosaics: `max_lit_mosaic.tif` and `average_mosaic.tif`, on the same grid.
- Image-id lists: `bundle_adjust_image_ids.txt` (the full bundle-adjust input) and
  `sfs_image_ids.txt` (the SfS subset). Ship both as text. Deliver as images and
  cameras only the SfS subset. Document the larger bundle-adjust set in the list but
  do not ship its images or cameras (no dead weight).
- Cameras (when requested): `cameras/` with the final jitter (or bundle-adjust)
  linear-reduced adjusted CSM `.json`, one per shipped image, named by bare image id.
  Stacked solve passes leave a repeated `run-run-...-` prefix on each file. On the
  way in, rename `run-run-<id>-...-adjusted_state.json` to `<id>.json`, so the camera
  ids match the ortho ids.
- Ortho directories (subdirectories of the results dir): `map_images/` (every
  shipped SfS ortho at 1 m/pixel) and `map_images_native_res/` (the sub-1 m frames at
  their own native GSD, with `gsd.csv`). The native-res orthos are mapprojected with
  the same registered cameras. Record the real output pixel size in `gsd.csv`, read
  back from each ortho.
- Disparity to LOLA: `sfs_to_lola_corr/` with the after-registration SfS-to-LOLA
  horizontal disparity, from `hillshade_correlator.sh`. Ship both the numeric float
  bands and the colorized views. The numeric bands are the customer's actual product,
  the colorized ones are the quick look. On the way in, rename:
  - `run-F_b1_nodata.tif` to `F-H.tif` (dh, horizontal, east-west).
  - `run-F_b2_nodata.tif` to `F-V.tif` (dv, vertical, north-south).
  - the colorized `colormap -5..5` views to `dh_ew_color.tif` and `dv_ns_color.tif`.

Region of interest and cropping: SfS is run on a domain padded beyond the product
ROI. Either crop every product to the ROI (snap the ROI box to the domain pixel
grid, `gdal_translate -projwin`, lossless) or deliver the full domain as insurance
against boundary artifacts and include the ROI polygon (`product_roi.gpkg`) so the
recipient can crop. Record the choice. Registration degrades toward the domain edges.

The 1 m/pixel ortho set is the SfS mapprojected images already produced (the
`map.tr1.tif`), gathered and renamed. Move them (they are big and the source map dir
is wiped after delivery), leaving the dropped offenders and the pyramids behind. The
native-GSD set is built with
`mapproject_native_res.sh` over the sub-1 m frames of the SfS set (paired with their
registered cameras), which mapprojects each at its own native resolution and writes
`gsd.csv`:

```bash
qsub -V -m n -r n -N natres -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=2:00:00 \
  -- mapproject_native_res.sh lists/native_res_images.txt lists/native_res_cameras.txt \
     ref/lola_1mpp.tif map_images_native_res $(pwd)
```

Build pyramids (`stereo_gui --create-image-pyramids-only`) on the DEMs, mosaics, and
colorized bands for fast viewing. Keep the `readme.md` terse (mirror a prior delivery
readme) and git-track it and `inventory.yaml` with the project notes. The heavy
rasters, orthos, and cameras are data and are not version-controlled.

`inventory.yaml` fields:

- the base terrain
- the final bundle-adjust (or jitter) prefix whose linear-reduced adjusted CSM `.json` cameras are delivered
- the SfS and blended terrains with their logs
- the height-error map
- both ortho mosaics
- the two image-id lists (`ba_image_ids_path`, `sfs_image_ids_path`)
- the two orthoimage directories (1 m/pixel and native-GSD, the latter with a per-image GSD CSV)
- the SfS-to-LOLA numeric disparity bands (`sfs_to_lola_corr_dh_path`, `sfs_to_lola_corr_dv_path`)

## Recipes

### Stereo pairs for an initial DEM and bundle-adjusted cameras

Running stereo is only necessary when USGS-produced aligned cameras for the site
are not available. When they exist, use them directly and skip this recipe. The
ASP SfS documentation covers using these well-registered cameras:
[Incorporation of well-registered images](https://stereopipeline.readthedocs.io/en/latest/sfs_usage.html#usgs-reg).

Otherwise, build stereo pairs from the bundle-adjustment convergence-angle file,
which lists the 25th-percentile convergence angle (column 2) and the match count
(column 5) per image pair. Select the well-converged, well-matched pairs with
`stereo-from-ba`:

```bash
stereo-from-ba baD/baD bundle_adjust_components.json --use_ba_mapproj_tifs \
  --max_residual_error 1.25 --max_mapproj_error 1.75 > STEREO_PAIR_LIST.txt
```

### Collecting mapprojected footprints into a GeoPackage

```bash
source bin/sfs_utilities.sh
collect_geojson ./IMAGES 'map.mask.geojson' > all_mask_footprints.geojson
update-db ./footprints.gpkg ./shadow_mask_footprints.gpkg ./all_mask_footprints.geojson
```
