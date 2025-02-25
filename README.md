# sfstools
A place for scripts to support the practical operation of SfS.

The main documentation for the Ames Stereo Pipeline SfS is available here: 
https://stereopipeline.readthedocs.io/en/latest/sfs_usage.html

We will use this as the reference document, but there are many practical aspects of generating DEMs via SfS that are not necessarily documented. 




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
gr2ogr -f CSV /vsistdout/  buffered_1km_mons_mouton_regional.gpkg -sql 'SELECT PRODUCT_ID, SUB_SOLAR_GROUND_AZIMUTH from buffered_1km_mons_mouton_regional' | sed '1d'
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

and to get a usable list file:

```bash
duckdb -csv -c "SELECT replace(column0,'.cub', '.map.noba.tif'), replace(column1, '.cub', '.map.noba.tif') FROM read_csv('./ba0/ba0-convergence_angles.txt', skip=2, header=False, sep=' ') WHERE column2 > 10 AND column5 > 10  ORDER BY column5 DESC"  | sed 's/,/ /g' | tail -n +2 > IMAGE_PAIR_LIST.txt
```

and the adjusted camera list file

```bash
duckdb -csv -c "SELECT replace(replace(column0,'.cub', '.adjusted_state.json'), 'IMAGES/', 'ba0/ba0-'), replace(replace(column1, '.cub', '.adjusted_state.json'), 'IMAGES/', 'ba0/ba0-') FROM read_csv('./ba0/ba0-convergence_angles.txt', skip=2, header=False, sep=' ') WHERE column2 > 10 AND column5 > 10  ORDER BY column5 DESC"  | sed 's/,/ /g' | tail -n +2 > CAMERA_PAIR_LIST.txt
```

#### TODO: 

Cross reference this with the main metadata db file (the one used to download image) to ensure pairs are ordered by increassing emission angle


### geodiff for stereo pairs

```bash
source init_asap.sh
for i in ./*/*DEM.tif; do ; geodiff $i $DEM  -o "${i%/*}/run"; done
# then
for i in ./*/*diff.tif; do echo $i $(gim $i); done
```

### various untested bash commands

```bash
# evict images that had high error
grep -F -x -v -f bad_images.txt all_images.txt

# get good images only (might be kinda useless, just use the good list at this point)
grep -F -x -f good_images.txt all_images.txt
```

