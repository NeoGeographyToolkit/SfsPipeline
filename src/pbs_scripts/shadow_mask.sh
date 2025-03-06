#!/bin/zsh
##############################################
# source asap environment
source init_sfstools.sh
micromamba activate sfstools
export PYTHONHOME=$CONDA_PREFIX
################################################
# Must have 1 arguments. Print usage on failure.
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <i>"
    exit 1
fi
in_img=$1
tmp_mask=${in_img%.tif}.mask.tif
out_mask_geojson=${in_img%.tif}.mask.geojson
out_json=${in_img%.tif}.mask.stats.json
# disable temp file creation for the purpose of this script, theoretically fine to leave but I want fewer random files laying around
export GDAL_PAM_ENABLED=NO
# compute the mask for shadows using gdal calc 
# TODO: I am suspicious a simple threshold like this won't be robust enough
# be a little pesimistic, if you lose terrain that is at the noise floor you couldn't match anyways
gdal_calc --quiet -A $in_img --calc="(2*(A>0.003))+(A<=0.003)" --outfile $tmp_mask --NoData=0 --type Byte --overwrite --co=COMPRESS=LZW --co=NBITS=2
# compute the stats for the mask 
gdalinfo $tmp_mask -hist -json | jq --arg IMG ${in_img##*/}  -c '{'img': $IMG, 'shadowed': .bands[0].histogram.buckets[1], 'illuminated': .bands[0].histogram.buckets[2], 'total_area': (.size[0] * .size[1])}' > $out_json
# recompute the mask 
gdal_calc --quiet -A $in_img --calc="A>0.003" --outfile $tmp_mask --NoData=0 --type Byte --overwrite --co=COMPRESS=LZW --co=NBITS=1
# now only the good illuminated pixels are not nodata, can't get stats per say but can get geometry
gdal_footprint -q -write_absolute_path -max_points 1000 -simplify 50 $tmp_mask -of GeoJSON $out_mask_geojson
# now remove the mask file as we don't need it anymore. 
rm $tmp_mask
# now we are done 
echo "Finished $in_img"