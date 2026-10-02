# sfstools
A place for scripts to support the practical operation of SfS. This is workin progress as of 2026/10. 

The main documentation for the Ames Stereo Pipeline SfS is available here: 
https://stereopipeline.readthedocs.io/en/latest/sfs_usage.html

We will use this as the reference document, but there are many practical aspects of generating DEMs via SfS that are not necessarily documented. 

## Installation Instructions

Note sfstools contains both utilities intended to be run on your local machine (denoted by 💻) and scripts intended for the NASA HECC HPC (denoted by ☁️). This repository should be installed in both locations, but only some of the steps below are necessary for HECC, and they are denoted by the ☁️ emoji. Otherwise the step needs to be run both locally and on HECC.


1. (☁️) Install ASP by downloading the precompiled binarys file [following these instructions and note the folder for step 6.](https://stereopipeline.readthedocs.io/en/latest/installation.html#precompiled-binaries)

2. [Install micromamba.](https://mamba.readthedocs.io/en/latest/installation/micromamba-installation.html) If you already have conda/mamba installed and running on your system you can skip this step.

3. (☁️) Install ISIS to a new conda environment and set up the data area [following these instructions (suggest calling the environment `isis`)](https://astrogeology.usgs.gov/docs/how-to-guides/environment-setup-and-maintenance/installing-isis-via-anaconda/)

4. Clone sfstools repo to your computer and CD into the project
  ```bash
  git clone https://github.com/NeoGeographyToolkit/sfstools.git
  cd sfstools
  ```

5. Install sfstools to a new conda environment using conda/mamba/micromamba, please name this environment 'sfstools':
   ```bash
   micromamba env create -n sfstools -f environment.yaml 
   ```

6. (☁️) Add `base_scripts` and `src/pbs_scripts` to your PATH environment by editing your .bashrc/.zshrc file and set ASP_ROOT, ISIS_ROOT, and ISIS_DATA variables to paths you created in steps 1 and 3.

```bash
# within your .bashrc/.zshrc file add (TODO Replace with with sym links in ~/.local/bin)
export PATH="$PATH:/path/to/sfstools/base_scripts/:/path/to/sfstools/src/pbs_scripts/"
export ISISDATA=/path/to/your/ISISDATA/
export ISISROOT=/path/to/your/conda/envs/isis
export ASPROOT=/path/to/your/extracted/ASP/ 
export NAME_SOURCE=/path/to/cities.csv or some other text file with random names you like, but this is optional
```

7. To run the commands below simply activate the `sfstools` conda environment. The bash and PBS scripts however shouldn't need this and they should be available in your PATH regardless of the conda environment. 

8. To run ISIS or ASP commands invoke `source init_asp.sh`, to run sfstool tools and GDAL use `source init_sfstools.sh`.


# Utility Scripts (base_scripts/sfs_utilities.sh)

Various helpful and needed small bash utilities are contained in `base_scripts/sfs_utilities.sh`.

This includes utilities for computing stats on geodiff results, converting images to LERC compressed COGs, and many other small things that are helpful to have but aren't complicated enough to warrant their own stand alone script.

To access these utilities simply run `source base_scripts/sfs_utilities.sh` AFTER `source init_asp.sh`. This may change to be incorporated into `init_asp.sh` and `init_sfstools.sh` but it is still being updated.

# QGIS utils (base_scripts/startup.py)

Various helpful enhancements for QGIS are implemented within the `base_scripts/startup.py` python file. The intent is for users to have a local copy of this file/the sfstools installation and for them to place a symbolic link to this file in the appropriate directory for there system as documented by https://docs.qgis.org/testing/en/docs/pyqgis_developer_cookbook/intro.html#the-startup-py-file. 


# Overview of scripts

This project contains a number of types of scripts that broadly are:

1) Python scripts 
    * generally for pre-processing operations and analysis. Typically run on your local system or on the PFE node.
2) PBS scripts
    * these end with `.pbs` extension and are intended to be run only on HPC with PBS job management system.
3) Bash scripts
    * located in base_scripts and pbs_scripts that are either simple utilities or help run or are used by other `.pbs` script files


The Python scripts are (unless I forgot to update the pyproject.toml) installed as entry points to your python environment and are available on your PATH.


## PBS Scripts detail

The PBS scripts (ending with `.pbs`) are a bit special and some explaination is needed for their use. 

The PBS scripts are self-submitting workflows. To submit the job to the cluster, run `export SUBMIT=true` prior to the script. This will create a job on the queue that actually runs the rest of the script to map project images, run sfs, run bundle adjust, etc.
The jobs are configured using a variety of environment variables particular to each script (working as required and optional parameters).

A few things like the PBS queue used and node allocations are currently hard set at the top of the file and must be 
adjusted manually. 

By default the scripts will not run any real commands (mapproject, bundle adjust, stereo, etc) UNLESS 
you set the environment variable `SUBMIT=true`. By default running the scripts will just execute the workings of the script 
that find files, prepare output folders, etc but no actual work will occur. This is intentional for debugging purposes and to 
avoid accidentally attempting to run work on the PFE nodes.

Each PBS (and a few of the .sh scripts) look for a debug flag set via the environment variable `DEBUG=true`
This will run the script line-by-line, where the user will see the command that will be executed printed
to the terminal, and the user will need to press enter to progress. This is helpful for understanding the scripts,
debugging issues, and for inspecting the temporary job list files that get created for certain commands that use gnu parallel.

The intended workflow is for users to set the environment variables they need for a particular job then:

1) unset SUBMIT
2) export DEBUG=true
3) run the script to ensure everything looks correct
4) unset DEBUG
5) export SUBMIT=true
6) run the script again to submit to PBS

Each script when submitted to PBS has a 15 second pause where the user can cancel the script (using keyboard shortcut)
before the job is actually submitted. As jobs typically don't run immedietly the user can also use `qdel` to cancel jobs after the submission occurs.



## Recommendation for workflow

It is recommended that users create a sub folder for each area they are producing SFS terrain for that will be the work directory.

The user should create a log file of some kind (like a markdown file) where they can document their steps and prototype bash commands
before running them in the terminal.


# Workflow for scripts

Here is the high level ordering of the commands used end-to-end 

Symbols:
💻 : run locally or on single PFE node
☁️ : run PBS script (so needs to be on PFE node)

1. process-cumulative-index (💻)
  - Local script for preparing geoparquet cumulative index files
2. sfs-cover (💻)
  - Local script for using geoparquet index to get images relevant to ROI 
3. find-stereo-pairs (💻)
  - Optional script to investigate "good stereo" availability prior to BA (you can skip entirely, this is just to get a sense of what could be usable)
4. solar_az_animate.py (💻)
  - Optional script to view footprint coverage given solar ground azimuth bins via animation in matplotlib (you can skip entirely, this is just to get a sense of what could be usable)
9. find_overlaps_for_bundle_adjust.py (💻)
  - Given sfs cover output determine likely matching images by overlap and lighting geometry to feed pairs list to bundle adjust
12. verify_bundle_adjust.py (💻/☁️)
  - Used to investigate the graph from the bundle adjust and determine the largest connected group of cameras/plot footprints and illumination coverage 
13. get_stereo_pairs_from_bundle_adjust.py (💻)
  - Script to determine what stereo pairs are available to run given the largest connected group of cameras
16. triangulation_plot.py (💻)
  - utility plot tool to plot triangulation error images in python without stereo-gui
17. downselect_stereo_for_pc_align.py (💻)
19. lit_select.py (💻)

# Base Scripts
 * stereo.sh
  - old script from Moses/Ross for stereo processing
 * random_sample.sh
  - Utility to take a random sample from a list file
 * ds_by_attr.sh
  - Subset a GPKG file using an attribute and a value range
 * rescale_raster.sh
  - Deprecated script to scale a floating point image to 8 bit
 * raster_matcher.py
  - QGIS plugin module for locating tif files from the file system to load using a vector layer (eg the sfs cover output) to determine the subset to load
 * startup.py
  - QGIS plugin module main file
 * add_rat_to_vrt.py
  - Script to add Raster Attribute Table to Max Lit Index files, allows QGIS to convert DN value to source LROC NAC Product ID.
 * sfs_utilities.sh
  - Large collection of bash function helper utilities critical to SFS processing. Source this file to add functions to terminal.
 * db_to_urls.sh
  - Script to get https urls for NAC IMG files so you can download them from the PDS from a GPKG source file.

# Bash Scripts

 * calibrate_edr.sh
  - Internally used script to run ISIS calibration/CSM Camera generation
 * init_asp.sh
  - Init the ASP/SFSTools environment.
 * init_isis.sh
  - Init the ISIS conda environment.
 * init_sfstools.sh
  - Init the SFSTools environment (ASP bin not in PATH).
 * launch_individual_mapproj_jobs.sh
  - Deprecated bash script to help launch many mapproj jobs.
 * launch_individual_stereo_jobs.sh
  - Deprecated bash script to help launch many stereo jobs.
 * make_lerc_cog.sh
  - Deprecated script to help make lerc cogs.
 * prepare_ba0_lists.sh
  - Deprecated script to help prepare lists for bundle adjust.
 * shadow_mask.sh
  - Internally used script to help compute shadow masks.

# PBS Scripts

 * bundle_adjust_pairwise_pt1.pbs
   - Runs IP matching prior to bundle adjustment (optimization of cameras), using many nodes.
 * bundle_adjust_pt0.pbs
   - Deprecated script to run step 0 in bundle adjust, using many nodes.
 * bundle_adjust_pt1.pbs
   - Deprecated script to run step 1 in bundle adjust, using many nodes.
 * bundle_adjust_pt2.pbs
   - Optimize Cameras/Refine to topography (the actual bundle adjustment), uses 1 node.
 * calibrate_edr.pbs
   - Calibrate IMG to CUB and generate CSM Cameras, using many nodes.
 * gdal_footprints.pbs
   - Deprecated script to create image footprint geojson files, using many nodes.
 * launch_stereo.pbs
   - Deprecated script to run stereo, using many nodes.
 * make_lerc_cogs.pbs
   - Deprecated script to convert TIF files to LERC compressed COG TIFs, using many nodes.
 * mapproj_ba.pbs
   - Mapproject images using BA'd CSM Cameras and Topography, using many nodes. 
   - Also computes footprints.
 * mapproj_noba.pbs
   - Mapproject images using Topography without BA'd CSM Cameras, using many nodes.
   - Also computes footprints.
 * run_command_list.pbs
   - Unused script to run arbitrary lists of commands, using many nodes.
 * run_geodiffs.pbs
   - Unused script to run large numbers of geodiff calls, using many nodes.
 * run_hillshade_align.pbs
   - Hillshade align two DEMs, using a single node.
 * run_individual_count_lit.pbs
   - Generate SFS count map product for a single tile, uses a single node.
 * run_individual_dem_mosaic.pbs
   - Run dem_mosaic to merge DEM tiles, kinda optional, uses a single node.
 * run_individual_image_correlation.pbs
   - Deprecated script to run image correlation.
 * run_individual_mapproj.pbs
   - Deprecated script to map project a single image, uses a single node.
 * run_individual_max_lit_indexes.pbs
   - Generate SFS max lit index (which image contributed each pixel) map product for a single tile, uses a single node.
 * run_individual_max_lit.pbs
   - Generate SFS max lit map product for a single tile, uses a single node.
 * run_individual_point2dem.pbs
   - Run point2dem for stereo job. 
 * run_individual_stereo.pbs
   - Run a single stereo pair as a distinct job.
 * run_sfs_blend.pbs
   - Run SFS Blend step for SFS processing, using a single node.
 * serve_folder.pbs
   - Serve a folder from NAS over http for viewing COGs, not much faster than downloading individual files though.
 * sfs_exposures.pbs
   - Deprecated script to run SFS to precompute exposure lists.
 * sfs.pbs
   - Run SFS, or optionally run height uncertainty jobs, using many or 1 node.
 * shadow_mask.pbs
   - Generate shadow mask tif files and footprint geojsons, using many nodes.



# Command Line Tools


## Process Cumulative Index to parquet files

this command will process the CUMINDEX.LBL and CUMINDEX.TAB in your home directory (NOTE: they must be in home dir, or at least symlinked there...)
into parquet files in /tmp. On a M2 Macbook Air this takes about 2 minutes.
Each parquet file will have an embedded metadata tag of the Provenance information which includes 
the date time stamp in utc, the user, the hostname, and the md5sum of the CUMINDEX.TAB file

```bash
process-cumulative-index
```

output looks like:

```bash
Gathering Provenance...
Provenance: {"date":"2025-01-31 09:29:41.468754","user":"aannex","hostname":"starmirage","md5sum":"828e6e35a977a67f4ab16eab59dd2bfe"}
preprocessing the cumlative index to the flatgeobuf file in /tmp
Read metadata from cumulative label
Loaded raw NAC only table with 2629426 rows
Got schema
Created cleaned table
Updated Longitudes to correct range
computed ground azimuth columns and made new table
created lroc spatial table, starting to apply hilbert order
saving hilbert ordered data to flatgeobuf
done!
       41.46 real        82.00 user         8.13 sys
creating the parquet files...
0...10...20...30...40...50...60...70...80...90...100 - done.
       20.94 real        19.82 user         1.82 sys
created global parquet file at /tmp/lroc_cumulative.parquet
        5.62 real         5.70 user         0.22 sys
created north polar parquet file at /tmp/lroc_cumulative_north_polar.parquet
        6.31 real         6.38 user         0.26 sys
created south polar parquet file at /tmp/lroc_cumulative_south_polar.parquet
Done! Parquet Files are located in /tmp/ for your use.
```

## SFS Cover

Even with a larger ROI for SFS Cover, you will only end up with a few thousand observations so geopackage output
is totally fine for this

```bash
sfs-cover --db_path /tmp/lroc_cumulative_south_polar.parquet -p "POLYGON((72471.2817000002 158818.3489,128308.508199999 158818.3489,128308.508199999 119030.173,72471.2817000002 119030.173,72471.2817000002 158818.3489))" -t mons_mouton_regional --gpkg /tmp/mons_mouton_regional.gpkg
```

the provenance info is propogated from the source db parquet file:

```bash
ogrinfo /tmp/mons_mouton_regional.gpkg mons_mouton_regional -so | head
INFO: Open of `/tmp/mons_mouton_regional.gpkg'
      using driver `GPKG' successful.

Layer name: mons_mouton_regional
Metadata:
  PROVENANCE={"date":"2025-01-31 09:29:41.468754","user":"aannex","hostname":"starmirage","md5sum":"828e6e35a977a67f4ab16eab59dd2bfe"}
Geometry: Polygon
Feature Count: 4844
Extent: (-58034.599620, -25721.486558) - (216325.951463, 263254.550266)
Layer SRS WKT:
```

## Getting updated Footprints

At several stages of the processing, users will want to updated the footprints/polygons in their GPKG/geodatabase file to reflect the actual map projected footprint with and without bundle adjusted cameras and get polygons that loosly represent illuminated vs shadowed areas using the shadow masks process. The general process is the same for these cases, although the exact commands will slightly differ but the general process is:

1) Generate the updated footprint geojsons, either through mapproject or if needed the shadow_mask.pbs script
2) Collect the geojsons desired using the `collect_geojson` utility, available from the `base_scripts/sfs_utilities.sh` file (source it to add the function to your terminal). 
3) run `update_db_from_footprints.py` to create a new GPKG file with all the meta data from the geodatabase for their ROI and the new footprints.

A more concrete/practical example for the first stage of this after map projecting the data

```bash
# source the sfs utilities so that collect_geojson is available
source base_scripts/sfs_utilities.sh
# collect the non-bundle adjusted footprints into a single file
# assuming you have a folder called 'IMAGES' that has all your cub/tif files. 
collect_geojson_stream IMAGES 'map.noba.geojson' > noba_footprints.geojson
# now generate the new GPKG file using this collected geojson and the original GDB
python loony/update_db_from_footprints.py SOURCE.gpkg TARGET_noba_footprints.gpkg noba_footprints.geojson
```

If using the shadow masks is desired, which it typically is, first they must be generated 

```bash
export INPUT_DIR="IMAGES"
export TIF_POSTFIX='map.noba.tif'
# submit a PBS just that looks for map projected images that use the original (noba) cameras
shadow_mask.pbs
# wait until the PBS jobs is complete then re-run the process above with new inputs

# source the sfs utilities so that collect_geojson is available
source base_scripts/sfs_utilities.sh
# collect the non-bundle adjusted footprints into a single file
# assuming you have a folder called 'IMAGES' that has all your cub/tif files. 
collect_geojson_stream IMAGES 'map.noba.mask.geojson' > mask_noba_footprints.geojson
# now generate the new GPKG file using this collected geojson and the original GDB
python loony/update_db_from_footprints.py SOURCE.gpkg TARGET_mask_noba_footprints.gpkg mask_noba_footprints.geojson
```

These steps can be repeated at later stages of processing by updating the particular parameters as needed

## Determining pairs for Bundle Adjust (investigate the graph)

An improved process for bundle adjust is to use the image footprints and metadata, both from the sfs-cover geodatabase file (optionally updated to use map projected or shadow mask footprints described above), to determine which images both overlap spatially and are likely to match well based on the illumination geometry and possibly which areas of the images are actually illuminated when using the shadowmask files. 

From these spatial relationships, we can investigate apriori how inter-connected the cameras can or will be given different tolerances after bundle adjustment is completed using a Graph data structure. We can also use this graph to directly generate the `overlap-list` file parameter for bundle adjust which can help perform the only matches necessary to complete a good bundle adjustment and avoid attempting to match images which don't overlap spatially or aren't fully illuminated in the same areas. As study area sizes grow and the number of images used grows, this becomes increasingly cirtical to keep the computational costs to reasonable limits.

Prior to bundle adjustment, it is highly suggested to have completed both the first pass, non bundle adjusted map projection of the images (using mapproj_noba.pbs) AND the shadow masks for these noba tifs (using shadow_mask.pbs) to generate the updated footprint GPKG file (using the steps above). 

While it is possible to use the sfs-cover gpkg file directly, the shadow masks in particular helpful as it eliminates impossible matches, where image footprints overlap in areas that are not illuminated.

Using this geodatabase/gpkg file, the python program `find-overlaps-for-bundle-adjust` is used with the option `--check_connectivity` first to compute the connectivity of the images given a maximum difference in sub-solar ground azimuth defined by the `--max_diff_slrgaz` parameter. 

For example 
```bash
# this script is somewhat resource intensive, so ideally run on a debug or devel PBS node with 4-8 cores. Should only 2 minutes or so.
find-overlaps-for-bundle-adjust --check_connectivity  -d ./mask_noba_footprints.gpkg --max_diff_slrgaz=12
```
will generate something like the following json who's fields I will explain below

```json
{
  "components": [... omitted for brevity ..]
  "is_connected": true, 
  "num_pairs": 36574, 
  "num_components": 1, 
  "component_sizes": [1514], 
  "num_pairs_per_component": [36574], 
  "degree_hist_per_component": [... omitted for brevity ..]
}
```

The 0th field is the `components` which has all the product ids for each sub graph but I don't discuss it here as it isn't useful to this topic presently. 

The 1st field `is_connected` tells you if the graph used every available image, and is rarely true. 

The 2nd field `num_pairs` are the number of image pairs from the largest full connected sub graph that would be created in the overlap list file for bundle adjust, and is the first value from the field `num_pairs_per_component` 

The 3rd field `num_components` tells you the number of sub graphs that are fully connected. In this case it is `1` because only one fully connected component was found.

The 4th field `component_sizes` tells you for each sub graph how many images are contained. The 1st (or 0th) component is always the largest as I sort them. 

the 5th field `num_pairs_per_component` tells you the number of image pairs in each sub graph that could be bundle adjusted together.

The last field is a histogram of the graph degree for each sub-graph, which is to say the histogram of the connectiveness of all the images, which to say ask "for each image, how many images is it directly connected to, and plot this histogram of this". This lets you see how deeply interconnected the graph is, and in general more values at higher bins is a good thing, as you want to keep the number of images that are only connected to 1 other image to a low value.

With all of the above explained we can now describe the actual workflow, which is to re-run the command above with higher or lower `--max_diff_slrgaz` values such that you keep the number of subgraphs ideally to 1 (so there is a single fully connected graph) while not suggesting too many pairs. 100k pairs would be considered a heck of a lot but do-able with available resources. A good comparison would be to take the number of images you have and multiply it by a reasonable "window" size you would otherwise use for bundle adjust, say 25 or 50, and if you are able to compute a fully connected graph with fewer pairs than this number, that you were successful. 

In testing a `--max_diff_slrgaz` greater than 10 degrees created un-neccessarily large number of pairs, while values around 6 or 8 degrees created large but managable sized lists.

Rerunning with `--max_diff_slrgaz=6` could tell you 

```json
...
"is_connected": false,
"num_pairs": 17507, 
"num_components": 4, 
"component_sizes": [1493, 8, 3, 3], 
"num_pairs_per_component": [17488, 13, 3, 3],
...
```


Which says that you have 4 sub graphs, the largest of which uses 1493 images and only has 17488 match pairs. You can see from the next few components that you lost a few images some of which are connected enough to be worth including.


Running it again after increasing the max diff value to 8 degrees results in 

```json
...
"is_connected": true, 
"num_pairs": 23580, 
"num_components": 1, 
"component_sizes": [1511], 
"num_pairs_per_component": [23580], 
```

Which uses nealy all the images we got from a max diff of 12 degrees, but only uses 23k pairs (approximately 2/3rds the value from 12 degrees). 

When happy with the parameters, re-run the script without the `--check_connectivity` parameter to create the overlap list file for bundle adjust

```bash
find-overlaps-for-bundle-adjust --image_dir='IMAGES/'  -d ./mask_noba_footprints.gpkg --max_diff_slrgaz=8 > OVERLAP_LIST_SLRGAZ_8.txt
```

This list can then be used to create the IMAGES, CAMERAS, and MapProjected data list files for bundle adjust using some bash and a utility from `base_scripts/sfs_utilities.sh`

```bash
source base_scripts/sfs_utilities.sh

# need to remake the image and camera list from the overlap list 
unique_from_pairs OVERLAP_LIST_SLRGAZ_8.txt > IMAGES.txt
cat IMAGES.txt | sed 's/.cub/.json/g' > CAMERAS.txt
cat IMAGES.txt | sed 's/.cub/.map.noba.tif/g' > MAPPROJ_DATA.txt 
# set the DEM path 
export DEM='path_to_dem.tif'
# append it to the mapproj data list
echo "$DEM" >> MAPPROJ_DATA.txt 

```

You are now ready to run the pairwise bundle adjust script that will described below.


## Downloading EDRs fast

```bash
db_to_urls.sh lrocedrlist.gpkg im | xargs -n 1 -P 8  -I {} wget {} -P ~/nobackup/LROCNACEDR/
```

db_to_urls.sh (in base scripts) outputs a list of formatted URLs from a GeoPackage/other spatial format (for now just output from sfs-cover)
into URLs that by default use the USGS AWS mirror of LROC NAC PDS data, which has much more bandwidth than the ASU/IM servers. But it's suggested to just use the IM server to avoid giving the USGS a big bill.

You can pass those to xargs and wget them in parallel, an example that downloaded almost 600 Gb only took a few minutes (maybe 10-15)



## First round ba0 bundle adjust make lists of good images/cameras/mapprojected images

```bash
cd folder/with/cubsandtifsandjsons
# images.txt is the sub solar ground azimuth ordered list of product ids
cat ../images.txt | prepare_ba0_lists.sh 
# IMAGES.txt, CAMERAS.txt, MAPPROJ_DATA.txt will be made
# append the dem
echo "path/to/dem.tif" >> MAPPROJ_DATA.txt
```


## Verify the bundle adjustment to look at graph connectivity

```bash
python ~/projects/sfstools/src/loony/verify_bundle_adjust.py 'baB/baB' --min_match_count=10 --max_residual_error=2.0 | jq '.component_sizes'
```

for the largest group identified, ensure you only select stereo pairs from it and drop further use of images that remain
in future stereo/bundle_adjust/sfs as those groups are disconnected islands

Be sure to iterate a few times with min match count, 10 may be too conservative, try 4,5,6, etc to see how size of largest component changes

Finally export the json to a file for later use 

```bash
python ~/projects/sfstools/src/loony/verify_bundle_adjust.py 'baB/baB' --min_match_count=10 --max_residual_error=2.0 > baB_comps.json
```

You will need to use this in joins later on like so




