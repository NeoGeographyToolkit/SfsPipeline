#!/usr/bin/env bash
#  Usage

if [ "$#" -eq 0 ]; then 
    echo "Usage: $0 <spatial db of observations (eg gpkg)>"
    exit 1
fi

if [ -n "$2" ]; then
    if [[ "$2" == *"asu"* ]]; then
        pds_url="http://pds.lroc.asu.edu/data/"
    elif [[ "$2" == *"im"* ]]; then
	pds_url="https://pds.lroc.im-ldi.com/data/LRO-L-LROC-2-EDR-V1.0"
    else
        pds_url="https://d2bqlxqdvh9600.cloudfront.net/LROC/EDR"
    fi
else
    pds_url="https://d2bqlxqdvh9600.cloudfront.net/LROC/EDR"
fi

db_file=${1}

# Read the layer name from the file, not the filename stem: a gpkg's internal layer
# name often differs, and a mismatch made the SQL fail with "no such table".
# ogrinfo lists layers as "N: name (type)"; take the first.
layer_name=$(ogrinfo -ro -so "$db_file" 2>/dev/null \
    | awk -F': ' '/^[0-9]+: /{sub(/ \(.*/,"",$2); print $2; exit}')
if [ -z "$layer_name" ]; then
    file_name="${db_file##*/}"
    layer_name="${file_name%%.*}"
fi

if [[ "$pds_url" != *"cloudfront"* ]]; then
    sqlcmd="SELECT replace(FILE_SPECIFICATION_NAME, 'LRO-L-LROC-2-EDR-V1.0', \"$pds_url\") FROM $layer_name"
else
    sqlcmd="SELECT CONCAT(\"$pds_url\", FILE_SPECIFICATION_NAME) FROM $layer_name"
fi

ogr2ogr -sql "$sqlcmd" -f CSV /vsistdout/ "$db_file" | tail -n+2 | sort
