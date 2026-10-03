#!/bin/bash

# Blend an SfS DEM back toward the reference (LOLA) DEM where there is little
# illumination signal, using ASP's sfs_blend. A worker to be submitted with
# qsub (see WORKFLOW.md), it takes the project work dir as its last argument.
#
# Keeps the tuned blend parameters from the original SfsPipeline run_sfs_blend
# step. The SfS DEM and the max-lit mosaic are first regridded onto the reference
# DEM grid (match_vrt_extent, from sfs_utilities.sh) so sfs_blend sees aligned
# inputs.
#
# Args:
#   refDem    reference DEM (e.g. the LOLA regrid), defines the output grid
#   sfsDem    the produced SfS DEM
#   maxLit    the max-lit image mosaic over the same area
#   currDir   work dir to cd into (project root), pass as $(pwd)
#
# Env (optional):
#   OUT_BLEND         output blended DEM (default <sfsDem stem>.blend.tif)
#   OUT_WEIGHT        output blend weight (default <sfsDem stem>.weight.tif)
#   SHADOW_THRESHOLD  image threshold for lit vs shadow (default 0.005)
#   THREADS           sfs_blend threads (default: all cores, nproc)

if [ "$#" -lt 4 ]; then
  echo "Usage: $0 refDem sfsDem maxLit currDir"
  exit 1
fi
refDem=$1; sfsDem=$2; maxLit=$3; currDir=$4
cd "$currDir"

binDir="$(cd "$(dirname "$0")" && pwd)"

export ASPROOT=${ASPROOT:-$HOME/projects/BinaryBuilder/StereoPipeline}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
export PATH=$ASPROOT/bin:$ISISROOT/bin:$PATH
umask 022
ulimit -c 0

threads=${THREADS:-$(nproc)}
shadowThresh=${SHADOW_THRESHOLD:-0.005}
stem=${sfsDem%.tif}
outBlend=${OUT_BLEND:-${stem}.blend.tif}
outWeight=${OUT_WEIGHT:-${stem}.weight.tif}

# match_vrt_extent regrids src onto ref's grid and echoes the vrt path
source "$binDir/sfs_utilities.sh"

out=output_$(basename "$stem").blend.txt
echo "sfs_blend: ref=$refDem sfs=$sfsDem maxLit=$maxLit -> $outBlend (log $out)"
/bin/rm -f "$out"

vrtSfs=$(match_vrt_extent "$refDem" "$sfsDem")
vrtMax=$(match_vrt_extent "$refDem" "$maxLit")

sfs_blend                               \
    --threads $threads                  \
    --lola-dem "$refDem"                \
    --sfs-dem "$vrtSfs"                  \
    --max-lit-image-mosaic "$vrtMax"    \
    --image-threshold "$shadowThresh"   \
    --lit-blend-length 25               \
    --shadow-blend-length 5             \
    --min-blend-size 50                 \
    --weight-blur-sigma 5               \
    --cache-size-mb 4096                \
    --output-dem "$outBlend"            \
    --output-weight "$outWeight"        \
    >> "$out" 2>&1
