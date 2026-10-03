#!/bin/bash

# Generic dem_mosaic over a list of DEMs or mapprojected images. A thin,
# long-term wrapper: it sets up the environment and runs one dem_mosaic call,
# passing any extra options straight through. Pick the mosaic mode by appending
# the relevant dem_mosaic flags after the required args:
#   blend (default) : (no extra flags)
#   max lit         : --max
#   mean            : --mean
#   valid count     : --count
#   coarser grid    : --tr <meters>
#   drop shadows    : --nodata-threshold <t>
#
# It does NOT build image pyramids (unlike blend_img_mosaic.sh); add a
# stereo_gui --create-image-pyramids-only step yourself if you want them.
#
# Meant to run on a compute node (qsub, e.g. the devel queue), so it uses
# several threads. Do NOT run it on a pfe head node.
#
# Args:
#   demList   text file, one DEM or mapprojected .tif per line
#   output    output tif path (a .tif suffix is optional)
#   currDir   working dir to cd into (project root)
#   [extra dem_mosaic options ...]   passed through verbatim
#
# Env:
#   THREADS   dem_mosaic threads (default 16)

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <demList> <output> <currDir> [extra dem_mosaic options ...]"
    exit 1
fi
demList=$1; shift
output=$1; shift
currDir=$1; shift
cd $currDir

threads=${THREADS:-16}
prefix=${output%.tif}

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022    # make outputs readable by others
ulimit -c 0  # no core dumps

out=output_$(basename $prefix).txt
echo "dem_mosaic_list: demList=$demList output=${prefix}.tif threads=$threads extra=$*"
echo "log: $(pwd)/$out"
/bin/rm -f $out

dem_mosaic --threads $threads \
    --dem-list $demList       \
    -o $prefix                \
    "$@"                      \
    >> $out 2>&1
