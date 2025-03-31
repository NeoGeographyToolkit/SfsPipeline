# sfstools
A place for scripts to support the practical operation of SfS.

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
# within your .bashrc/.zshrc file add:
export PATH="$PATH:/path/to/sfstools/base_scripts/:/path/to/sfstools/src/pbs_scripts/"
export ISISDATA=/path/to/your/ISISDATA/
export ISISROOT=/path/to/your/conda/envs/isis
export ASPROOT=/path/to/your/extracted/ASP/ 
```

7. To run the commands below simply activate the `sfstools` conda environment. The bash and PBS scripts however shouldn't need this and they should be available in your PATH regardless of the conda environment. 

8. To run ISIS or ASP commands invoke `source init_asp.sh`, to run sfstool tools and GDAL use `source init_sfstools.sh`.


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
  - Optional script to investigate "good stereo" availability prior to BA (you can skip entirely)
4. db_to_urls.sh (💻/☁️)
  - Given sfs-cover output get S3 urls to images/labels for downloading via wget
5. calibrate_edr.pbs (☁️)
  - PBS batch job for calibrating/spiceinit'ing images, making CSM models, etc, run on PFE to submit job.
6. mapproj_noba.pbs (☁️)
  - PBS batch job for map projecting CUB files given CSM models
7. prepare_ba0_lists.sh (💻)
  - Given folder of cubs and csm cameras generate most of the list text files bundle adjust needs (may be deprecated)
8. find_overlaps_for_bundle_adjust.py (💻)
  - Given sfs cover output determine likely matching images by overlap and lighting geometry to feed pairs list to bundle adjust
9. solar_az_animate.py (💻)
  - Optional script to view footprint coverage given solar ground azimuth bins via animation in matplotlib
10. bundle_adjust_pt1.pbs (☁️)
  - PBS batch job First pass bundle adjust that just computes statistics and matches for bundle adjust
11. bundle_adjust_pt2.pbs (☁️)
  - PBS batch job that only runs 1 node to perform bundle adjust optimization
12. mapproj_ba.pbs (☁️)
13. verify_bundle_adjust.py (💻)
14. get_stereo_pairs_from_bundle_adjust.py (💻)
15. launch_individual_stereo_jobs.sh (☁️)
  - Script that launches individual stereo jobs each as PBS jobs that use 1 node each 
16. triangulation_plot.py (💻)
  - utility plot tool to plot triangulation error images in python without stereo-gui



## Command Line Tools


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

## Finding stereo pairs from SFS Cover outputs

```bash
find-stereo-pairs --db_path /tmp/mons_mouton_regional.gpkg -p "POLYGON((72471.2817000002 158818.3489,128308.508199999 158818.3489,128308.508199999 119030.173,72471.2817000002 119030.173,72471.2817000002 158818.3489))" -g /tmp/stereo_pairs_mons_mouton_regional.gpkg
```

and again metadata is propogated from the source GPKG file:

```bash
ogrinfo /tmp/stereo_pairs_mons_mouton_regional.gpkg stereo_pairs_mons_mouton_regional -so | head
INFO: Open of `/tmp/stereo_pairs_mons_mouton_regional.gpkg'
      using driver `GPKG' successful.

Layer name: stereo_pairs_mons_mouton_regional
Metadata:
  PROVENANCE={"date":"2025-01-31 09:29:41.468754","user":"aannex","hostname":"starmirage","md5sum":"828e6e35a977a67f4ab16eab59dd2bfe"}
Geometry: Unknown (any)
Feature Count: 273
Extent: (37521.275857, 67456.116796) - (153931.222797, 187826.424185)
Layer SRS WKT:
```

## Downloading EDRs fast

```bash
db_to_urls.sh lrocedrlist.gpkg | xargs -n 1 -P 8  -I {} wget {} -P ~/nobackup/LROCNACEDR/
```

db_to_urls.sh (in base scripts) outputs a list of formatted URLs from a GeoPackage/other spatial format (for now just output from sfs-cover)
into URLs that by default use the USGS AWS mirror of LROC NAC PDS data, which has much more bandwidth than the ASU servers.

You can pass those to xargs and wget them in parallel, an example that downloaded almost 600 Gb only took a few minutes (maybe 10-15)

## Get the list of Product Id's and their sub solar ground azimuths as a list

This will just output two columns with no header due to the sed call
```bash
ogr2ogr -f CSV /vsistdout/  buffered_1km_mons_mouton_regional.gpkg -sql 'SELECT PRODUCT_ID, SUB_SOLAR_GROUND_AZIMUTH from buffered_1km_mons_mouton_regional ORDER BY SUB_SOLAR_GROUND_AZIMUTH ASC' | sed '1d'
```


## Get the projected extent of a raster (eg the DEM) 

```bash
rio bounds M2M_mons_mouton_lola_5mpp_erode_blend.tif --projected | jq -c '.bbox'
```

## Convert a bounds to a WKT polygon
```bash
python -m fire shapely box 72470.0 119030.0 128310.0 158820.0

POLYGON ((128310 119030, 128310 158820, 72470 158820, 72470 119030, 128310 119030))
```

## Expand projwin by half a meter
```bash
wkt-round-out 'POLYGON ((128310 119030, 128310 158820, 72470 158820, 72470 119030, 128310 119030))'
72469.5 119029.5 128310.5 158820.5
```


## First round ba0 bundle adjust make lists of good images/cameras/mapprojected images

```bash
cd folder/with/cubsandtifsandjsons
# images.txt is the sub solar ground azimuth ordered list of product ids
cat ../images.txt | prepare_ba0_lists.sh 
# IMAGES.txt, CAMERAS.txt, MAPPROJ_DATA.txt will be made
# append the dem
echo "path/to/dem.tif" >> MAPPROJ_DATA.txt
```


## combine folder of geojson files into one geojson file

```bash
jq '{"type": "FeatureCollection", "features": [.[] | .features[]]}' --slurp ./folder/*.geojson  > ./all_footprints.geojson
```

## combine the footprints geojson with the source database, retaining the new geometies

TODO recompute fractional area

```bash
duckdb -c "LOAD spatial; CREATE TEMP TABLE df AS SELECT * FROM ST_READ('/tmp/buffered_1km_mons_mouton_regional.gpkg'); CREATE TEMP TABLE ov AS SELECT split_part(parse_filename(O.location, true),'.',1) as PRODUCT_ID, ST_ConvexHull(geom) as geom FROM ST_READ('./all_footprints.geojson') O; CREATE TEMP TABLE merged AS SELECT * EXCLUDE (geom), ov.geom FROM df JOIN ov ON df.PRODUCT_ID == ov.PRODUCT_ID; COPY merged TO 'mapprojected_footprints_noba.gpkg' WITH (FORMAT GDAL, DRIVER 'GPKG', SRS 'IAU:30135');"
```


## get the image ids that had high mean residuals as a CSV

```bash
duckdb -csv -c "SELECT \"# Image\" FROM read_csv('./ba0/ba0-final_residuals_stats.txt', skip=1, header=True) WHERE median > 2 AND isfinite(median)"
```


## inspect the mapproj_match_offset_stats and mapproj_match_offset_pair_stats.txt files

```bash
duckdb -c "SELECT * FROM read_csv('./baA/baA-mapproj_match_offset_stats.txt', skip=0, sep=' ',  header=False);"


duckdb -c "SELECT * FROM read_csv('./baA/baA-mapproj_match_offset_pair_stats.txt', skip=0, sep=' ',  header=False) WHERE column5 <= 1.75 AND column5 > 0"

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

TODO join also with residuals to pick low residuals only

```bash
duckdb -csv -c "INSTALL json; LOAD json; WITH comp AS (SELECT UNNEST(components[1]) as product_ids FROM read_json_auto('./test_delta/bundle_adjust_components.json')) SELECT replace(column0,'.cub', '.map.noba.tif'), replace(column1, '.cub', '.map.noba.tif') FROM read_csv('./baD/baD-convergence_angles.txt', skip=2, header=False, sep=' ') JOIN comp ON comp.product_ids = column1 WHERE column2 > 10 AND column5 > 1000 ORDER BY column5 DESC;" | sed 's/,/ /g' | tail -n +2 > ./test_delta/CAMERA_PAIR_LIST.txt
```

```bash
duckdb -csv -c "INSTALL json; LOAD json; WITH comp AS (SELECT UNNEST(components[1]) as product_ids FROM read_json_auto('./test_delta/bundle_adjust_components.json')), final_resid AS (SELECT \"# Image\" as product_ids FROM read_csv('./baD/baD-final_residuals_stats.txt', skip=1, header=True) WHERE median < 1.5 AND isfinite(median)) SELECT replace(column0,'.cub', '.map.noba.tif'), replace(column1, '.cub', '.map.noba.tif') FROM read_csv('./baD/baD-convergence_angles.txt', skip=2, header=False, sep=' ') JOIN final_resid AS fr0 ON fr0.product_ids = column0 JOIN final_resid AS fr1 ON fr1.product_ids = column1 JOIN comp AS c0 ON c0.product_ids = column0 JOIN comp AS c1 ON c1.product_ids = column1  WHERE column2 > 10 AND column5 > 1000 ORDER BY column5 DESC;" | sed 's/,/ /g' | tail -n +2 > ./test_delta/CAMERA_PAIR_LIST.txt
```


### print out just the largest component list to txt list

```bash
cat bundle_adjust_components.json | jq  -r '.["components"][0][]' > BEST_IMAGES.txt
# use sed to generate cameras
cat bundle_adjust_components.json | jq  -r '.["components"][0][]' | sed 's/cub/json/g' > BEST_CAMERAS.txt
# and get the best bundle adjusted versions of these cameras

```


TODO don't I have a generic utility for plotting anticipated stereo pairs? 



## get the good stereo pair options from the convergence angle file
column2 is the 25% value for the convergence angle (conservative)
and column5 is the number of matches between the two images.

```bash
duckdb  -c "SELECT * FROM read_csv('./ba0/ba0-convergence_angles.txt', skip=2, header=False, sep=' ') WHERE column2 > 10 AND column5 > 10 ORDER BY column5 DESC"
```
note this will return the image files, not the map projected images so to get a more usable list do

```bash
duckdb -csv -c "SELECT replace(column0,'.cub', '.map.noba.tif'), replace(column1, '.cub', '.map.noba.tif') FROM read_csv('./ba0/ba0-convergence_angles.txt', skip=2, header=False, sep=' ') WHERE column2 > 10 AND column5 > 10"
```

to get a stereo pair list file use the `get_stereo_pairs_from_bundle_adjust.py` script

```bash
# first get the list assuming bundle-adjusted map projected images
get_stereo_pairs_from_bundle_adjust.py baD/baD ./test_delta/bundle_adjust_components.json --use_ba_mapproj_tifs  --max_residual_error 1.25 --max_mapproj_error 1.75 > ./test_delta/STEREO_PAIR_LIST_BA.txt 
# and next from raw cameras
get_stereo_pairs_from_bundle_adjust.py baD/baD ./test_delta/bundle_adjust_components.json --max_residual_error 1.25 --max_mapproj_error 1.75 > ./test_delta/STEREO_PAIR_LIST_NOBA.txt 
```
(these files are the IMAGE_PAIR_LIST.txt files to use)

and then use SED to get the corresponding adjusted_cameras for the CAMERA_PAIR_LIST.txt:

```bash
cat ./test_delta/STEREO_PAIR_LIST_NOBA.txt | sed 's/IMAGES\//baD\/baD-/g' | sed 's/.map.noba.tif/.adjusted_state.json/g' > ./test_delta/CAMERA_PAIR_LIST.txt 
```

## running stereo pairs as individual jobs

we will use the launch_individual_stereo_jobs.sh script to parse the image and camera pairs and launch a bunch of small low priority jobs 

```bash
export DEM=/home7/aannex/nobackup/DATA/MONS_MOUTON_10k/m2m_mons_mouton_10k.tif
export IMAGE_PAIR_LIST=/home7/aannex/nobackup/DATA/MONS_MOUTON_10k/test_delta/STEREO_PAIR_LIST_NOBA.txt
export CAMERA_PAIR_LIST=/home7/aannex/nobackup/DATA/MONS_MOUTON_10k/test_delta/CAMERA_PAIR_LIST.txt
export BA_PREFIX='baD/baD'
export SUBMIT=true
launch_individual_stereo_jobs.sh
```


## get metadata for product ids used in convergence angle file

we need to join the two csvs and make an output similar to the find_stereo_pairs overlap file preferably as a geopackage output. For best results use the updated map projected footprints database file.

```sql
INSTALL SPATIAL;
LOAD SPATIAL;
CREATE TEMP TABLE conv AS SELECT * FROM  read_csv('./baD/baD-convergence_angles.txt', skip=2, header=False, sep=' ');
CREATE TEMP TABLE md AS SELECT * FROM ST_Read('./mapprojected_footprints_noba_mons_mouton_10k.gpkg');
CREATE TEMP TABLE 
            pairs
    AS SELECT
            L.PRODUCT_ID      as L_PRODUCT_ID,
            L.VOLUME_ID       as L_VOLUME_ID,
            L.ORBIT_NUMBER    as L_ORBIT_NUMBER,
            L.PHASE_ANGLE     as L_PHASE_ANGLE,
            L.EMISSION_ANGLE  as L_EMISSION_ANGLE,
            L.INCIDENCE_ANGLE as L_INCIDENCE_ANGLE,
            L.SUB_SOLAR_GROUND_AZIMUTH as L_SUB_SOLAR_GROUND_AZIMUTH,
            L.SUB_SPACECRAFT_GROUND_AZIMUTH as L_SUB_SPACECRAFT_GROUND_AZIMUTH,
            L.RESOLUTION      as L_RESOLUTION,
            ST_AREA(L.geom)   as L_area,
            R.PRODUCT_ID      as R_PRODUCT_ID,
            R.VOLUME_ID       as R_VOLUME_ID,
            R.ORBIT_NUMBER    as R_ORBIT_NUMBER,
            R.PHASE_ANGLE     as R_PHASE_ANGLE,
            R.EMISSION_ANGLE  as R_EMISSION_ANGLE,
            R.INCIDENCE_ANGLE as R_INCIDENCE_ANGLE,
            R.SUB_SOLAR_GROUND_AZIMUTH as R_SUB_SOLAR_GROUND_AZIMUTH,
            R.SUB_SPACECRAFT_GROUND_AZIMUTH as R_SUB_SPACECRAFT_GROUND_AZIMUTH,
            R.RESOLUTION      as R_RESOLUTION,
            ST_AREA(R.geom)   as R_area,
            ST_INTERSECTION(L.geom, R.geom) as geom,
            ABS(L.EMISSION_ANGLE - R.EMISSION_ANGLE) as EMISSION_DIFF,
            conv.column2 as angle_percentiles_25,
            conv.column3 as angle_percentiles_50,
            conv.column4 as angle_percentiles_75,
            conv.column5 as num_angles_per_pair,
    FROM 
        conv 
    JOIN 
        md AS L ON CONTAINS(conv.column0,L.PRODUCT_ID) 
    JOIN
        md AS R ON CONTAINS(conv.column1,R.PRODUCT_ID)
    WHERE 
      conv.column2 > 10 AND conv.column5 > 10  
    ORDER BY 
      conv.column5 DESC; 
COPY (SELECT * FROM pairs) TO './mons_mouton_10k_baD_convergence_angles.gpkg'         
    WITH (FORMAT GDAL, DRIVER 'GPKG', SRS 'IAU:30135');
```


#### TODO: 



### geodiff for stereo pairs

```bash
function gim {                                    
  gdalinfo -stats $1 | grep -i Maximum | grep -i mean
}

function jim {
  gdalinfo $1 -stats -json | jq -c '.bands[0].metadata | .[""]'
}

source init_asp.sh
for i in ./*/*DEM.tif; do ; geodiff --threads 8 $i $DEM  -o "${i%/*}/run"; done
# then
```


### various untested bash commands

```bash
# evict images that had high error
grep -F -x -v -f bad_images.txt all_images.txt

# get good images only (might be kinda useless, just use the good list at this point)
grep -F -x -f good_images.txt all_images.txt
```

## dem mosaic
first decide which are good

```bash
function jim {
  gdalinfo $1 -stats -json | jq -c ".bands[0].metadata | .[""] + {file: \"$1\"}"
}
dem_mosaic ./*/run-DEM.tif -o all_dem_mosaic.tif
for i in ./*/*DEM.tif; do gdal_translate -r average -outsize 50% 50% $i ${i%.tif}.half.tif; done
#for i in ./*/*DEM.half.tif; do; geodiff --threads 8 $i $DEM -o "${i%/*}/run-ref"; done
for i in ./*/*DEM.half.tif; do; geodiff --threads 8 $i all_dem_mosaic.tif -o "${i%/*}/run-all"; done
#for i in <good images>; do; geodiff --threads 8 $i good_dem_mosaic.tif -o "${i%/*}/run-good"; done
# look for the ones with low mean differences here
# cross reference with low triangulation error
for i in ./*/run-all-diff.tif; do echo $(jim $i) >> diff_all_jim.txt; done
for i in ./*/*IntersectionErr.tif; do echo $(jim $i) >> inter_all_jim.txt; done 
# remove diffs with means larger than 10/less than-10
# remove intersection errors larger than 1 meter mean





# then make the good_dem_mosaic
dem_mosaic <good dems only> -o good_dem_mosaic.tif
# then diff again
for i in `cat good_list.txt`; do geodiff --threads 8 $i good_dem_mosaic.tif -o "${i%/*}/run-good"; done

for i in ./*/run-good-diff.tif; do echo $i $(gim $i); done


```

## triangulation error plotting
I needed more control over error plotting so I AI-slopped the script `triangulation_plot.py`
```bash
# plot the hillshades
python ~/projects/sfstools/src/loony/triangulation_plot.py ./*/*DEM.half.tif --hillshade
# plot the intersection errors
python ~/projects/sfstools/src/loony/triangulation_plot.py ./*/*IntersectionErr.tif --out-prefix intersec
```



## pc align
```bash
pc_align --threads 8 --max-displacement 500 all_dem_mosaic_baD.tif $DEM --save-inv-transformed-reference-points -o run_align_all/run 

pc_align --threads 8 --alignment-method nuth --max-displacement 500 all_dem_mosaic_baD.tif $DEM --save-inv-transformed-reference-points -o run_align_all_nuth/run 



pc_align --threads 8 --max-displacement 500 good_dem_mosaic.tif ../M2M_mons_mouton_lola_5mpp_erode_blend.tif --save-inv-transformed-reference-points -o run_align_good/run 



pc_align --threads 8 --alignment-method nuth --max-displacement 500 good_dem_mosaic.tif ../M2M_mons_mouton_lola_5mpp_erode_blend.tif --save-inv-transformed-reference-points -o run_align_good_nuth/run 
```


## compute valid pixels for avoiding shadowed images

todo I suspect bundle adjust basically computes this already, but we could potentially
pre-filter the images we use to ensure at least some of the pixels are actually illuminated after map projection to 
the reference DEM.

```bash
# todo move to funct
gdal_calc -A $1.noba.tif --calc="A>0.001" --outfile ~/$1_mask.tif --NoData=0 --type Byte --overwrite --co=COMPRESS=LZW
gdalinfo ~/$1_mask.tif -stats # get the valid pixels from here
```



## get lists of files after bundle adjust refinement for maximally lit mosaics

```bash
duckdb -csv -c "WITH tbl AS (SELECT * FROM read_csv('../baD_align_ref/baD-mapproj_match_offset_pair_stats.txt', skip=0, sep=' ',  header=False) WHERE column5 < 1.0 AND column5 > 0 AND column7 > 1000 ORDER BY column5) SELECT column0 as img FROM tbl UNION SELECT column1 FROM tbl AS img;" | tail -n +2 | sort > max_list_list_limit_1.txt
```

from testing, raising the max 85% error value (column5) past 1 meter didn't add as many images as changing the tolerance on the number of matches (column7). For that, a value of 100 was found to be too permissive. 500 was found to be just on the edge (maybe a bad image or two is included), while 1000 seemed perfect, although some illumination diversity was lost.