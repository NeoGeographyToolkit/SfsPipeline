# SfsPipeline

Scripts supporting the practical operation of Shape-from-Shading (SfS) with the Ames Stereo Pipeline. Work in progress as of 2026/10.

The reference documentation is the [ASP SfS guide](https://stereopipeline.readthedocs.io/en/latest/sfs_usage.html). This repository covers practical aspects of producing SfS DEMs that the guide does not.

See [WORKFLOW.md](WORKFLOW.md) for an end-to-end example and [TIPS.md](TIPS.md) for handy one-liners.

## Installation

SfsPipeline is installed both locally and on the NASA HECC HPC. Some steps apply only to the HPC install.

1. Install ASP from the precompiled binaries ([instructions](https://stereopipeline.readthedocs.io/en/latest/installation.html#precompiled-binaries)); note the install folder for step 6.
2. Install [micromamba](https://mamba.readthedocs.io/en/latest/installation/micromamba-installation.html) if conda or mamba is not already available.
3. Install ISIS into a new conda environment named `isis` and set up its data area ([instructions](https://astrogeology.usgs.gov/docs/how-to-guides/environment-setup-and-maintenance/installing-isis-via-anaconda/)).
4. Clone the repository:
   ```bash
   git clone https://github.com/NeoGeographyToolkit/SfsPipeline.git
   cd SfsPipeline
   ```
5. Create the conda environment:
   ```bash
   micromamba env create -n SfsPipeline -f environment.yaml
   ```
6. Add the bin directory to PATH and set the ASP, ISIS, and data paths in `.bashrc` or `.zshrc`:
   ```bash
   export PATH="$PATH:/path/to/SfsPipeline/bin"
   export ISISDATA=/path/to/your/ISISDATA/
   export ISISROOT=/path/to/your/conda/envs/isis
   export ASPROOT=/path/to/your/extracted/ASP/
   ```
7. Activate the `SfsPipeline` conda environment to run the command-line tools. The bash and PBS scripts are on PATH regardless of the active environment.
8. Run `source init_asp.sh` for ISIS and ASP commands, or `source init_sfs.sh` for the SfsPipeline tools and GDAL.

## Utility scripts

`bin/sfs_utilities.sh` holds small bash helpers (geodiff statistics, LERC COG conversion, and others). Source it after `init_asp.sh`:

```bash
source bin/sfs_utilities.sh
```

## QGIS helpers

`bin/startup.py` adds QGIS enhancements. Symlink it into the QGIS startup location for the platform, per the [QGIS documentation](https://docs.qgis.org/testing/en/docs/pyqgis_developer_cookbook/intro.html#the-startup-py-file).

## Script types

- Python: preprocessing and analysis, installed as PATH entry points, run locally or on a PFE node.
- PBS (`.pbs`): run only on the HPC under the PBS job manager.
- Bash: utilities in `bin` used by the other scripts.

## PBS scripts

PBS scripts are self-submitting workflows configured through environment variables. They perform no real work unless `SUBMIT=true` is set; otherwise they only locate files and prepare output folders, which is useful for inspection. Setting `DEBUG=true` steps through the script command by command. On submission a 15-second pause allows cancellation, and `qdel` cancels a job afterward.

Typical sequence:

```bash
unset SUBMIT
export DEBUG=true   # dry run, inspect
unset DEBUG
export SUBMIT=true  # submit to PBS
```

## Recommended practice

Create a work directory per SfS terrain area. Keep a log file (for example a markdown file) documenting each step and command.

## Workflow

The pipeline has two layers: lightweight command-line tools (installed as PATH entry points) that handle discovery, verification, and selection, and PBS scripts that run the heavy compute (mapproject, bundle adjust, SfS) on the HPC. See [WORKFLOW.md](WORKFLOW.md) for the full end-to-end example with the PBS steps.

Main SfS path, high-level order of operations:

1. `make-index` builds the geoparquet cumulative index files.
2. `sfs-cover` selects candidate images for an ROI from the index.
3. `find-image-overlaps` builds the bundle-adjust pairs list from overlapping, similarly-illuminated footprints.
4. Bundle adjust the images (PBS), the single most important step for SfS quality.
5. `verify-ba` inspects graph connectivity and reports the largest connected camera group; images outside it are dropped.
6. `lit-select` picks a well-illuminated image subset per SfS tile.
7. Run SfS (PBS), optionally with a preview pass hillshade-aligned to LOLA before a final pass.

`solar-az-plot` is an optional illumination check that animates footprint coverage by solar azimuth.

Optional stereo survey: where stereo coverage exists, `find-stereo` surveys stereo availability, `stereo-from-ba` lists runnable stereo pairs from the largest connected group, and `tri-plot` plots triangulation-error images. For sparse polar coverage this branch is usually skipped in favor of more complete bundle adjustment (see WORKFLOW.md).

## Script reference

All scripts live in `bin`.

### Shell scripts

- `init_asp.sh`: initialize the ASP and SfsPipeline environment.
- `init_isis.sh`: initialize the ISIS conda environment.
- `init_sfs.sh`: initialize the SfsPipeline environment (ASP bin not on PATH).
- `sfs_utilities.sh`: bash helper functions for SfS processing. Source to load.
- `calibrate_edr.sh`: ISIS calibration and CSM camera generation.
- `db_to_urls.sh`: produce NAC IMG download URLs from a GPKG source file.
- `stereo.sh`: stereo processing.
- `shadow_mask.sh`: compute shadow masks.
- `random_sample.sh`: take a random sample from a list file.
- `ds_by_attr.sh`: subset a GPKG file by an attribute value range.
- `prepare_ba0_lists.sh`: prepare lists for bundle adjust (deprecated).
- `rescale_raster.sh`: scale a floating-point image to 8 bit (deprecated).
- `make_lerc_cog.sh`: make LERC COGs (deprecated).
- `launch_mapproj_jobs.sh`: launch many mapproject jobs (deprecated).
- `launch_stereo_jobs.sh`: launch many stereo jobs (deprecated).

### QGIS helper scripts

- `startup.py`: QGIS plugin main file.
- `raster_matcher.py`: QGIS plugin to locate TIF files from a vector layer.
- `add_rat_to_vrt.py`: add a Raster Attribute Table to max-lit index files so QGIS maps DN values to source LROC NAC product IDs.

### PBS scripts

- `bundle_adjust_pairwise_pt1.pbs`: IP matching prior to bundle adjustment, many nodes.
- `bundle_adjust_pt0.pbs`: bundle adjust step 0, many nodes (deprecated).
- `bundle_adjust_pt1.pbs`: bundle adjust step 1, many nodes (deprecated).
- `bundle_adjust_pt2.pbs`: optimize cameras and refine to topography, one node.
- `calibrate_edr.pbs`: calibrate IMG to CUB and generate CSM cameras, many nodes.
- `gdal_footprints.pbs`: create footprint geojson files, many nodes (deprecated).
- `launch_stereo.pbs`: run stereo, many nodes (deprecated).
- `make_lerc_cogs.pbs`: convert TIF files to LERC COGs, many nodes (deprecated).
- `mapproj_ba.pbs`: mapproject with bundle-adjusted cameras and topography, many nodes; also computes footprints.
- `mapproj_noba.pbs`: mapproject with topography and no bundle-adjusted cameras, many nodes; also computes footprints.
- `run_command_list.pbs`: run arbitrary command lists, many nodes.
- `run_geodiffs.pbs`: run many geodiff calls, many nodes.
- `run_hillshade_align.pbs`: hillshade-align two DEMs, one node.
- `run_count_lit.pbs`: SfS count map for one tile, one node.
- `run_dem_mosaic.pbs`: merge DEM tiles with dem_mosaic, one node.
- `run_image_correlation.pbs`: image correlation (deprecated).
- `run_mapproj.pbs`: mapproject one image, one node (deprecated).
- `run_max_lit_indexes.pbs`: SfS max-lit index map for one tile, one node.
- `run_max_lit.pbs`: SfS max-lit map for one tile, one node.
- `run_point2dem.pbs`: run point2dem for a stereo job.
- `run_stereo.pbs`: run one stereo pair as a job.
- `run_sfs_blend.pbs`: SfS blend step, one node.
- `serve_folder.pbs`: serve a folder from NAS over HTTP for viewing COGs.
- `sfs_exposures.pbs`: precompute SfS exposure lists (deprecated).
- `sfs.pbs`: run SfS, or height-uncertainty jobs, on one or many nodes.
- `shadow_mask.pbs`: generate shadow-mask TIF files and footprint geojsons, many nodes.

## Command-line tools

### Make index

`make-index` processes CUMINDEX.LBL and CUMINDEX.TAB from `~/LRO_EDR_CUMINDEX/` (they must be present there, or symlinked) into parquet files in /tmp. It takes about two minutes. Each parquet file embeds provenance metadata: UTC timestamp, user, hostname, and the md5sum of CUMINDEX.TAB.

```bash
make-index
```

### SFS cover

`sfs-cover` selects observations for an ROI. GeoPackage output suits the few thousand observations a typical ROI yields.

```bash
sfs-cover \
  --db_path /tmp/lroc_cumulative_south_polar.parquet \
  -p "POLYGON((72471 158818,128309 158818,128309 119030,72471 119030,72471 158818))" \
  -t mons_mouton_regional \
  --gpkg /tmp/mons_mouton_regional.gpkg
```

Provenance metadata propagates from the source parquet file into the output.

### Getting updated footprints

Footprints in the geodatabase can be refreshed to reflect mapprojected footprints, with or without bundle-adjusted cameras, and illuminated-versus-shadowed areas from shadow masks. The process:

1. Generate footprint geojsons via mapproject, or shadow_mask.pbs for shadow masks.
2. Collect them with `collect_geojson` from `bin/sfs_utilities.sh`.
3. Run `update-db` to write a new GPKG combining the geodatabase metadata with the new footprints.

Example after mapprojection:

```bash
source bin/sfs_utilities.sh
collect_geojson_stream IMAGES 'map.noba.geojson' > noba_footprints.geojson
update-db SOURCE.gpkg TARGET_noba_footprints.gpkg noba_footprints.geojson
```

With shadow masks:

```bash
export INPUT_DIR="IMAGES"
export TIF_POSTFIX='map.noba.tif'
shadow_mask.pbs
# after the PBS job completes:
source bin/sfs_utilities.sh
collect_geojson_stream IMAGES 'map.noba.mask.geojson' > mask_noba_footprints.geojson
update-db SOURCE.gpkg TARGET_mask_noba_footprints.gpkg mask_noba_footprints.geojson
```

### Determining pairs for bundle adjust

Bundle adjust benefits from an overlap list that pairs only images that overlap spatially and share similar illumination geometry. `find-image-overlaps` builds a connectivity graph from the sfs-cover geodatabase, optionally updated with mapprojected or shadow-mask footprints, and reports its structure.

The tool is resource intensive. Run it on a debug or devel PBS node with 4 to 8 cores; it takes about two minutes.

Run with `--check_connectivity` to evaluate connectivity for a maximum sub-solar ground azimuth difference set by `--max_diff_slrgaz`:

```bash
find-image-overlaps \
  --check_connectivity \
  -d ./mask_noba_footprints.gpkg \
  --max_diff_slrgaz=12
```

The output is a JSON summary:

```json
{
  "is_connected": true,
  "num_pairs": 36574,
  "num_components": 1,
  "component_sizes": [1514],
  "num_pairs_per_component": [36574]
}
```

Key fields: `is_connected` reports whether every image is used (rarely true), `num_components` is the number of fully connected subgraphs, `component_sizes` lists the image count per subgraph (largest first), and `num_pairs` is the pair count of the largest subgraph, written to the overlap list.

Re-run with different `--max_diff_slrgaz` values to reach a single connected component without generating too many pairs. Values above 10 degrees produce unnecessarily many pairs; 6 to 8 degrees give large but manageable lists. A useful target is fewer pairs than the image count times a typical bundle-adjust window of 25 to 50.

Once satisfied, re-run without `--check_connectivity` to write the overlap list:

```bash
find-image-overlaps \
  --image_dir='IMAGES/' \
  -d ./mask_noba_footprints.gpkg \
  --max_diff_slrgaz=8 \
  > OVERLAP_LIST_SLRGAZ_8.txt
```

The emitted paths are `<image_dir>/<product_id><postfix>`. The postfix defaults to `.ech.cub` (`--image_filename_postfix`), and `--image_dir` defaults to `<cwd>/IMAGES/`. Override the postfix if your cubes use a different stem.

Build the image, camera, and mapprojected lists from the overlap list:

```bash
source bin/sfs_utilities.sh
unique_from_pairs OVERLAP_LIST_SLRGAZ_8.txt > IMAGES.txt
sed 's/.cub/.json/g' IMAGES.txt > CAMERAS.txt
sed 's/.cub/.map.noba.tif/g' IMAGES.txt > MAPPROJ_DATA.txt
echo "path_to_dem.tif" >> MAPPROJ_DATA.txt
```

### Downloading EDRs fast

`db_to_urls.sh` (in bin) converts a GeoPackage from sfs-cover into NAC IMG download URLs. By default it uses the USGS AWS mirror of the LROC NAC PDS data. Prefer the IM server (the `im` argument) to avoid a large bill to USGS.

```bash
db_to_urls.sh lrocedrlist.gpkg im \
  | xargs -n 1 -P 8 -I {} wget {} -P ~/nobackup/LROCNACEDR/
```

Downloads parallelize well; roughly 600 GB completes in 10 to 15 minutes.

### First round ba0 bundle adjust

Build the image, camera, and mapprojected lists from the overlap list as shown in "Determining pairs for bundle adjust" above (`unique_from_pairs` plus `sed`).

The older `prepare_ba0_lists.sh` wrapper, which builds the three lists from a plain sub-solar-ground-azimuth-ordered product-id list, is deprecated and kept only for reference:

```bash
cd folder/with/cubsandtifsandjsons
# images.txt is the sub-solar ground azimuth ordered list of product ids
cat ../images.txt | prepare_ba0_lists.sh
echo "path/to/dem.tif" >> MAPPROJ_DATA.txt
```

### Verify the bundle adjustment

Inspect graph connectivity after bundle adjustment with `verify-ba`:

```bash
verify-ba 'baB/baB' \
  --min_match_count=10 \
  --max_residual_error=2.0 \
  | jq '.component_sizes'
```

Select stereo pairs only from the largest connected component; images outside it form disconnected islands and are dropped from later stereo, bundle adjust, and SfS. Iterate over `--min_match_count` (for example 4, 5, 6) to see how the largest component changes. Export the result for later use:

```bash
verify-ba 'baB/baB' \
  --min_match_count=10 \
  --max_residual_error=2.0 \
  > baB_comps.json
```
