#!/bin/bash

# Function to display help
function display_help() {
    echo "Usage: $0 [options] -i <input_raster> -o <output_raster>"
    echo ""
    echo "Options:"
    echo "  -i <input_raster>    Specify the input raster file"
    echo "  -o <output_raster>   Specify the output 8-bit raster file"
    echo "  -m <method>          Specify the method for scaling: 'minmax' or 'meanstd'"
    echo "  -t <type>            Optionally Specify the output Dtype, either Byte or UInt16"
    echo "  -s <stds>            Optionally Specify the number of standard deviations to scale for 'meanstd'"
    echo "  -h                    Display this help message"
    exit 1
}

# Default values
method="minmax"
stds=1
outtype="Byte"

# Parse command-line options
while getopts "i:o:m:s:t:h" opt; do
    case ${opt} in
        i )
            input_raster=$OPTARG
            ;;
        o )
            output_raster=$OPTARG
            ;;
        m )
            method=$OPTARG
            ;;
        s )
            stds=$OPTARG
            ;;
        t )
            outtype=$OPTARG
            ;;
        h )
            display_help
            ;;
        \? )
            display_help
            ;;
    esac
done


# Check for mandatory options
if [ -z "$input_raster" ] || [ -z "$output_raster" ]; then
    echo "Error: Input and output files must be specified."
    display_help
fi

# Get raster statistics as JSON
stats=$(gdalinfo -stats -json "$input_raster")

# Initialize scale_param
scale_param=""

# Determine number of bands
num_bands=$(echo "$stats" | jq '.bands | length')

# Loop through each band to prepare the scale parameter based on the selected method
for (( band=1; band<=$num_bands; band++ )); do
    if [ "$method" = "minmax" ]; then
        # Scaling based on minimum and maximum values
        min=$(echo "$stats" | jq ".bands[$((band-1))].metadata[\"\"].STATISTICS_MINIMUM | tonumber")
        max=$(echo "$stats" | jq ".bands[$((band-1))].metadata[\"\"].STATISTICS_MAXIMUM | tonumber")
    elif [ "$method" = "meanstd" ]; then
        # Scaling based on mean and standard deviation
        mean=$(echo "$stats" | jq ".bands[$((band-1))].metadata[\"\"].STATISTICS_MEAN | tonumber")
        stddev=$(echo "$stats" | jq ".bands[$((band-1))].metadata[\"\"].STATISTICS_STDDEV | tonumber")
        #min=$(awk "BEGIN {printf \"%.12f\", $mean - ($stddev * $stds)}")
        min=$(echo "$stats" | jq ".bands[$((band-1))].metadata[\"\"].STATISTICS_MINIMUM | tonumber")
        max=$(awk "BEGIN {printf \"%.12f\", $mean + ($stddev * $stds)}")
    else
        echo "Invalid method specified. Use 'minmax' or 'meanstd'."
        exit 1
    fi
done
scale_param="-scale $min $max"
echo "$scale_param"
# Use gdal_translate to create an 8-bit version of the raster
gdal_translate --config GDAL_NUM_THREADS 8 -co NUM_THREADS=8 -co PREDICTOR=2 -co COMPRESS=DEFLATE -ot "$outtype" -of COG -scale "$min" "$max" "$input_raster" "$output_raster"
