# End-to-end SfS workflow

This is the practical, runnable sequence for producing a large-scale
Shape-from-Shading (SfS) DEM with the Ames Stereo Pipeline, from terrain
preparation through bundle adjustment, SfS, re-registration to LOLA, and
blending. It follows the large-scale section of the
[ASP SfS guide](https://stereopipeline.readthedocs.io/en/latest/sfs_usage.html)
and drives the scripts in `bin/`.

The original framework was developed by Andrew Annex.

## Conventions

- Every heavy step runs on a compute node through `qsub`. The head node is used
  only for trivial list-building and inspection. Do not run multi-thread work on
  a front-end node.
- Worker scripts are plain `.sh` (or `.py`). They do the work and take the
  project work directory as their last positional argument, always passed as
  `$(pwd)`. There are no self-submitting `.pbs` scripts.
- Workers thread to the PBS-provided core count (`$NCPUS`), not `nproc` (which
  can report 1 inside a PBS job). Set `NCPUS`/`MODEL` where a step takes them.
- Set the PBS allocation once as an environment variable and pass it to every
  `qsub`. Nothing hardcodes an allocation:

```bash
export groupName=your_allocation   # e.g. the group_list for your project
```

- The canonical submission form is:

```bash
qsub -m n -r n -N <name> -q normal \
  -W group_list=$groupName -j oe -S /bin/bash \
  -l select=<N>:ncpus=<C>:model=<model> -l walltime=<HH:MM:SS> \
  -- <script>.sh <args...> $(pwd)
```

  Node models and core counts (`bro_ele` 28, `cas_ait` 40, `rom_ait` 128) and the
  suggested walltimes below are starting points. Tune them to your site size.
  On a non-interactive ssh, `qsub` may not be on PATH. Use `/PBS/bin/qsub`
  (Pleiades) or `/opt/pbs/bin/qsub` (Athena front end).

- Activate the environment first (`source init_asp.sh`), which puts `bin/` plus
  the ASP and ISIS tools on PATH and sets `ASPROOT`, `ISISROOT`, `ISISDATA`.
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
  `_blur.tif`. Use that only as a mapprojection drape, never as the height
  constraint, and let the name say so.

```bash
qsub -m n -r n -N ref_dem -q normal \
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

Discovery is local and fast. Two front ends are available. Use either.

Cumulative-index front end: `make-index` builds geoparquet index files from
CUMINDEX.LBL/TAB in `~/LRO_EDR_CUMINDEX/` (about two minutes, embeds provenance),
then `sfs-cover` selects the observations for an ROI polygon into a GeoPackage:

```bash
make-index
sfs-cover \
  --db_path lroc_cumulative_south_polar.parquet \
  -p "POLYGON((72471 158818,128309 158818,128309 119030,72471 119030,72471 158818))" \
  -t my_roi --gpkg my_roi.gpkg
```

ODE front end (standalone, no index needed):

```bash
query_lro.sh --dem ref/lola_1mpp.tif --margin-km 1.0 \
  --min-incidence 70 --max-incidence 90 \
  --output-urls lists/urls.txt --output-products lists/products.txt
```

Download the EDRs. From a GeoPackage, `db_to_urls.sh` emits the IMG URLs (pass
`im` to use the IM server and avoid billing the USGS mirror). Or feed
`download_all.sh` the ODE URL list. Run on a front end (it has network). Roughly
600 GB completes in 10 to 15 minutes.

```bash
db_to_urls.sh my_roi.gpkg im | xargs -n 1 -P 8 -I {} wget {} -P img/
# or: download_all.sh lists/urls.txt
```

Batch ingest (fetch + lronac2isis + spiceinit + lronaccal + lronacecho +
`isd_generate --reduction linear`). The linear ephemeris reduction shrinks each
CSM `.json` about tenfold with sub-millimeter `cam_test` agreement, and these
linear-reduced cameras are what ship at delivery. Suggested walltime 2:00:00:

```bash
qsub -m n -r n -N calib -q normal \
  -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=40:model=cas_ait -l walltime=2:00:00 \
  -- batch_prepare_lro.sh lists/products.txt img $(pwd)
```

## 3. Image selection and sorting by illumination

Get each camera's Sun azimuth and sort the list by it, so that the later
`--overlap-limit` in bundle adjustment pairs images of similar illumination
(matched shadows). Low-signal / shadowed frames are culled by their max value
(0.005 is the LRO NAC lit-vs-shadow cutoff). Inspect the max-value distribution
first and drop all-shadow and non-intersecting frames.

```bash
sfs_query.sh img/*.cal.echo.cub > lists/azimuth_tables.txt   # sfs --query
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
# report connectivity for a range of sub-solar ground-azimuth differences
find-image-overlaps --check_connectivity -d ./my_roi_mask.gpkg --max_diff_slrgaz=8
```

`find-image-overlaps` reports `is_connected`, `num_components`, and
`component_sizes` (largest first). Raise `--max_diff_slrgaz` until the graph is a
single connected component without producing too many pairs (6 to 8 degrees is
usually a good range). Images outside the largest component are dropped.

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
qsub -m n -r n -N ba_match -q normal \
  -W group_list=$groupName -j oe -S /bin/bash \
  -l select=10:ncpus=28:model=bro_ele -l walltime=8:00:00 \
  -v "IMG_DIR=img,OVERLAP_LIMIT=75,NUM_ITERATIONS=0,PROCESSES=10,THREADS=8" \
  -- bundle_adjust.sh lists/filtered_map.txt ref/lola_1mpp.tif maps ba/run $(pwd)
```

### 5b. Controlled refine chain (fixed -> free -> heights-from-dem)

`bundle_adjust_refine.sh` reuses the harvested matches and runs one stage per
call, from most-constrained to least and back to the ground. Run each as its own
single-node job. Each waits for the previous. Suggested walltime 8:00:00 each
(`bro_ele` rejects more than 8 hours).

```bash
# Stage 1: fixed - a set of well-registered cameras is held fixed and pulls the
# rest into their frame (on the Moon, the USGS South-Pole controlled cameras).
qsub -m n -r n -N ba_fix -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=8:00:00 \
  -v "FIXED_LIST=lists/usgs_fixed_images.txt" \
  -- bundle_adjust_refine.sh lists/filtered_images.txt lists/filtered_cameras.txt \
     ba/run ba_fix $(pwd)

# Stage 2: free - relax all cameras, no external constraint, reusing stage 1's
# clean matches so the network settles (feeds on ba_fix).
qsub -m n -r n -N ba_free -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=8:00:00 \
  -v "USE_CLEAN=1" \
  -- bundle_adjust_refine.sh ba_fix/run-image_list.txt ba_fix/run-camera_list.txt \
     ba_fix/run ba_free $(pwd)

# Stage 3: heights-from-dem - final tighten to the reference terrain (feeds on
# ba_free, reusing stage 1's clean matches).
qsub -m n -r n -N ba_htdem -W group_list=$groupName -j oe -S /bin/bash \
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

Before SfS, confirm the cameras co-register and remove any badly-posed ("whacky")
ones, whose stretched drape smears the mosaic. This is the go/no-go gate.

Mapproject the survivors with the final `ba_htdem` cameras, then build a max-lit
mosaic of each azimuth half and overlay them red/green: coincident terrain means
the cameras co-register. Red/green only on opposite crater walls is an
illumination difference (fine). A uniform offset of whole crater outlines is a
real misregistration. Then rank the per-camera bundle-adjust stats and prune:

```bash
# Flag whacky cameras from the ba_htdem per-camera stats. run-mapproj_match_offset_stats.txt
# (meters off consensus) is the best smear detector, run-camera_offsets.txt plus a low
# match count catches drifted dropouts, run-final_residuals_stats.txt (reproj px) is blind
# to a self-consistent-but-wrong pose. Defaults: offset-p95 > 5 m, reproj-med > 0.75 px,
# camera move > 1000 m, or matches < 50.
sfs_flag_bad_cameras.py ba_htdem/run -o lists/removed_ids.txt

# Rebuild the max-lit mosaic WITHOUT re-mapprojecting (the per-image *.map.tr1.tif survive):
# drop the removed ids from each chunk list and re-run dem_mosaic --max per chunk, halves, total.
sfs_prune_and_remosaic.sh map_htdem lists/removed_ids.txt $(pwd) 500 28
```

Verify a couple of flagged cameras visually before pruning, and after rebuilding
confirm the streaks are gone and the terrain did not move.

## 7. SfS image subset

The full image set is too expensive for the SfS solve, so pick a minimal-but-
covering subset. The grouping axis is the Sun azimuth ANGLE, not equal counts:
plot the rose first (`plot_sfs_azimuth.py`), then cut the site into fixed angle
slices of roughly 45 degrees, respecting the natural gaps. Keep a rare illumination
direction as its own whole group, drop empty slices, and lump a lone stray frame
into the adjacent slice. Do not blind-cut into four 90-degree quadrants. Each slice
is then thinned by `image_subset` (a crowded angle gets sparsed hardest, since it
only has to fill the same ground), for a primary cover plus an extra (2x) cover on
the remainder, driven by `sfs_select_full_site.sh` over low-resolution sub images
(`prepare_lowres.sh`). Validate with a max-lit of the selection against the
full-set max-lit.

```bash
sfs_select_full_site.sh lists/filtered_map.txt lists/azimuth.txt selection $(pwd) 0.05 28
```

Note on GSD: coarse frames hurt SfS and the max-lit mosaic. Ground area per pixel
scales as GSD squared, so a 2 m/pixel frame covers about 4x the real estate of a
1 m/pixel one, which is exactly why `image_subset`'s coverage-greedy ranking tends
to prefer the coarse frame when a finer one would be better. `query_gsd.sh` reports
each image's native ground sample distance; it also correlates with high
`mapproj_match_offset` (partly a coarseness proxy), so the coarsest tend to be
caught by the prune in step 6. Treat GSD over about 1.75 m as suspect and over 2 m
as a drop from the SfS subset, preferring a finer frame and keeping a coarse one
only as a last resort where it is the sole cover (gate on coverage holes first).
Drop only from the SfS subset, never from the bundle solve, where the large
footprints are tie-point coverage assets.

The `image_subset` coverage threshold (last arg above) starts at a low value; if it
barely thins, raising it to roughly 0.05 to 0.1 is usually wise, but that changes
which images SfS sees, so decide it deliberately rather than bumping it silently.

```bash
query_gsd.sh lists/filtered_images.txt lists/filtered_cameras.txt ref/lola_1mpp.tif \
  lists/gsd 2.0 $(pwd)
```

## 8. Shape-from-Shading

### 8a. Compute exposures (do this first)

`sfs --compute-exposures-only` writes one `run-exposures.txt` that every tile and
every later simulation reuses. Run it once over the selected set before tiling.

```bash
qsub -m n -r n -N sfs_exp -W group_list=$groupName -j oe -S /bin/bash \
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

Merge with a blended `dem_mosaic` (no `--max`, so tile seams stay smooth):

```bash
qsub -m n -r n -N sfs_merge -W group_list=$groupName -j oe -S /bin/bash \
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

```bash
# recompute exposures over the full set on the final sfs_dem first
sfs_exposures.sh lists/filtered_images.txt ba_htdem/run sfs_dem.tif exposures_all $(pwd)

qsub -m n -r n -N sim_align -W group_list=$groupName -j oe -S /bin/bash \
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
qsub -m n -r n -N hcorr -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=20:model=bro_ele -l walltime=1:00:00 \
  -- hillshade_correlator.sh sfs_dem.tif ref/lola_1mpp.tif $(pwd) hcorr_sfs_lola 25
```

If the shift is real (a roughly uniform few meters beyond LOLA's own slop), turn
the disparity into a GCP with `dem2gcp.sh` and run the GCP-driven per-line refine
`jitter_gcp.sh`. A rigid `bundle_adjust` under-corrects a spatially-structured
shift because the dense match network pins the relative geometry. The per-line
flex of jitter reproduces the structure a rigid shift cannot.

```bash
dem2gcp.sh sfs_dem.tif ref/lola_1mpp.tif hcorr_sfs_lola/run-F.tif \
  ba_htdem/run-image_list.txt ba_htdem/run-camera_list.txt ba_htdem/run 20 \
  sfs_ref_corr/run.gcp $(pwd)

# jitter re-registration. Finer orientation knots track the shift better, keep
# anchor strength through --anchor-dem-uncertainty (large = light), over-provision
# anchors and let the ratio caps prune. For a set with borderline/edge frames, set
# ANCHOR_DEM to a genuine DEM padded well beyond the domain (+4 km/side here) so the
# out-of-domain orientation knots still get anchors, keep heights/mapproj on the
# domain DEM.
qsub -m n -r n -N jitter -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=8:00:00 \
  -v "NUM_LINES_ORIENT=2000,MAX_NUM_TRI=80000,MAX_GCP_TO_TRI_RATIO=2.0,\
MAX_ANCHOR_TO_TRI_RATIO=1.0,ANCHOR_DEM_UNC=20,NUM_ANCHOR=1000" \
  -- jitter_gcp.sh ba_htdem/run-image_list.txt ba_htdem/run-camera_list.txt \
     ref/lola_1mpp.tif sfs_ref_corr/run.gcp ba_htdem/run jitter $(pwd)
```

Then redo SfS (repeat step 8, reusing the exposures since the pose change is
sub-pixel) with the `jitter/run-...-adjusted_state.json` cameras. De-risk with a
few spread tiles first to confirm the bias collapsed, then run the full set.
Verify: `geodiff` versus LOLA (dz near zero) and `hillshade_correlator.sh` dx/dy
versus LOLA now near zero, plus `geodiff` versus the original `sfs_dem.tif`
showing the corrective move.

## 10. Blending and mosaics

On the final (re-registered) SfS DEM, build the ortho mosaics and blend the DEM
back toward the reference where there is little illumination signal
(`sfs_blend.sh`, keeping the tuned parameters from the ASP manual). The blended
DEM's hillshade is the delivery hillshade. Build it with
`gdaldem hillshade -multidirectional -compute_edges -alt 10 sfs_dem_blend.tif sfs_dem_blend_hill.tif`
(crisper and with more shadow detail than ASP `hillshade -e 10`. The grazing-light
ASP hillshade is kept only for the DEM-to-DEM correlation step, not for delivery).

Both ortho mosaics are delivered, with distinct roles:
- The **max-lit** mosaic (`dem_mosaic --max`) keeps the brightest pixel per
  location. It is the matching orthoimage shipped with the DEM, the input to
  `sfs_blend`, and the best view for spotting shadow coverage and camera-
  registration smears.
- The **average (blend)** mosaic (`blend_img_mosaic.sh`, a seamless grassfire
  blend with shadow pixels masked) is an additional product customers have asked
  to receive as well as the max-lit one.

```bash
# Build the max-lit mosaic (the matching ortho and the sfs_blend input)
qsub -m n -r n -N maxlit -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=1:00:00 \
  -- dem_mosaic_list.sh lists/sfs_maps.txt max_lit.tif $(pwd) --max

# Build the average (blend) ortho mosaic - an additional delivered product.
# Build it over the SAME images as the max-lit mosaic (the SfS set), then snap
# it onto the delivered LOLA grid with regrid_to_grid.sh so it matches the
# max-lit mosaic pixel for pixel.
qsub -m n -r n -N blendmos -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=1:00:00 \
  -- blend_img_mosaic.sh lists/sfs_maps.txt average_mosaic_raw.tif 0.005 $(pwd)
regrid_to_grid.sh average_mosaic_raw.tif average_mosaic.tif \
  "<xmin ymin xmax ymax>" 1 $(pwd)

# Blend SfS DEM with reference DEM in permanently shadowed areas
qsub -m n -r n -N sfs_blend -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=1:00:00 \
  -- sfs_blend.sh ref/lola_1mpp.tif sfs_dem.tif max_lit.tif $(pwd)
```

## 11. Height-uncertainty map (optional)

Re-run the SfS worker with `estimError=1` to write a `-height-error.tif` per tile.
This pass evaluates height perturbations on the FINAL produced SfS DEM (the blend),
not on LOLA, so run it only after the blend is settled: tile the final blended DEM
into the same tile grid, then launch with `estimError=1`. It is single-core per tile
and slower. Budget it separately. Finally mosaic the per-tile error maps into the
delivered `height_uncertainty.tif`.

```bash
# tile the final blended SfS DEM onto the same tile grid
tile_dem.py sfs_dem_blend.tif 4000 4000 tiles_blend 200

# uncertainty pass (estimError=1, tiles are from the blend, not LOLA)
export QUEUE=long
launch_sfs_tiles.sh tiles_blend lists/secondary_images.txt ba_htdem/run \
  exposures_sec/run-exposures.txt sfs_err 1 $(pwd)

# mosaic the per-tile error maps into the delivered product
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
  `sfs_dem_blend_lola-diff.tif` geodiff. An optional `height_uncertainty.tif`.
- Ortho mosaics: `max_lit_mosaic.tif` and `average_mosaic.tif`, on the same grid.
- Image-id lists: `bundle_adjust_image_ids.txt` (the full bundle-adjust input) and
  `sfs_image_ids.txt` (the SfS subset). Ship both as text. Deliver as images and
  cameras ONLY the SfS subset. Document the larger bundle-adjust set in the list but
  do not ship its images or cameras (no dead weight).
- Cameras (when requested): `cameras/` with the final jitter (or bundle-adjust)
  linear-reduced adjusted CSM `.json`, one per shipped image.
- Ortho directories (subdirectories of the results dir): `map_images/` (every
  shipped SfS ortho at 1 m/pixel) and `map_images_native_res/` (the sub-1 m frames at
  their own native GSD, with `gsd.csv`). The native-res orthos are mapprojected with
  the same registered cameras. Record the real output pixel size in `gsd.csv`, read
  back from each ortho.
- Disparity to LOLA: `sfs_to_lola_corr/` with the after-registration SfS-to-LOLA
  horizontal disparity as colorized GeoTIFFs (`colormap` on a fixed symmetric scale),
  one band east-west and one north-south.

Region of interest and cropping: SfS is run on a domain padded beyond the product
ROI. Either crop every product to the ROI (snap the ROI box to the domain pixel
grid, `gdal_translate -projwin`, lossless) or deliver the full domain as insurance
against boundary artifacts and include the ROI polygon (`product_roi.gpkg`) so the
recipient can crop. Record the choice. Registration degrades toward the domain edges.

The 1 m/pixel ortho set is the SfS mapprojected images already produced (the
`map.tr1.tif`), gathered and renamed. The native-GSD set is built with
`mapproject_native_res.sh` over the sub-1 m frames of the SfS set (paired with their
registered cameras), which mapprojects each at its own native resolution and writes
`gsd.csv`:

```bash
qsub -m n -r n -N natres -W group_list=$groupName -j oe -S /bin/bash \
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
