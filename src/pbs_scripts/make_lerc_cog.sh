#!/usr/bin/env bash
##############################################
# source bashrc
[ -f ~/.bashrc ] && source ~/.bashrc
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
# must have gdal_translate/etc in path
if ! command -v gdal_translate 2>&1 >/dev/null
then
    echo "gdal_translate could not be found"
    exit 1
fi
# get the input file name
in_name=$1
# set the output name with lerc.cog.tif
out_cog=${in_img%.tif}.lerc.cog.tif
# disable temp file creation for the purpose of this script, theoretically fine to leave but I want fewer random files laying around
export GDAL_PAM_ENABLED=NO
# set the LERC precision level to 0.001, 0.0001 is almost indistinguishable from raw but going above 0.001 started to introduce minor issues up to 0.002 so thinking 0.001 is pretty good with a bonus compression over 0.0001
PREC=0.001
# convert to lerc
gdal_translate --config GDAL_NUM_THREADS 4 -co NUM_THREADS=4 -co COMPRESS=LERC_DEFLATE -co MAX_Z_ERROR="$PREC" -co PREDICTOR=3 -ot Float32 -of COG "$in_name" "$out_cog"
echo "Finished $in_img made $out_cog"