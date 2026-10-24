#!/bin/bash

# Blend an SfS DEM back toward the reference (LOLA) DEM where there is little
# illumination signal, using ASP's sfs_blend. A worker to be submitted with
# qsub (see WORKFLOW.md), it takes the project work dir as its last argument.
#
# Keeps the tuned blend parameters from sfs_usage.rst. When USE_VRT=1 is set,
# the SfS DEM and max-lit mosaic are regridded onto the reference DEM grid via
# match_vrt_extent (from sfs_utilities.sh). By default (USE_VRT=0), inputs are
# passed directly if they already share the reference grid.
#
# Inspect the blended result. If a shadowed area needs a touch-up, re-blend a
# padded clip and merge it back with dem_mosaic --priority-blending-length (see
# WORKFLOW.md). The sfs_blend --shadow-fill-mode option
# can also fill holes with a surface grown from the surrounding SfS that curves
# gently downward, instead of using LOLA.
#
# Args:
#   refDem    reference DEM (e.g. the LOLA regrid), defines the output grid
#   sfsDem    the produced SfS DEM
#   maxLit    the max-lit image mosaic over the same area
#   currDir   work dir to cd into (project root), pass as $(pwd)
#
# Env (optional):
#   OUT_BLEND            output blended DEM (default <sfsDem stem>.blend.tif)
#   OUT_WEIGHT           output blend weight (default <sfsDem stem>.weight.tif)
#   SHADOW_THRESHOLD     image threshold for lit vs shadow (default 0.005)
#   LIT_BLEND_LENGTH     blend length into lit area in pixels (default 20)
#   SHADOW_BLEND_LENGTH  blend length into shadow in pixels (default 20)
#   MIN_BLEND_SIZE       minimum shadow hole size to blend (default 25)
#   WEIGHT_BLUR_SIGMA    Gaussian blur sigma for weight (default 10)
#   CACHE_SIZE_MB        ASP cache size in MB (default 4096)
#   THREADS              sfs_blend threads (default: all cores, nproc)
#   USE_VRT              regrid via VRT to match reference (default 0)
#   SHADOW_FILL_MODE     hole fill: lola, curved, lola-curved
#                        (default lola-curved; lola is a plain LOLA fill)
#   SHADOW_FILL_MAX_DIAMETER  max hole diameter in pixels for the curved surface
#                        (default 300)

if [ "$#" -lt 4 ]; then
  echo "Usage: $0 refDem sfsDem maxLit currDir"
  exit 1
fi
refDem=$1; sfsDem=$2; maxLit=$3; currDir=$4
cd "$currDir"

binDir="$(cd "$(dirname "$0")" && pwd)"

export ASPROOT=${ASPROOT:-$HOME/projects/BinaryBuilder/StereoPipeline}
export ISISROOT=${ISISROOT:-${CONDA_PREFIX:-$HOME/miniconda3/envs/asp_deps}}
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
export PATH=$ASPROOT/bin:$ISISROOT/bin:$PATH
umask 022
ulimit -c 0

threads=${THREADS:-${NCPUS:-$(nproc --all)}}
shadowThresh=${SHADOW_THRESHOLD:-0.005}
minBlendSize=${MIN_BLEND_SIZE:-25}
cacheSize=${CACHE_SIZE_MB:-4096}
useVrt=${USE_VRT:-0}
# Default to lola-curved: the per-pixel minimum of the SfS, LOLA, and a surface
# grown from the surrounding SfS that curves gently downward, so LOLA does not
# pop up above the terrain, with the matching feather (lit 20, shadow 20,
# sigma 10). This needs an ASP build that supports sfs_blend --shadow-fill-mode.
# Set SHADOW_FILL_MODE=lola for a plain LOLA fill.
shadowFillMode=${SHADOW_FILL_MODE:-lola-curved}
shadowFillMaxDiam=${SHADOW_FILL_MAX_DIAMETER:-300}
litBlend=${LIT_BLEND_LENGTH:-20}
shadowBlend=${SHADOW_BLEND_LENGTH:-20}
weightBlur=${WEIGHT_BLUR_SIGMA:-10}

stem=${sfsDem%.tif}
outBlend=${OUT_BLEND:-${stem}.blend.tif}
outWeight=${OUT_WEIGHT:-${stem}.weight.tif}

out=output_$(basename "$stem").blend.txt
echo "sfs_blend: ref=$refDem sfs=$sfsDem maxLit=$maxLit -> $outBlend (log $out)"
/bin/rm -f "$out"

if [ "$useVrt" -eq 1 ]; then
  source "$binDir/sfs_utilities.sh"
  inSfs=$(match_vrt_extent "$refDem" "$sfsDem")
  inMax=$(match_vrt_extent "$refDem" "$maxLit")
else
  inSfs="$sfsDem"
  inMax="$maxLit"
fi

sfs_blend                                       \
  --threads $threads                            \
  --lola-dem "$refDem"                          \
  --sfs-dem "$inSfs"                            \
  --max-lit-image-mosaic "$inMax"               \
  --image-threshold "$shadowThresh"             \
  --lit-blend-length $litBlend                  \
  --shadow-blend-length $shadowBlend            \
  --min-blend-size $minBlendSize                \
  --weight-blur-sigma $weightBlur               \
  --shadow-fill-mode $shadowFillMode            \
  --shadow-fill-max-diameter $shadowFillMaxDiam \
  --cache-size-mb $cacheSize                    \
  --output-dem "$outBlend"                      \
  --output-weight "$outWeight"                  \
  >> "$out" 2>&1
