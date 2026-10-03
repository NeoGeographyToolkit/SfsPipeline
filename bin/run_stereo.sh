#!/bin/bash

# Run one stereo pair with parallel_stereo (asp_mgm), then point2dem
# (--errorimage) and a half-resolution DEM. A worker; qsub it with N nodes and it
# reads $PBS_NODEFILE. Converted from the PBS run_stereo to the worker
# conventions. The stereo parameters are carried over from the original and are
# kept under review (the optional stereo branch, usually skipped for polar SfS).
#
# Args:
#   lImg rImg   left and right images
#   lCam rCam   left and right cameras (already bundle-adjusted)
#   dem         DEM the images were mapprojected onto (if mapprojected)
#   baPrefix    a tag used to name the output directory
#   currDir     work dir to cd into, pass as $(pwd)

if [ "$#" -lt 7 ]; then
  echo "Usage: $0 lImg rImg lCam rCam dem baPrefix currDir"
  exit 1
fi
lImg=$1; rImg=$2; lCam=$3; rCam=$4; dem=$5; baPrefix=$6; currDir=$7
cd "$currDir" || exit 1

export ASPROOT=${ASPROOT:-$HOME/projects/BinaryBuilder/StereoPipeline}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
export PATH=$ASPROOT/bin:$ISISROOT/bin:$PATH
umask 022
ulimit -c 0

lbase=$(basename "$lImg"); rbase=$(basename "$rImg")
outDir="run_stereo_${baPrefix##*/}/${lbase%%.*}__${rbase%%.*}"
mkdir -p "$outDir"

nodesOpt=()
if [ -n "$PBS_NODEFILE" ] && [ -f "$PBS_NODEFILE" ]; then
  nodesOpt=(--nodes-list "$PBS_NODEFILE")
fi

parallel_stereo                     \
    "$lImg" "$rImg" "$lCam" "$rCam" \
    --stereo-algorithm asp_mgm      \
    --nodata-value 0.003            \
    --ip-detect-method 1            \
    --ip-per-tile 400               \
    --ip-per-image 20000            \
    --subpixel-mode 9               \
    --threads-singleprocess 4       \
    --threads-multiprocess 4        \
    --processes 8                   \
    "${nodesOpt[@]}"                \
    "$outDir/run" "$dem"            \
    &> "$outDir/stereo_log.txt"

point2dem --threads 8 --errorimage --tr 1 "$outDir/run-PC.tif" &> "$outDir/point2dem_log.txt"
gdal_translate -r average -outsize 50% 50% "$outDir/run-DEM.tif" "$outDir/run-DEM.half.tif" &> "$outDir/gdal_log.txt"
echo "done: $outDir"
