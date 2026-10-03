# SfsPipeline

Scripts supporting the practical operation of Shape-from-Shading (SfS) with the Ames Stereo Pipeline. The reference documentation is the [ASP SfS guide](https://stereopipeline.readthedocs.io/en/latest/sfs_usage.html).

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
7. Activate the `SfsPipeline` conda environment to run the command-line tools. The bash worker scripts in bin/ are on PATH regardless of the active environment.
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
- Bash workers (`.sh`): do the actual processing (mapproject, bundle adjust, SfS, mosaicking, and so on). They take the project work directory as their last argument and are submitted to the HPC with an explicit `qsub` (see below). A few lightweight ones run locally.

## Running jobs on the HPC

Heavy work runs on a compute node through `qsub`; the head node is used only for trivial list-building and inspection. There are no self-submitting `.pbs` scripts: you submit a worker `.sh` yourself, passing `$(pwd)` as its last argument and your PBS allocation through an environment variable so nothing is hardcoded:

```bash
export groupName=your_allocation
qsub -m n -r n -N <name> -q normal \
  -W group_list=$groupName -j oe -S /bin/bash \
  -l select=<N>:ncpus=<C>:model=<model> -l walltime=<HH:MM:SS> \
  -- <script>.sh <args...> $(pwd)
```

See [WORKFLOW.md](WORKFLOW.md) for the full end-to-end sequence with a ready `qsub` command and a suggested walltime for each step.

## Recommended practice

Create a work directory per SfS terrain area. Keep a log file (for example a markdown file) documenting each step and command.

## Workflow

The pipeline has two layers: lightweight command-line tools (installed as PATH entry points) that handle discovery, verification, and selection, and bash worker scripts submitted with `qsub` that run the heavy compute. [WORKFLOW.md](WORKFLOW.md) is the runnable end-to-end sequence with a `qsub` command and suggested walltime for every step.

Main SfS path, high-level order of operations:

1. Prepare the reference terrain: `make_ref_dem.sh` regrids the LOLA DEM to the target grid and half-integer bounds.
2. Fetch and calibrate the NAC images: discover with `sfs-cover` (or `query_lro.sh`), download, then `batch_prepare_lro.sh`.
3. Sort images by Sun azimuth and cull shadowed frames (`sfs_query.sh`, `filter_by_max.sh`).
4. Mapproject onto the reference DEM (`batch_mapproject.sh`).
5. Bundle adjust: harvest matches (`bundle_adjust.sh`, `NUM_ITERATIONS=0`) then the refine chain (`bundle_adjust_refine.sh`). This is the single most important step for SfS quality.
6. Validate the camera graph with `verify-ba` and drop disconnected images.
7. Run SfS per tile (`tile_dem.py`, `launch_sfs_tiles.sh`), merge (`dem_mosaic_list.sh`), optionally after a preview pass hillshade-aligned to LOLA.
8. Post-SfS registration, height-uncertainty, and jitter as needed.

`solar-az-plot` is an optional illumination check that animates footprint coverage by solar azimuth.

Optional stereo survey: where stereo coverage exists, `find-stereo` surveys stereo availability, `stereo-from-ba` lists runnable stereo pairs from the largest connected group, and `tri-plot` plots triangulation-error images. For sparse polar coverage this branch is usually skipped in favor of more complete bundle adjustment (see WORKFLOW.md).

## Script reference

All scripts live in `bin`.

Each worker prints its own argument list if run with no arguments. See [WORKFLOW.md](WORKFLOW.md) for how they fit together and the `qsub` command for each.

### Environment and helpers

- `init_asp.sh`: activate the environment with ASP and ISIS on PATH (micromamba, mamba, or conda).
- `init_isis.sh`: activate the ISIS conda environment.
- `init_sfs.sh`: activate the SfsPipeline environment (ASP bin not on PATH).
- `sfs_utilities.sh`: bash helper functions for SfS processing. Source to load.
- `db_to_urls.sh`: produce NAC IMG download URLs from a GPKG source file.
- `random_sample.sh`: take a random sample from a list file.
- `ds_by_attr.sh`: subset a GPKG file by an attribute value range.

### Terrain, fetch, and calibration

- `make_ref_dem.sh`: regrid a source DEM (gdalwarp) to the target grid, resolution, and half-integer bounds, with optional spike blur.
- `query_lro.py` / `query_lro.sh`: query the PDS ODE REST API for NAC images by lat/lon box or DEM extent, emitting product IDs and IMG URLs.
- `download_all.sh`: resumable multi-URL downloader.
- `fetch_lro_nac.sh`, `prepare_lro_nac.py`, `batch_prepare_lro.sh`: fetch and calibrate EDRs to `.cal.echo.cub` plus CSM cameras (lronac2isis, spiceinit, lronaccal, lronacecho, isd_generate with linear reduction).
- `isd_generate.sh`: generate CSM camera JSON for a list of cubes.
- `regrid_to_grid.sh`: gdalwarp a raster onto a fixed target grid.

### Selection and illumination

- `sfs_query.sh`, `query_azimuth.sh`: per-camera Sun azimuth/elevation via `sfs --query`.
- `query_gsd.sh`: per-image ground sample distance via `mapproject --query-projection`.
- `filter_by_max.sh`: order-preserving cull of shadowed/non-intersecting frames by max value.
- `split_quadrants.py`, `prepare_lowres.sh`, `image_subset_2x.sh`, `sfs_select_full_site.sh`: minimal-but-covering image subset selection per quadrant.
- `plot_sfs_azimuth.py`: Sun-azimuth rose plot.
- `sfs_flag_bad_cameras.py`, `sfs_prune_and_remosaic.sh`: flag and drop whacky cameras, rebuild max-lit mosaics.

### Mapprojection, bundle adjustment, alignment

- `batch_mapproject.sh` / `mapproject_chunk.sh`: chunked multi-node mapprojection and its per-node worker.
- `mapproject_sub10.sh`: low-resolution mapprojection for quick looks.
- `bundle_adjust.sh`: parallel_bundle_adjust wrapper (matches-only with `NUM_ITERATIONS=0`, or a solve).
- `bundle_adjust_refine.sh`: the fixed-anchors -> free -> heights-from-dem refine chain.
- `bundle_adjust_dem_gcp.sh`: bundle adjust constrained by a DEM-derived GCP file.
- `correlator.sh`, `dense_correlator.sh`: image-to-image correlation (correlator mode).
- `hillshade_correlator.sh`: DEM-to-DEM hillshade correlation for a horizontal shift (dh/dv).
- `dem2gcp.sh`, `trans_gcp.sh`, `filter_gcp.py`: turn a DEM-to-DEM disparity into GCPs for a re-solve.

### SfS, mosaics, registration, jitter

- `tile_dem.py`: cut the reference DEM into ~4k x 4k padded tiles.
- `parallel_sfs.sh` / `launch_sfs_tiles.sh`: per-tile parallel_sfs worker and the batch submitter over all tiles.
- `sfs_exposures.sh`: precompute SfS exposures.
- `dem_mosaic_list.sh`: merge DEMs or mapprojected images with dem_mosaic (blend, max, mean, count via pass-through flags).
- `max_lit.sh`, `batch_max_mosaic.sh`, `batch_max_mosaic_lowres.sh`: max-lit mosaics.
- `blend_img_mosaic.sh`, `avg_mosaic.sh`: weighted-mean image mosaics with shadow suppression.
- `sfs_sim_align.sh` / `batch_sfs_sim.sh`: post-SfS per-image registration by rendering an SfS-simulated view, image_align, and gcp_gen.
- `jitter_solve.sh`, `jitter_gcp.sh`: refine per-line linescan poses to remove jitter.

### QGIS helper scripts

- `startup.py`: QGIS plugin main file.
- `raster_matcher.py`: QGIS plugin to locate TIF files from a vector layer.
- `add_rat_to_vrt.py`: add a Raster Attribute Table to max-lit index files so QGIS maps DN values to source LROC NAC product IDs.

### Legacy PBS scripts

The earlier self-submitting `*.pbs` job scripts are superseded by the bash workers above, submitted with an explicit `qsub` (see WORKFLOW.md). They are retained for reference while the migration settles and will be removed. A few still-unique ones (`run_sfs_blend.pbs` for `sfs_blend`, `run_max_lit_indexes.pbs` for index maps, `shadow_mask.pbs`, `serve_folder.pbs`, `run_command_list.pbs`) are slated to be rewritten as `.sh` workers before removal.

## Command-line tools

These Python entry points (installed on PATH by the conda environment) handle
discovery, selection, and validation. [WORKFLOW.md](WORKFLOW.md) shows each one
in the order you actually run it, with the surrounding commands; this is just a
reference.

- `make-index`, `prep-index`, `provenance`: build the geoparquet LROC cumulative
  index (from CUMINDEX.LBL/TAB in `~/LRO_EDR_CUMINDEX/`) with embedded provenance.
- `sfs-cover`: select the observations crossing an ROI polygon into a GeoPackage.
- `find-image-overlaps`: build a spatial/illumination connectivity graph from the
  cover GeoPackage; `--check_connectivity` reports component sizes, otherwise it
  writes the overlap list. Used here for validation and downselect.
- `verify-ba`: after bundle adjustment, report the largest connected camera
  component from the match-offset and residual stats so islands can be dropped.
- `lit-select`: pick a well-illuminated image subset for an SfS tile.
- `update-db`: write a new GeoPackage combining the metadata with refreshed
  (mapprojected or shadow-masked) footprints.
- `filter-db`: downselect a GeoPackage to the product ids in a verify-ba result.
- `find-stereo`, `stereo-from-ba`, `tri-plot`: optional stereo-survey branch
  (stereo availability, runnable pairs, triangulation-error plots).
- `solar-az-plot`: animate footprint coverage by solar azimuth.
- `wkt-to-ullr`, `wkt-to-projwin`, `wkt-round-out`, `setops`: small geometry and
  list helpers (see TIPS.md).
