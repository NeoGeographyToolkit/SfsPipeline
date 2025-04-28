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
# must have gdalinfo in path
if ! command -v gdalinfo 2>&1 >/dev/null
then
    echo "gdalinfo could not be found"
    exit 1
fi
# must have gdal_footprint in path
if ! command -v gdal_footprint 2>&1 >/dev/null
then
    echo "gdal_footprint could not be found"
    exit 1
fi

in_img=$1
out_cog=${in_img%.tif}.cog.8bit.tif
# disable temp file creation for the purpose of this script, theoretically fine to leave but I want fewer random files laying around
export GDAL_PAM_ENABLED=NO




echo "Finished $in_img"