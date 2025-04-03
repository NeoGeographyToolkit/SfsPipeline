#!/usr/bin/env bash
#  Usage

if [ "$#" -eq 0 ]; then 
    echo "Usage: $0 <spatial db of observations (eg gpkg)>"
    exit 1
fi

if [ -n "$2" ]; then
    if [[ "$2" == *"asu"* ]]; then
        pds_url="http://pds.lroc.asu.edu/data/"
    else
        pds_url="https://d2bqlxqdvh9600.cloudfront.net/LROC/EDR"
    fi
else
    pds_url="https://d2bqlxqdvh9600.cloudfront.net/LROC/EDR"
fi

db_file=${1}
file_name="${db_file##*/}"
layer_name="${file_name%%.*}"

if [[ "$pds_url" == *"lroc.asu.edu"* ]]; then
    sqlcmd="SELECT CONCAT(\"$pds_url\", FILE_SPECIFICATION_NAME) FROM $layer_name"
else
    sqlcmd="SELECT replace(FILE_SPECIFICATION_NAME, 'LRO-L-LROC-2-EDR-V1.0', \"$pds_url\") FROM $layer_name"
fi

ogr2ogr -sql "$sqlcmd" -f CSV /vsistdout/ "$db_file" | tail -n+2 | sort