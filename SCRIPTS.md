# Scripts and tools reference

All scripts live in `bin`. Each bash worker prints its own argument list if run
with no arguments. [WORKFLOW.md](WORKFLOW.md) shows how they fit together and the
`qsub` command for each. The Python command-line tools are installed on PATH by
the conda environment.

## Bash workers and helpers

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
- `mapproject_native_res.sh`: mapproject a list of images at their own native GSD (no fixed `--tr`) with paired cameras onto a reference DEM, building the native-resolution delivery ortho set plus a `gsd.csv` of the actual output pixel sizes.
- `bundle_adjust.sh`: parallel_bundle_adjust wrapper (matches-only with `NUM_ITERATIONS=0`, or a solve).
- `bundle_adjust_refine.sh`: the fixed (USGS-controlled) -> free -> heights-from-dem refine chain.
- `bundle_adjust_dem_gcp.sh`: bundle adjust constrained by a DEM-derived GCP file.
- `hillshade_corr.sh`: standalone DEM-to-DEM hillshade correlation for a horizontal shift (dh/dv step, no pc_align).
- `hillshade_correlator.sh`: DEM-to-DEM hillshade correlation and alignment (runs pc_align to emit aligned DEM).
- `dem2gcp.sh`, `trans_gcp.sh`, `filter_gcp.py`: turn a DEM-to-DEM disparity into GCPs for a re-solve (used to pull a DEM into the LOLA frame).

### SfS, mosaics, registration, jitter

- `tile_dem.py`: cut the reference DEM into ~4k x 4k padded tiles.
- `parallel_sfs.sh` / `launch_sfs_tiles.sh`: per-tile parallel_sfs worker and the batch submitter over all tiles.
- `sfs_exposures.sh`: precompute SfS exposures.
- `dem_mosaic_list.sh`: merge DEMs or mapprojected images with dem_mosaic (blend, max, mean, count via pass-through flags).
- `max_lit.sh`, `batch_max_mosaic.sh`, `batch_max_mosaic_lowres.sh`: max-lit mosaics.
- `max_lit_index.sh`: max-lit mosaic with a per-pixel source-image index map (pairs with `add_rat_to_vrt.py`).
- `sfs_blend.sh`: blend the SfS DEM toward the reference where there is little illumination.
- `blend_img_mosaic.sh`, `avg_mosaic.sh`: weighted-mean image mosaics with shadow suppression.
- `sfs_sim_align.sh` / `batch_sfs_sim.sh`: post-SfS per-image registration by rendering an SfS-simulated view, image_align, and gcp_gen.
- `jitter_gcp.sh`: GCP-driven per-line refine that re-registers the SfS terrain to LOLA (the committed final refine).
- `jitter_solve.sh`: per-line refine with no GCP, for removing intrinsic jitter when there is no re-registration target.

### Batch and QA utilities

- `run_command_list.sh`: fan an arbitrary command list out across the nodes of a PBS job with GNU parallel.
- `run_geodiffs.sh`: geodiff every matching DEM in a directory against a reference, fanned out.
- `batch_shadow_mask.sh`: run `shadow_mask.sh` over a directory of mapprojected images, fanned out.
- `serve_folder.sh`: serve a folder of COGs over HTTP (read-only) with rclone for remote QA.

### Stereo branch (optional, under review)

- `run_stereo.sh`: run one stereo pair (parallel_stereo asp_mgm) with point2dem and a half-res DEM.
- `run_point2dem.sh`: point2dem on a stereo point cloud.

These are reworked to the worker conventions. Their stereo parameters are carried over from the original and kept under review (the stereo branch is usually skipped for polar SfS).

### QGIS helper scripts

- `startup.py`: QGIS plugin main file.
- `raster_matcher.py`: QGIS plugin to locate TIF files from a vector layer.
- `add_rat_to_vrt.py`: add a Raster Attribute Table to max-lit index files so QGIS maps DN values to source LROC NAC product IDs.

## Command-line tools (Python)

These entry points handle discovery, selection, and validation.
[WORKFLOW.md](WORKFLOW.md) shows each one in the order you actually run it, with
the surrounding commands. This is just a reference.

- `make-index`, `prep-index`, `provenance`: build the geoparquet LROC cumulative index (from CUMINDEX.LBL/TAB in `~/LRO_EDR_CUMINDEX/`) with embedded provenance.
- `sfs-cover`: select the observations crossing an ROI polygon into a GeoPackage.
- `find-image-overlaps`: build a spatial/illumination connectivity graph from the cover GeoPackage. `--check_connectivity` reports component sizes, otherwise it writes the overlap list. Used for validation and downselect.
- `verify-ba`: after bundle adjustment, report the largest connected camera component from the match-offset and residual stats so islands can be dropped.
- `lit-select`: pick a well-illuminated image subset for an SfS tile.
- `update-db`: write a new GeoPackage combining the metadata with refreshed (mapprojected or shadow-masked) footprints.
- `filter-db`: downselect a GeoPackage to the product ids in a verify-ba result.
- `find-stereo`, `stereo-from-ba`, `tri-plot`: optional stereo-survey branch (stereo availability, runnable pairs, triangulation-error plots).
- `solar-az-plot`: animate footprint coverage by solar azimuth.
- `wkt-to-ullr`, `wkt-to-projwin`, `wkt-round-out`, `setops`: small geometry and list helpers (see TIPS.md).
