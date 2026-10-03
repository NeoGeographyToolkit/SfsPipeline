#!/bin/bash
# Prepare low-resolution mapprojected images for image_subset coverage selection.
#
# For each full-res mapprojected tif, ensure its stereo_gui pyramid exists, then pick
# the best available sub level and write its path to an output list (one chosen file
# per input map, same order). Preference: sub8 > sub4 > sub2 > full-res. NEVER coarser
# than sub8 (do not use sub16/sub32 - too coarse for reliable coverage). Tiny images
# whose pyramid stops early fall back to the finest available. No symlinks: image_subset
# --image-list reads the chosen-level paths directly.
#
# Usage: prepare_lowres.sh <mapList> <lowresListOut> <currDir>
#   mapList        list of full-res mapprojected tifs (e.g. map_htdem/<id>.map.tr1.tif)
#   lowresListOut  output list of chosen low-res files, in input order
#   currDir        work dir to cd into (paths in mapList are relative to it)
set -e
if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <mapList> <lowresListOut> <currDir>"
  exit 1
fi
mapList=$1; shift
lowresOut=$1; shift
currDir=$1; shift
cd "$currDir"

export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
share=$HOME/projects/BinaryBuilder/$s/share
[ -d "$share/proj" ] && export GDAL_DATA=$share/gdal PROJ_DATA=$share/proj PROJ_LIB=$share/proj
umask 022
ulimit -c 0

: > "$lowresOut"
missing=0
while read -r map; do
  [ -z "$map" ] && continue
  base=${map%.tif}
  # ensure a pyramid exists; build it if even sub2 is absent
  if [ ! -f "${base}_sub2.tif" ]; then
    stereo_gui --create-image-pyramids-only "$map" > /dev/null 2>&1 || true
  fi
  # pick best available: sub8 > sub4 > sub2 > full
  chosen=""
  for lvl in 8 4 2; do
    if [ -f "${base}_sub${lvl}.tif" ]; then chosen="${base}_sub${lvl}.tif"; break; fi
  done
  if [ -z "$chosen" ]; then
    chosen="$map"          # no pyramid (tiny image): fall back to full-res
    missing=$((missing + 1))
  fi
  echo "$chosen" >> "$lowresOut"
done < "$mapList"

echo "wrote $(wc -l < "$lowresOut") lowres entries to $lowresOut ($missing fell back to full-res)"
