#!/bin/bash

# Average (blended weighted-mean) mosaic of mapprojected images, with
# a low-intensity nodata mask so shadow pixels do not pollute the mean.
#
# Default dem_mosaic mode (no --first/--mean/--max/etc.) does a
# grassfire-weighted blend across inputs, producing a smooth seam-free
# average. --nodata-threshold T invalidates per-input pixels with
# value <= T BEFORE accumulation, so shadowed pixels are dropped from
# each image and the remaining lit pixels are blended.
#
# Args:
#   mosaicList  text file, one *.tr1.tif per line (no sub* previews)
#   threshold   nodata threshold (e.g. 0.005 to drop shadow pixels)
#   mosaicName  output tif path
#   currDir     working dir (project root)

if [ "$#" -lt 4 ]; then
    echo "Usage: $0 mosaicList threshold mosaicName currDir"
    exit 1
fi
mosaicList=$1; shift
threshold=$1; shift
mosaicName=$1; shift
currDir=$1; shift
cd $currDir

echo mosaicList=$mosaicList
echo threshold=$threshold
echo mosaicName=$mosaicName
echo currDir=$currDir

out=output_$(basename $mosaicName).txt

echo Will write the output to $out
/bin/rm -f $out

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022

dem_mosaic --threads 20 --nodata-threshold $threshold \
    --output-nodata-value -1e+6 \
    --dem-list $mosaicList \
    -o $mosaicName >> $out 2>&1

stereo_gui --create-image-pyramids-only $mosaicName >> $out 2>&1
