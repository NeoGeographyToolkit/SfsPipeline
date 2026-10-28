#!/bin/bash

# Find max lit mosaic

if [ "$#" -lt 3 ]; then
    Usage: $0 mosaicList mosaicName currDir
    exit
fi
mosaicList=$1; shift
mosaicName=$1; shift
currDir=$1; shift
cd $currDir

echo mosaicList=$mosaicList
echo mosaicName=$mosaicName
echo currDir=$currDir

out=output_$(basename $mosaicName).txt

echo Will write the output to $out
/bin/rm -f $out

# Set up the environment (ASPROOT, ISISROOT, ISISDATA from your .bashrc)
binDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$binDir/sfs_env.sh" || exit 1

dem_mosaic --threads ${NCPUS:-$(nproc --all)} --max --dem-list $mosaicList \
    -o $mosaicName >> $out 2>&1

stereo_gui --create-image-pyramids-only $mosaicName >> $out 2>&1
