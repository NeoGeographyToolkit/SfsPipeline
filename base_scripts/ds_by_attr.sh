#!/usr/bin/env bash
#  Usage

if [ "$#" -eq 0 ]; then 
    echo "Usage: $0 <spatial db of observations (eg gpkg)> <min_value> <max_value> ?attr ?ret"
    exit 1
fi

if [[ -z "$4" ]]; then
    attr="ROI_SUB_SOLAR_GROUND_AZIMUTH"
else
    attr="$4"
fi

if [[ -z "$5" ]]; then
    ret="PRODUCT_ID"
else
    ret="$5"
fi

db_file=${1}
min_value=${2}
max_value=${3}
file_name="${db_file##*/}"
layer_name="${file_name%%.*}"

sqlcmd="SELECT $ret FROM $layer_name WHERE $attr >= $min_value AND $attr < $max_value"

ogr2ogr -sql "$sqlcmd" -f CSV /vsistdout/ "$db_file" | tail -n+2