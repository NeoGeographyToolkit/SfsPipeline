# Collection of useful bash 1-liners and small commands that may be helpful.


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

## combine folder of geojson files into one geojson file

```bash
jq '{"type": "FeatureCollection", "features": [.[] | .features[]]}' --slurp ./folder/*.geojson  > ./all_footprints.geojson
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

### print out just the largest component list to txt list

```bash
cat bundle_adjust_components.json | jq  -r '.["components"][0][]' > BEST_IMAGES.txt
# use sed to generate cameras
cat bundle_adjust_components.json | jq  -r '.["components"][0][]' | sed 's/cub/json/g' > BEST_CAMERAS.txt
# and get the best bundle adjusted versions of these cameras

```


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
export DEM=/path/to/dem.tif
export IMAGE_PAIR_LIST=/path/to/STEREO_PAIR_LIST_NOBA.txt
export CAMERA_PAIR_LIST=/path/to/CAMERA_PAIR_LIST.txt
export BA_PREFIX='baD/baD'
export SUBMIT=true
launch_individual_stereo_jobs.sh
```





### geodiff for stereo pairs

```bash
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
tri-plot ./*/*DEM.half.tif --hillshade
# plot the intersection errors
tri-plot ./*/*IntersectionErr.tif --out-prefix intersec
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




## Collect map projected footprints into a update geodatabase (GPKG) file using new scripts (deprecating lots of steps above)


```bash
# need to make this part easier
source ~/projects/SfsPipeline/bin/sfs_utilities.sh

collect_geojson ./IMAGES 'map.baD_align_ref.geojson' > all_map_baD_align_ref_footprints.geojson

collect_geojson ./IMAGES 'map.noba.mask.geojson' > all_map_noba_mask_footprints.geojson

collect_geojson ./IMAGES 'map.baD_align_ref.mask.geojson' > all_map_baD_align_ref_mask_footprints.geojson


update_db_from_footprints.py ./mons_mouton_10k_5m.gpkg ./shadow_mask_mons_mouton_10k_5m.gpkg ./all_map_baD_align_ref_mask_footprints.geojson

```

