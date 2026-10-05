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

When a project is finished, fill in a copy of `inventory.yaml` (at the repo root) in the work directory. It is a delivery and provenance manifest that records the base terrain, the final bundle-adjust prefix, the stereo and SfS terrains, logs, and the orthoimage directory, so the project is self-describing when handed off. See the comments in the file for each field.

## Workflow

The pipeline has two layers: lightweight command-line tools (installed as PATH entry points) that handle discovery, verification, and selection, and bash worker scripts submitted with `qsub` that run the heavy compute. [WORKFLOW.md](WORKFLOW.md) is the runnable end-to-end sequence with a `qsub` command and suggested walltime for every step.

Main SfS path, high-level order of operations:

1. Prepare the reference terrain: `make_ref_dem.sh` regrids the LOLA DEM to the target grid and half-integer bounds.
2. Fetch and calibrate the NAC images: discover with `sfs-cover` (or `query_lro.sh`), download, then `batch_prepare_lro.sh`.
3. Sort images by Sun azimuth and cull shadowed frames (`sfs_query.sh`, `filter_by_max.sh`).
4. Mapproject onto the reference DEM (`batch_mapproject.sh`).
5. Bundle adjust: harvest matches (`bundle_adjust.sh`, `NUM_ITERATIONS=0`) then the fixed (USGS-controlled) -> free -> heights-from-dem refine chain (`bundle_adjust_refine.sh`). This is the single most important step for SfS quality.
6. Evaluate and prune: check the camera graph with `verify-ba`, then flag and drop whacky cameras (`sfs_flag_bad_cameras.py`, `sfs_prune_and_remosaic.sh`).
7. Pick a minimal-but-covering SfS image subset (`sfs_select_full_site.sh`).
8. Run SfS per tile (`sfs_exposures.sh`, `tile_dem.py`, `launch_sfs_tiles.sh`) and merge (`dem_mosaic_list.sh`).
9. Re-register the SfS DEM to LOLA where it shifted: measure (`batch_sfs_sim.sh`, `hillshade_correlator.sh`), build a GCP and refine (`dem2gcp.sh`, `jitter_gcp.sh`), then redo SfS.
10. Blend toward LOLA in shadow (`sfs_blend.sh`), build the max-lit and average mosaics, an optional height-uncertainty map, then fill `inventory.yaml` for delivery.

`solar-az-plot` is an optional illumination check that animates footprint coverage by solar azimuth.

Optional stereo survey: where stereo coverage exists, `find-stereo` surveys stereo availability, `stereo-from-ba` lists runnable stereo pairs from the largest connected group, and `tri-plot` plots triangulation-error images. For sparse polar coverage this branch is usually skipped in favor of more complete bundle adjustment (see WORKFLOW.md).

## Scripts and tools

See [SCRIPTS.md](SCRIPTS.md) for the full reference: the bash workers in `bin`
(grouped by pipeline stage) and the Python command-line tools. Each bash worker
also prints its own argument list if run with no arguments, and [WORKFLOW.md](WORKFLOW.md)
shows every step with its `qsub` command. See [TIPS.md](TIPS.md) for handy one-liners.
