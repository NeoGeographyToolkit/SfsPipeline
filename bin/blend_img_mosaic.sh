#!/bin/bash

# Blended ("average") mosaic of mapprojected images, with a low-intensity
# nodata mask so shadow pixels do not pollute the blend.
#
# This is the generic worker for the "average" image mosaics Ross/Artemis
# asked for. It runs ONE dem_mosaic in the default (seamless blend) mode,
# NOT --mean and NOT --max. The blend has no seams: once --nodata-threshold
# turns shadows into a per-input mask, the blend feathers gently across that
# mask boundary, which a plain --mean cannot do (a mean steps abruptly
# wherever the contributing-image count changes).
#
#   --nodata-threshold T   per-input, pixels with value <= T are
#                          invalidated BEFORE accumulation (drops shadows).
#   --output-nodata-value  sentinel for all-nodata output pixels (-1e+6).
#
# No PBS logic here: this is a plain script. The caller (the per-project
# notes) sets any qsub args. Used both per-tile (Mons, via the Mons
# driver) and globally (SP, VIPER, called directly on the full list).
# It supersedes avg_mosaic.sh (same recipe, "blend" is the accurate name).
#
# Args:
#   list            text file, one mapprojected .tif per line
#   output          output tif path
#   threshold       nodata threshold (e.g. 0.005 to drop shadow pixels)
#   currDir         working dir to cd into (project root)
#   threads         optional, default 20
#   buildPyramids   optional, default 1; pass 0 to skip (per-tile intermediates)

if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <list> <output> <threshold> <currDir> [threads] [buildPyramids]"
    exit 1
fi
list=$1
output=$2
threshold=$3
currDir=$4
threads=${5:-$(nproc)}
buildPyramids=${6:-1}
cd $currDir

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022 # make outputs readable by others

out=output_$(basename $output .tif).txt
echo "blend_img_mosaic: list=$list output=$output threshold=$threshold threads=$threads"
echo "log: $(pwd)/$out"
/bin/rm -f $out

dem_mosaic --threads $threads --nodata-threshold $threshold \
    --output-nodata-value -1e+6 \
    --dem-list $list \
    -o $output >> $out 2>&1

if [ "$buildPyramids" != "0" ]; then
    stereo_gui --create-image-pyramids-only $output >> $out 2>&1
fi
