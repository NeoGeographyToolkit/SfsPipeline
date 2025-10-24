# Workflow 

Dr. Andrew M. Annex
10/10/2025


### 1. Overview

The key to successful SFS processing is successfully bundle adjusting the images such that there is no ghosting, and that you've gathered as many images as humanly possible.

**Nothing Else Matters**

If you have any ghosting, it is very difficult to eliminate it unless it is exceedingly obvious which image is responsible. If multiple images contribute to ghosting in the same area, you don't know which to trust and you end up in a bad place to be.

For any SFS processing, all requisit time and effort and compute resources should be done to ensure you have as perfect a set of images as possible. Don't ever assume it is "good enough" or think you can save yourself later. 

If possible ensure your bundle adjustment is just below the computational limits for the ceres solver. Anything less is a waste of effort. When in doubt, always increase the number of interest points, the number of images you allow each image to be compared to, the number of points used from each pair. 

The reason this is good is that the compute required for this is not going to be greater than the shape from shading processing, and if you leave any performance on the table you will regret it later.


#### High Level Workflow Description

The workflow I developed is highly similar to the large scale sfs tutorial developed for SFS of lunar terrain from the ASP docs. 
However, because of the lack of stereo coverage, I skipped the stereo processing section in favor of doing a better/more complete job of bundle adjustment using more images and more interest point matches with smithed spice kernels.

Secondly and more critically perhaps, a "preview" pass of SFS is run using fewer images to produce a preliminary DEM that can be hill shade aligned to the LOLA. This may only work if the ROI is large enough to have meaningful texture to match to LOLA products. 

At that point the cameras can be translated in the same manner as the stereo-alignment method, re-bundle adjusted to the terrain, and a final sfs product can be computed using a higher prior dem weight constraint.


#### Overview of how to perform the workflow

The workflow for SFS is not a single script that runs due to the amount of flexibility needed to deal with issues as they arrise. 
So there is no "one" workflow or single command to run. Instead the workflow is a series of steps that must be manually executed
in the terminal, mostly on the NAS super computer system using the PFE nodes to run small scripts and processing steps and launch larger jobs that do the actual work. The main readme explains some of the particulars for how these scripts work, while this document is more focused on their actual use within a workflow. 


### 2.Guide to Processing

Below I will explain all the necessary processing steps I used for Mons Mouton/1414a. There should be no expectation that these steps will work exactly for any other location, and I will leave out some steps as being too trivial to explain. The steps won't be enough to make the products I made reproducible, simply because I was learning how to do it all as I went, and I didn't always take the best notes especially in places where I promoted certain proceedures and one-off bash calls into bash functions. 

This guide also doesn't explain installation or how to update things for your setup or file system paths or username. Read the install for that. So yeah, don't expect to drop the below into a terminal and have it work. It should however get you started.




## 1. Running SFS cover to get NAC images 

```bash
sfs-cover --db_path /tmp/lroc_cumulative_south_polar.parquet -p "POLYGON((...))" -t roi --gpkg ./roi.gpkg
```


## 2. Running first map projection to prepare for Bundle Adjustment

```bash
export SUBMIT=true
export DEM="roi_1m_lola.tif"
export INPUT_DIR="/path/to/cub/file/folder/"
mapproj_noba.pbs
```



## 3. Running first Bundle Adjustment Pass

### 3.0 Generate list files for bundle adjust
From the sfs-cover CSV file, we need to generate several list files:
1. The IMAGES (cub) list
2. The CAMERAS (csm camera) list
3. the MAPPROJ_DATA list that has the DEM as the final line

Below are some example ways to do this in bash, using a utlity at the end to ensure all the paths point to files that exist to make sure nothing went wrong with calibration or map projection.

```bash
### Prepare lists for bundle adjustment
```bash
# keep the order of the sfs list
cut -d, -f1 sfs_cover.csv | tail -n +2 > ./alpha/PIDs.txt 
# make the images list
cat ./alpha/PIDs.txt | sed 's/M/\/path\/to\/IMAGES\/M/g' | sed 's/$/.ech.cub/' > ./alpha/IMAGES.txt
# make the cameras list
cat ./alpha/PIDs.txt | sed 's/M/\/path\/to\/IMAGES\/M/g' | sed 's/$/.ech.json/' > ./alpha/CAMERAS.txt
# make the map projected images list 
cat ./alpha/PIDs.txt | sed 's/M/\/path\/to\/IMAGES\/M/g' | sed 's/$/.ech.map.noba.tif/' > ./alpha/MAPPROJ_IMAGES.txt
# make the map projected data file for bundle adjust
cp ./alpha/MAPPROJ_IMAGES.txt ./alpha/MAPPROJ_DATA.txt
export DEM="roi_1m_lola.tif"
echo $DEM >> ./alpha/MAPPROJ_DATA.txt

check_files ./alpha/CAMERAS.txt 
check_files ./alpha/IMAGES.txt
check_files ./alpha/MAPPROJ_DATA.txt  

```

To run bundle adjustment, we will explicitly decide which images to compare and match using the
`find-overlaps-for-bundle-adjust` script. That script requires us though to have made a new GPKG file with the map projected illumination footprints first though.

### 3.1 Generate Shadow Mask Footprints

```bash
export TIF_POSTFIX='map.noba.tif'
export INPUT_DIR="/path/to/your/IMAGES/"
# edit shadow_mask.pbs to ensure you have enough resources first
shadow_mask.pbs
```

When that's done, we can generate the updated gpkg file by the following two step process

```bash
source sfstools/base_scripts/sfs_utilities.sh
# collect geojson stream is a bash utility function in sfs_utilities.sh
collect_geojson_stream ./IMAGES 'map.noba.mask.geojson' > noba_mask_footprints.geojson
# run the update_db_from_footprints.py file
python sfstools/src/loony/update_db_from_footprints.py roi.gpkg roi_noba_mask_footprints.gpkg  ./noba_mask_footprints.geojson
```

### 3.2 Generate the overlaps list
Now we can actually generate the list of image overlaps using `find-overlaps-for-bundle-adjust`.
This script is intended to be run a few times to generate a list that is sufficiently big while not trying to compare too many pair-wise images and causing resouce waste.

For reference, the largest ROI I processed created almost 100k image pairs to compare (from 4.5k individual images). That was verging on too big to bundle adjust. For smaller ROIs with a few hundred images, expect numbers on the order of 8-20k. When in doubt, go bigger though, as there is little cost to going too big versus too small.

In general, a maximum difference of solar ground azimuth over 20 degrees tends not to work very well, while less than 10 degrees can result in too sparse a network of cameras to bundle adjust.

Below I illustrate a few invocations of the script, followed by a decision to go with a particular number:

```bash

find-overlaps-for-bundle-adjust  --image_dir='./IMAGES/'  -d ./roi_noba_footprints.gpkg --max_diff_slrgaz=2 | wc -l # 1000, too low

find-overlaps-for-bundle-adjust  --image_dir='./IMAGES/'  -d ./roi_noba_footprints.gpkg --max_diff_slrgaz=6 | wc -l # 6000, still too low

find-overlaps-for-bundle-adjust  --image_dir='./IMAGES/'  -d ./roi_noba_footprints.gpkg --max_diff_slrgaz=45 | wc -l # 32000, too high

find-overlaps-for-bundle-adjust  --image_dir='./IMAGES/'  -d ./roi_noba_footprints.gpkg --max_diff_slrgaz=16 | wc -l # 10000, just right 

# now save the list
find-overlaps-for-bundle-adjust  --image_dir='./IMAGES/'  -d ./roi_noba_footprints.gpkg --max_diff_slrgaz=16 > alpha/OVERLAP_LIST_SLRGAZ_16.txt
```

### 3.3 Bundle Adjust Setup

Okay to actually bundle adjust, we first need to generate the list of bundle adjust pairwise commands that actually need to be run, although the script can be just run, setting up that list is a bit slow and it's more efficient to just pre-generate the list of compairisons on a PFE node than to let the job be mostly idle for too long.

On a PFE node run the following command in DEBUG mode (the env var we set does this) until you see the temporary list of commands generated completely, copy that file over somewhere else and exit the script with ctrl+c.

Be sure to also set whatever other parameters for bundle adjustment you want to use within the `bundle_adjust_pairwise_pt1.pbs` script file. Also be sure to make sure you are using a few to a dozen nodes for the job over a 8 hour period to ensure all the commands run quickly.

```bash
unset SUBMIT
export DEBUG=true
export IMAGES="alpha/IMAGES.txt"
export CAMERAS="alpha/CAMERAS.txt"
export MAPPROJ_DATA="alpha/MAPPROJ_DATA.txt"
export OVERLAP_LIST="alpha/OVERLAP_LIST_SLRGAZ_16.txt"
export DEM="roi_1m_lola.tif"
export BA_PREFIX='ba0/ba0'

bundle_adjust_pairwise_pt1.pbs 
# in another terminal copy over the temp command list to alpha/launch_bundle_adjust_cmds_16.txt and exit"
```

### 3.4 Bundle Adjust Part 1

now we can submit the job after setting a few things

```bash

unset DEBUG
export SUBMIT=true
export IMAGES="alpha/IMAGES.txt"
export CAMERAS="alpha/CAMERAS.txt"
export MAPPROJ_DATA="alpha/MAPPROJ_DATA.txt"
export OVERLAP_LIST="alpha/OVERLAP_LIST_SLRGAZ_16.txt"
export DEM="roi_1m_lola.tif"
export BA_PREFIX='ba0/ba0'
export PARALLEL_JOBS_LIST_FILE="alpha/launch_bundle_adjust_cmds_16.txt"
bundle_adjust_pairwise_pt1.pbs 
```

### 3.5 Bundle Adjust Part 2 (optimization)

After part 1 finishes, we can run the actual bundle adjust optimization (step 2) which uses a single node. Be sure to set things like the MAX_PAIRWISE_MATCHES and the min-matches parameters.

```bash
unset DEBUG
export SUBMIT=true
export IMAGES="alpha/IMAGES.txt"
export CAMERAS="alpha/CAMERAS.txt"
export MAPPROJ_DATA="alpha/MAPPROJ_DATA.txt"
export OVERLAP_LIST="alpha/OVERLAP_LIST_SLRGAZ_16.txt"
export DEM="roi_1m_lola.tif"
export BA_PREFIX='ba0/ba0'
bundle_adjust_pt2.pbs 

```


## 4. Map projection of first BA Pass


## 5. 2nd Pass BA using Terrain Refinement


## 6. First pass SFS for hill shade alignment


### 6.1 Create the LOLA Tiles

To speed up SFS, we create VRT tiles from the LOLA DEM so that multiple sfs jobs are submitted, each independently making a SFS terrain that we can later merge with dem_mosaic. This has many advantages such as speeding up SFS processing, allowing quicker tests for large ROIs, and in general is just the best approach I've devised.

To do this we first run a python program to determine the number of tiles we'd need to cover a site and how much overlap to have.
In general, because we do the sfs processing with 256x256 tiles, an overlap of 256 is more than sufficient to ensure continuity in the data, but likely some redundant compute could be saved with a smaller overlap. 

Aim to make tiles no larger than 5128x5128 pixels (5.128km x 5.128km), for smaller ROIs something like 3768x3768 will work


```bash
# first run the following command to generate a minimal acceptable number of tiles, and view the gpkg in QGIS to make sure it looks good
python sfstools/src/loony/to_vrt_tiles.py dem_to_tiles_by_width_with_overlap roi_1m_lola.tif 3768 --overlap 256 to_gpkg roi_3k_tiles.gpkg
python sfstools/src/loony/to_vrt_tiles.py dem_to_vrt_tiles_by_width_with_overlap roi_1m_lola.tif 3768 --overlap 256 # this will actually generate the vrts
```

### 6.2 Make the list files for the SFS Jobs

Next we use a script called lit_select (not the one in ASP) to select the images that intersect each VRT tile and create list files of the images, cameras, map projected images, and etc.

```bash
for i in roi_1m_lola.tile.*.vrt; do; do
    echo $i
    python ~/projects/sfstools/src/loony/lit_select.py roi_mask_ba0s_ref_footprints.gpkg --dem_path $i --verify_out_json=alpha/ba0s_ref_components.json  --verbose --min_v 0 --max_v 370 | sort > "./sfs/${i%.vrt}.txt"
done

for i in ./sfs/roi_1m_lola.tile.*.txt; do
    # convert to image list (be sure to use the full resolve path to IMAGES below)
    awk '{print "IMAGES/"$1".ech.cub"}' $i > "${i%.txt}.IMAGES.txt"
    # and convert the image list to cameras
    cat "${i%.txt}.IMAGES.txt" | sed 's/IMAGES\//ba0s_ref\/ba0s_ref-ba0s-/g' | sed 's/.cub/.adjusted_state.json/g'  > "${i%.txt}.CAMERAS.txt"
done

for i in roi_1m_lola.tile.*.vrt; do; do
    export IMAGES="sfs/${i%.vrt}.IMAGES.txt"
    export MAPPROJ_IMAGE_LIST="sfs/${i%.vrt}.MAPPROJ_IMAGES.txt"
    cat "$IMAGES" | sed 's/.cub/.map.ba0s_ref.tif/g' > "$MAPPROJ_IMAGE_LIST"
done
```



## 7. Hillshade alignment and new Bundle Adjust


## 8. Second Pass SFS for final products


### 8.1 Make the SFS DEM

```bash
export NOSLEEP=true
export SUBMIT=true
export RUN_MODE='standard'
export ROBUST_THRESHOLD=0.05
export PADDING_SIZE=32
export INITIAL_DEM_CONSTRAINT_WEIGHT=0.001
export SHADOW_THRESHOLD=0.005
for i in roi_1m_lola.tile.*.vrt; do
    export DEM=$(realpath $i)
    export IMAGES="sfs/${i%.vrt}.IMAGES.txt"
    export CAMERAS="sfs/${i%.vrt}.CAMERAS.txt"
    export _SFS_PREFIX="sfs/${i%.vrt}/${i%.vrt}"
    export SFS_PREFIX="${_SFS_PREFIX//./_}"
    echo $DEM
    echo $IMAGES
    echo $CAMERAS
    echo $SFS_PREFIX
    sfs.pbs
done
```

### 8.2 Make the SFS Height Error Maps

Height Errors use a different RUN_MODE (to be faster/cheaper) from the SFS job and we need to also specify `HEIGHT_ERRORS` as a variable.

```bash
export NOSLEEP=true
export SUBMIT=true
export HEIGHT_ERRORS=true
export RUN_MODE='errors'
for i in roi_1m_lola.tile.*.vrt; do
    export _SFS_PREFIX="sfs_ba1_ref_mm_has/${i%.vrt}/${i%.vrt}"
    export SFS_PREFIX="${_SFS_PREFIX//./_}"
    export _DEM="$SFS_PREFIX-DEM-final.tif"
    export DEM=$(realpath $_DEM)
    export IMAGES="sfs/${i%.vrt}.IMAGES.txt"
    export CAMERAS="sfs/${i%.vrt}.CAMERAS.txt"
    echo $DEM
    echo $IMAGES
    echo $CAMERAS
    echo $SFS_PREFIX
    sfs.pbs
done
```

### 8.3 Make the Count Maps

```bash

# first I need to compute the mask files using the correct threshold of 0.002
unset DEBUG
export SHADOW_THRESHOLD=0.002
export SUBMIT=true
export INPUT_DIR="./IMAGES/"
export TIF_POSTFIX='map.ba2_ref_hsa.sfs.tif'
shadow_mask.pbs

# now I can loop through the jobs
export NOSLEEP=true
export SUBMIT=true
for i in roi_1m_lola.tile.*.vrt; do
    export DEM=$(realpath $i)
    _bounds=$(rio bounds $DEM --projected --bbox)
    _bounds="${_bounds:1:-1}"
    export PROJWIN="${_bounds//,/}"
    export IMAGES="sfs/${i%.vrt}.IMAGES.txt"
    export IMAGE_LIST="sfs/${i%.vrt}.MASK_IMAGES.txt"
    export OUT_NAME="sfs/${i%.vrt}.count.lit.tif"
    cat "$IMAGES" | sed 's/.cub/.map.ba2_ref_hsa.sfs.mask.tif/g' > "$IMAGE_LIST"
    echo $OUT_NAME
    echo $IMAGE_LIST
    echo $PROJWIN
    run_individual_count_lit.pbs 
done

cd sfs
gdalbuildvrt roi.count.lit.cog.vrt *.count.lit.cog.tif

gdal_translate --config GDAL_NUM_THREADS 38  -co BIGTIFF=YES -co NUM_THREADS=38 -co COMPRESS=ZSTD -co PREDICTOR=2 -ot UInt16 -of COG roi_sfs.count.lit.cog.vrt roi_sfs.count.lit.cog.tif
```

### 8.4 Make the Max Lit Maps

```bash
export NOSLEEP=true
export SUBMIT=true
for i in roi_1m_lola.tile.*.vrt; do
    export DEM=$(realpath $i)
    _bounds=$(rio bounds $DEM --projected --bbox)
    _bounds="${_bounds:1:-1}"
    export PROJWIN="${_bounds//,/}"
    export IMAGES="sfs/${i%.vrt}.IMAGES.txt"
    export IMAGE_LIST="sfs/${i%.vrt}.MAPPROJ_IMAGES.txt"
    cat "$IMAGES" | sed 's/.cub/.map.ba2_ref_hsa.sfs.tif/g' > "$IMAGE_LIST"
    export OUT_NAME="sfs/${i%.vrt}.max.lit.tif"
    echo $OUT_NAME
    echo $IMAGE_LIST
    echo $PROJWIN
    run_individual_max_lit.pbs
done

gdalbuildvrt roi_sfs.max.lit.lerc.cog.vrt *.max.lit.lerc.cog.tif
gdalbuildvrt roi_sfs.max.lit.vrt *.max.lit.tif
gdal_translate --config GDAL_NUM_THREADS 38 -co NUM_THREADS=38 -co COMPRESS=LERC_DEFLATE -co MAX_Z_ERROR="0.00033" -co PREDICTOR=3 -ot Float32 -of COG roi_sfs.max.lit.lerc.cog.vrt roi_sfs.max.lit.lerc.cog.tif
gdal_translate --config GDAL_NUM_THREADS 38 -co BIGTIFF=YES -co NUM_THREADS=38 -co COMPRESS=ZSTD -co PREDICTOR=3 -ot Float32 -of COG roi_sfs.max.lit.vrt roi_sfs.max.lit.tif
```

### 8.5 Make The Max Lit Index Maps and VRTs

```bash
export NOSLEEP=true
export SUBMIT=true
for i in roi_1m_lola.tile.*.vrt; do
    export DEM=$(realpath $i)
    _bounds=$(rio bounds $DEM --projected --bbox)
    _bounds="${_bounds:1:-1}"
    export PROJWIN="${_bounds//,/}"
    export IMAGES="sfs/${i%.vrt}.IMAGES.txt"
    export IMAGE_LIST="sfs/${i%.vrt}.MAPPROJ_IMAGES.txt"
    export OUT_NAME="sfs/${i%.vrt}.max.lit.index.tif"
    echo $OUT_NAME
    echo $IMAGE_LIST
    echo $PROJWIN
    run_individual_max_lit_indexes.pbs
done

```

make all the vrt's that actually apply the RAT to the individual tif files

```bash

for i in *index.tif; do
    list="$i-index-map.txt"
    add_rat_to_vrt "$i" "$list"
done
```

### 8.6 Make the SFS Blend Products

```bash
export SUBMIT=true
export REF_DEM="roi_1m_lola.tif"
export SFS_DEM="sfs/sfs_dem.tif"
export MAX_LIT="sfs/sfs_max_lit.tif"
run_sfs_blend.pbs
```

### 8.7 Run the final Map Projection

We run the mapproj_ba.pbs script again but this time 
we set the SFS_FLAG parameter to ensure we can distinguish these dems from the others

```bash
export SUBMIT=true
export DEM="sfs/sfs_dem.tif"
export SFS_FLAG=".sfs"
export BA_PREFIX='ba2_ref_hsa/ba2_ref_hsa'
export IMAGE_LIST="./ba2_ref_hsa/ba2_ref_hsa-image_list.txt"
export CAMERA_LIST="./ba2_ref_hsa/ba2_ref_hsa-camera_list.txt"
export SUBMIT=true
unset DEBUG
mapproj_ba.pbs

```