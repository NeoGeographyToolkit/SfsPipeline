# End-to-end SfS workflow

This is the practical, runnable sequence for producing a large-scale
Shape-from-Shading (SfS) DEM with the Ames Stereo Pipeline, from terrain
preparation through bundle adjustment, SfS, and jitter. It follows the
large-scale section of the [ASP SfS guide](https://stereopipeline.readthedocs.io/en/latest/sfs_usage.html)
and drives the scripts in `bin/`.

The original Mons Mouton / 1414a workflow was developed by Dr. Andrew M. Annex.
This version wires in the batch execution scripts and keeps their conventions.

## Conventions

- Every heavy step runs on a compute node through `qsub`. The head node is used
  only for trivial list-building and inspection. Do not run multi-thread work on
  a front-end node.
- Worker scripts are plain `.sh` (or `.py`); they do the work and take the
  project work directory as their last positional argument, always passed as
  `$(pwd)`. There are no self-submitting `.pbs` scripts.
- Set the PBS allocation once as an environment variable and pass it to every
  `qsub`; nothing hardcodes an allocation:

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
  suggested walltimes below are starting points; tune them to your site size.
  On a non-interactive ssh, `qsub` may not be on PATH; use `/PBS/bin/qsub`
  (Pleiades) or `/opt/pbs/bin/qsub` (Athena front end).

- Activate the environment first (`source init_asp.sh`), which puts `bin/` plus
  the ASP and ISIS tools on PATH and sets `ASPROOT`, `ISISROOT`, `ISISDATA`.

## 1. Reference terrain preparation

Regrid a LOLA source DEM to the target projection, resolution, and a half-integer
extent (so 1 m pixel centers land on integers, required by `sfs_blend`; see the
terrain-bounds section of the SfS guide). `make_ref_dem.sh` wraps `gdalwarp`
(cubic spline, 256-block tiling) and an optional spike blur. Build it on a
compute node, not the head node. Suggested walltime 1:00:00.

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

Discovery is local and fast. Two front ends are available; use either.

Cumulative-index front end: `make-index` builds geoparquet index files from
CUMINDEX.LBL/TAB in `~/LRO_EDR_CUMINDEX/` (about two minutes, embeds provenance),
then `sfs-cover` selects the observations for an ROI polygon into a GeoPackage:

```bash
make-index
sfs-cover \
  --db_path /tmp/lroc_cumulative_south_polar.parquet \
  -p "POLYGON((72471 158818,128309 158818,128309 119030,72471 119030,72471 158818))" \
  -t my_roi --gpkg /tmp/my_roi.gpkg
```

ODE front end (standalone, no index needed):

```bash
query_lro.sh --dem ref/lola_1mpp.tif --margin-km 1.0 \
  --min-incidence 70 --max-incidence 90 \
  --output-urls lists/urls.txt --output-products lists/products.txt
```

Download the EDRs. From a GeoPackage, `db_to_urls.sh` emits the IMG URLs (pass
`im` to use the IM server and avoid billing the USGS mirror); or feed
`download_all.sh` the ODE URL list. Run on a front end (it has network); roughly
600 GB completes in 10 to 15 minutes.

```bash
db_to_urls.sh /tmp/my_roi.gpkg im | xargs -n 1 -P 8 -I {} wget {} -P img/
# or: download_all.sh lists/urls.txt
```

Batch ingest (fetch + lronac2isis + spiceinit + lronaccal + lronacecho +
`isd_generate --reduction linear`). Suggested walltime 2:00:00:

```bash
qsub -m n -r n -N calib -q normal \
  -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=40:model=cas_ait -l walltime=2:00:00 \
  -- batch_prepare_lro.sh lists/products.txt img $(pwd)
```

## 3. Image selection and sorting by illumination

Get each camera's Sun azimuth and sort the list by it, so that the later
`--overlap-limit` in bundle adjustment pairs images of similar illumination
(matched shadows). Low-signal / shadowed frames are culled by their max value.

```bash
sfs_query.sh img/*.cal.echo.cub > lists/azimuth_tables.txt   # sfs --query
sort -k3,3 -n lists/azimuth_tables.txt > lists/azimuth.txt
awk '{print $1}' lists/azimuth.txt > lists/azimuth_images.txt
filter_by_max.sh lists/azimuth_map.txt lists/filtered_map.txt $(pwd) 0.005
```

For very large sites, thin to a minimal-but-covering subset per quadrant with
`split_quadrants.py`, `prepare_lowres.sh`, and `image_subset_2x.sh`.

Optionally refresh the GeoPackage footprints to reflect the actual mapprojected
(and shadow-masked, hence lit) extents, then check camera-graph connectivity
with `find-image-overlaps`. This is a validation and downselect step: the matcher
in bundle adjustment is our azimuth-sort plus `--overlap-limit`, not the
azimuth-restricted overlap graph. After mapprojection (step 4):

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
list into chunks and submits one node per chunk; `mapproject_chunk.sh` is the
per-node worker it `qsub`s (so you run `batch_mapproject.sh` on the head node and
it submits the chunks). Control the grid and extent through environment
variables; chunks finish in a few hours at most.

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
solve yet). We use our own IP detection (`--ip-detect-method 0`,
`--match-first-to-last`) and `--overlap-limit` over the azimuth-sorted list, not
a Sun-azimuth-restricted overlap graph. Suggested walltime up to a day on 8-16
nodes (matching parallelizes well; often finishes in a few hours).

```bash
qsub -m n -r n -N ba_match -q normal \
  -W group_list=$groupName -j oe -S /bin/bash \
  -l select=10:ncpus=28:model=bro_ele -l walltime=23:00:00 \
  -v "IMG_DIR=img,OVERLAP_LIMIT=75,NUM_ITERATIONS=0,PROCESSES=10,THREADS=8" \
  -- bundle_adjust.sh lists/filtered_map.txt ref/lola_1mpp.tif maps ba/run $(pwd)
```

### 5b. Controlled refine chain (fixed -> free -> heights-from-dem)

`bundle_adjust_refine.sh` reuses the harvested matches and runs one stage per
call, from most-constrained to least and back to the ground. Run each as its own
single-node job; each waits for the previous. Suggested walltime 8:00:00 each.

```bash
# Stage 1: fixed - registered anchor cameras hold the frame
qsub -m n -r n -N ba_fix -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=8:00:00 \
  -v "FIXED_LIST=lists/anchor_images.txt" \
  -- bundle_adjust_refine.sh lists/filtered_images.txt lists/filtered_cameras.txt \
     ba/run ba_fix $(pwd)

# Stage 2: free - relax all cameras, no external constraint (feeds on ba_fix)
qsub -m n -r n -N ba_free -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=8:00:00 \
  -- bundle_adjust_refine.sh ba_fix/run-image_list.txt ba_fix/run-camera_list.txt \
     ba/run ba_free $(pwd)

# Stage 3: dem - final tighten to the reference terrain (feeds on ba_free)
qsub -m n -r n -N ba_htdem -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=8:00:00 \
  -v "REF_DEM=ref/lola_1mpp.tif" \
  -- bundle_adjust_refine.sh ba_free/run-image_list.txt ba_free/run-camera_list.txt \
     ba/run ba_htdem $(pwd)
```

Validate each stage: the median reprojection error per camera in
`<outDir>/run-final_residuals_stats.txt` should fall to about 1-2 px. Then check
the camera graph with `verify-ba`, which uses the match-offset and residual
stats to report the largest connected component; images outside it are dropped
from SfS. Iterate `--min_match_count` to see how the component changes:

```bash
verify-ba ba_htdem/run --min_match_count=10 --max_residual_error=2.0 | jq '.component_sizes'
verify-ba ba_htdem/run --min_match_count=10 --max_residual_error=2.0 > ba_htdem_comps.json
```

## 6. Alignment to the ground and registration refinement

Where a horizontal shift against LOLA remains, measure it by correlating
hillshades and turn it into ground control. `hillshade_correlator.sh` produces
the DEM-to-DEM disparity; `dem2gcp.sh` turns that disparity into a GCP file;
then a short `bundle_adjust` (or `trans_gcp.sh`) pulls the cameras into the LOLA
frame. Suggested walltime 1:00:00 (correlation) + 2:00:00 (solve).

```bash
qsub -m n -r n -N hcorr -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=20:model=bro_ele -l walltime=1:00:00 \
  -- hillshade_correlator.sh sfs_dem.tif ref/lola_1mpp.tif $(pwd) hcorr 25
```

Alternatively align the produced DEM directly with `pc_align` (see the pc-align
guidance in the ASP manual).

## 7. Shape-from-Shading

### 7a. Tile the reference DEM

Tile into roughly 4k x 4k padded tiles so SfS runs as many independent per-tile
jobs that are merged afterwards. Local, fast:

```bash
tile_dem.py ref/lola_1mpp.tif 4000 4000 tiles 200
```

### 7b. Run parallel_sfs per tile

`launch_sfs_tiles.sh` submits one SfS job per tile (`parallel_sfs.sh` is the
per-tile worker). A 4k tile is roughly 4-7 h on 4 `bro_ele` nodes. Suggested
walltime 20:00:00 for the batch; `estimError=0` for the SfS pass.

```bash
export MODEL=bro_ele NCPUS=28
launch_sfs_tiles.sh tiles lists/filtered_images.txt ba_htdem/run \
  lists/exposures.txt sfs 0 $(pwd)
```

### 7c. Merge the tiles

```bash
qsub -m n -r n -N sfs_merge -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=4:00:00 \
  -- dem_mosaic_list.sh lists/sfs_tiles.txt sfs_dem.tif $(pwd)
```

Inspect: `geodiff` the SfS DEM against the reference and hillshade both; there
should be no tile seams and no large bias.

## 8. Blending and mosaics

Blend the SfS result back toward the reference where there is little
illumination signal (`sfs_blend`, keep Andrew's recipe), and build the max-lit
and count mosaics for QA.

```bash
qsub -m n -r n -N maxlit -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=1:00:00 \
  -- dem_mosaic_list.sh lists/sfs_maps.txt max_lit.tif $(pwd) --max
```

## 9. Post-SfS registration (optional)

Render an SfS-simulated view per camera, `image_align` it to the real
mapprojected image to measure the residual pixel shift, and `gcp_gen` a
corrective GCP; feed the GCPs into a final joint solve or `trans_gcp.sh`. Use
`ALIGN_THRESH=0` to force a GCP for every image. Suggested walltime 8:00:00.

```bash
qsub -m n -r n -N sim_align -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=8:00:00 \
  -v "ALIGN_THRESH=0" \
  -- batch_sfs_sim.sh lists/filtered_images.txt 1 99999 sfs_dem.tif img \
     ba_htdem/run sim $(pwd)
```

## 10. Height-uncertainty map

Re-run `parallel_sfs.sh` with `estimError=1` on the produced SfS DEM to write a
`-height-error.tif`. This pass is single-core per tile and slower; budget it
separately.

```bash
launch_sfs_tiles.sh tiles lists/filtered_images.txt ba_htdem/run \
  lists/exposures.txt sfs 1 $(pwd)
```

## 11. Jitter (optional)

If a residual low-frequency bend remains in the linescan cameras, refine the
per-line poses with `jitter_solve.sh`, constrained to the reference DEM and the
clean matches from bundle adjustment. Suggested walltime 8:00:00.

```bash
qsub -m n -r n -N jitter -W group_list=$groupName -j oe -S /bin/bash \
  -l select=1:ncpus=28:model=bro_ele -l walltime=8:00:00 \
  -- jitter_solve.sh ba_htdem clean_matches jitter ref/lola_1mpp.tif $(pwd)
```

## 12. Delivery

Fill in `inventory.yaml` in the project directory with the base terrain, final
bundle-adjust prefix, SfS and blended terrains, logs, and the orthoimage
directory, so the project is self-describing when handed off.
