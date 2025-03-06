#!/usr/bin/env bash
# Log the PBS_NODEFILE if available
if [ -n "$PBS_NODEFILE" ]; then
    echo "Running on PBS node: $(uname -a)"
fi
##############################################
# source asap environment
source init_asap.sh
# echo out ISISDATA and ISISROOT
echo ISIS data is $ISISDATA 
echo ISIS root is $ISISROOT
# echo out PATH
echo PATH is $PATH
################################################
# Must have 1 arguments. Print usage on failure.
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <i>"
    exit 1
fi
in_img=$1
tmp_mask=${in_img%.tif}.mask.tif
out_json=${in_img%.tif}.mask.stats.json
# disable temp file creation for the purpose of this script, theoretically fine to leave but I want fewer random files laying around
export GDAL_PAM_ENABLED=NO
# compute the mask for shadows using gdal calc 
# TODO: I am suspicious a simple threshold like this won't be robust enough
# be a little pesimistic, if you lose terrain that is at the noise floor you couldn't match anyways
/vast_swbuild/swbuild3/aannex/micromamba/envs/sfstools/bin/gdal_calc --quiet -A $in_img --calc="(2*(A>0.003))+(A<=0.003)" --outfile $tmp_mask --NoData=0 --type Byte --overwrite --co=COMPRESS=LZW --co=NBITS=1
# hmm I don't think this correct to use yet,
# I need to distinquish areas that are outside of the data completely 

# compute the stats for the mask 
# gdalinfo $tmp_mask -json -hist  | jq -c '.bands[0].histogram.buckets| 0/ .[2] '
gdalinfo $tmp_mask -json -hist  | jq -c '.bands[0].histogram.buckets| .[1] / .[2] ' # TODO how to avoid divide by 0 if there is no valid data/no invalid data?
/vast_swbuild/swbuild3/aannex/micromamba/envs/sfstools/bin/gdalinfo $tmp_mask -hist -json | jq --arg IMG ${in_img##*/} -c '.bands[0].metadata | .[""] + {img: $IMG}' > $out_json
# 