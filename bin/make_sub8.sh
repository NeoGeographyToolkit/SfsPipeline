#!/bin/bash
# Make low-resolution (sub8) copies of mapprojected images for image_subset.
#
# Replaces the old stereo_gui image-pyramid approach (prepare_lowres.sh): stereo_gui
# no longer writes _subN.tif pyramids (it uses on-the-fly overlay), so we build the
# low-res copies directly with gdal_translate, per the ASP image_subset docs
# (:numref:`image_subset`). Each copy is reduced to PERCENT of the original size with
# -r average (averaging avoids aliasing and preserves the data type and the
# georeferencing, so the reduced images stay registered to each other).
#
# PERCENT default 12.5 = 1/8 = sub8 (the finest low-res level we use; never coarser
# than sub8, which loses too much for reliable coverage). The ASP doc example uses
# 6.25% = sub16; 12.5% is the SfS default here.
#
# For each input map tif, writes <sub8Dir>/<base>_sub8.tif and appends its path to
# <sub8ListOut> (same order as the input). Idempotent: an existing sub8 copy is reused.
#
# Usage: make_sub8.sh <mapList> <sub8Dir> <sub8ListOut> <currDir> [percent]
#   mapList       list of full-res mapprojected tifs (paths relative to currDir or absolute)
#   sub8Dir       output dir for the reduced copies
#   sub8ListOut   output list of the reduced copies, in input order
#   currDir       work dir to cd into
#   percent       output size as a percent of the input (default 12.5 = sub8)
set -e
if [ "$#" -lt 4 ]; then
  echo "Usage: $0 <mapList> <sub8Dir> <sub8ListOut> <currDir> [percent]"
  exit 1
fi
mapList=$1; shift
sub8Dir=$1; shift
sub8Out=$1; shift
currDir=$1; shift
pct=${1:-12.5}
cd "$currDir"

export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-${CONDA_PREFIX:-$HOME/miniconda3/envs/isis}}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
share=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/share
[ -d "$share/proj" ] && export GDAL_DATA=$share/gdal PROJ_DATA=$share/proj PROJ_LIB=$share/proj
export GDAL_NUM_THREADS=1
umask 022
ulimit -c 0

mkdir -p "$sub8Dir"
: > "$sub8Out"
made=0; reused=0
while read -r map; do
  [ -z "$map" ] && continue
  base=$(basename "$map"); base=${base%.tif}
  out="$sub8Dir/${base}_sub8.tif"
  if [ ! -f "$out" ]; then
    gdal_translate -outsize "${pct}%" "${pct}%" -r average \
      -co COMPRESS=LZW -co TILED=yes "$map" "$out" > /dev/null
    made=$((made + 1))
  else
    reused=$((reused + 1))
  fi
  echo "$out" >> "$sub8Out"
done < "$mapList"

echo "make_sub8: wrote $(wc -l < "$sub8Out") entries to $sub8Out (made $made, reused $reused, pct=$pct)"
