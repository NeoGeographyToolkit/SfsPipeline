#!/bin/bash
# Prune flagged suspect cameras from chunk map lists and rebuild every max-lit mosaic
# without re-mapprojecting (reuses surviving per-image mapprojected GeoTIFFs).
#
# Implementation of the sfs-post-bundle-eval workflow:
#   1. Drops suspect IDs from each chunk's map_list_<beg>_<end>.txt -> map_list_<beg>_<end>_pruned.txt
#   2. Re-runs dem_mosaic --max per pruned chunk -> max_mosaic_<beg>_<end>_pruned.tif
#   3. Splits pruned chunks into two illumination halves (by chunk index / beg)
#   4. Rebuilds half1_pruned_max_mosaic.tif, half2_pruned_max_mosaic.tif, and all_pruned_max_mosaic.tif
#
# Usage:
#   sfs_prune_and_remosaic.sh <map_dir> <removed_ids.txt> <curr_dir> [half_split_index] [threads]

set -e
if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <map_dir> <removed_ids.txt> <curr_dir> [half_split_index] [threads]"
  exit 1
fi

map_dir="$1"
rm_ids="$2"
curr_dir="$3"
split_idx="${4:-500}"
th="${5:-20}"

cd "$curr_dir"

export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
share=$HOME/projects/BinaryBuilder/$s/share
[ -d "$share/proj" ] && export GDAL_DATA=$share/gdal PROJ_DATA=$share/proj PROJ_LIB=$share/proj
umask 022
ulimit -c 0

if [ ! -f "$rm_ids" ]; then
  echo "Error: Suspect IDs file not found: $rm_ids"
  exit 1
fi

echo "Pruning $(wc -l < "$rm_ids") suspect IDs from $map_dir"

: > "$map_dir/half1_pruned_list.txt"
: > "$map_dir/half2_pruned_list.txt"

# 1. Per-chunk: drop suspects and re-max-lit
for ml in $(ls "$map_dir"/map_list_*.txt 2>/dev/null | grep -E 'map_list_[0-9]+_[0-9]+\.txt$' | sort -t_ -k3 -n); do
  be=$(echo "$ml" | sed -E 's#.*map_list_([0-9]+)_([0-9]+)\.txt#\1#')
  en=$(echo "$ml" | sed -E 's#.*map_list_([0-9]+)_([0-9]+)\.txt#\2#')
  clean="$map_dir/map_list_${be}_${en}_pruned.txt"
  grep -vF -f "$rm_ids" "$ml" > "$clean" || true
  n0=$(wc -l < "$ml")
  n1=$(wc -l < "$clean")
  out="$map_dir/max_mosaic_${be}_${en}_pruned.tif"
  echo "Chunk ${be}_${en}: $n0 -> $n1 maps -> $out"
  dem_mosaic --max --threads "$th" --dem-list "$clean" -o "$out"
  if [ "$be" -lt "$split_idx" ]; then
    echo "$out" >> "$map_dir/half1_pruned_list.txt"
  else
    echo "$out" >> "$map_dir/half2_pruned_list.txt"
  fi
done

# 2. Two illumination halves from pruned chunks
echo "Building half1 pruned max mosaic..."
dem_mosaic --max --threads "$th" --dem-list "$map_dir/half1_pruned_list.txt" -o "$map_dir/half1_pruned_max_mosaic.tif"

echo "Building half2 pruned max mosaic..."
dem_mosaic --max --threads "$th" --dem-list "$map_dir/half2_pruned_list.txt" -o "$map_dir/half2_pruned_max_mosaic.tif"

# 3. Grand max-lit of the two halves
printf '%s/half1_pruned_max_mosaic.tif\n%s/half2_pruned_max_mosaic.tif\n' "$map_dir" "$map_dir" > "$map_dir/halves_pruned_list.txt"
dem_mosaic --max --threads "$th" --dem-list "$map_dir/halves_pruned_list.txt" -o "$map_dir/all_pruned_max_mosaic.tif"

echo "DONE: $map_dir/all_pruned_max_mosaic.tif successfully built."
