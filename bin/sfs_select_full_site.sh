#!/bin/bash
# SfS INPUT SELECTION for a full site (non-quadrant decomposition).
# Groups mapprojected images by solar azimuth into balanced clusters, then runs
# two-pass image_subset (primary + extra = 2x cover) on each azimuth group.
#
# Implementation of sfs-image-selection workflow for small-to-moderate sites (<25 km):
#   1. Uses prepare_lowres.sh to select sub8 > sub4 > sub2 pyramids.
#   2. Parses solar azimuths from azimuth_table (output of sfs_query.sh).
#   3. Groups images into balanced azimuth bins.
#   4. Runs image_subset_2x.sh per azimuth group.
#   5. Produces primary, extra, and combined 2x image lists.
#
# Usage:
#   sfs_select_full_site.sh <map_list.txt> <azimuth_table.txt> <out_dir> <curr_dir> [threshold] [threads]

set -e
if [ "$#" -lt 4 ]; then
  echo "Usage: $0 <map_list.txt> <azimuth_table.txt> <out_dir> <curr_dir> [threshold] [threads]"
  exit 1
fi

map_list="$1"
az_file="$2"
out_dir="$3"
curr_dir="$4"
thresh="${5:-0.01}"
th="${6:-20}"

cd "$curr_dir"
mkdir -p "$out_dir"

tools_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
share=$HOME/projects/BinaryBuilder/$s/share
[ -d "$share/proj" ] && export GDAL_DATA=$share/gdal PROJ_DATA=$share/proj PROJ_LIB=$share/proj
umask 022
ulimit -c 0

# 1. Prepare low-res sub image list
echo "=== Step 1: Preparing low-res pyramid list ==="
lowres_list="$out_dir/lowres_maps.txt"
bash "$tools_dir/prepare_lowres.sh" "$map_list" "$lowres_list" "$curr_dir"

# 2. Map image ID -> azimuth (0-360)
declare -A id2az
while read -r p _s az0360 _e; do
  id=$(echo "$p" | perl -pe 's#^.*?(M\d+\wE|[A-Za-z0-9_]+).*#\1#')
  id2az[$id]=$az0360
done < "$az_file"

# 3. Associate low-res paths with azimuths
az_path_file="$out_dir/az_path.txt"
: > "$az_path_file"
while read -r lr; do
  id=$(echo "$lr" | perl -pe 's#^.*?(M\d+\wE|[A-Za-z0-9_]+).*#\1#')
  az=${id2az[$id]:-}
  [ -z "$az" ] && continue
  printf '%s\t%s\n' "$az" "$lr" >> "$az_path_file"
done < "$lowres_list"

echo "Total images with valid azimuths: $(wc -l < "$az_path_file")"

# 4. Decompose into azimuth groups (0-90, 90-180, 180-270, 270-360, splitting dense bins at medians)
python3 -c "
import sys, numpy as np

with open('$az_path_file') as f:
  lines = [l.strip().split('\t') for l in f if '\t' in l]

data = [(float(az), p) for az, p in lines]
data_low = [x for x in data if x[0] < 180.0]
data_mid = [x for x in data if 180.0 <= x[0] < 270.0]
data_high = [x for x in data if x[0] >= 270.0]

med_low = np.median([x[0] for x in data_low]) if len(data_low) > 1 else 90.0
med_high = np.median([x[0] for x in data_high]) if len(data_high) > 1 else 315.0

g0 = [x[1] for x in data_low if x[0] <= med_low]
g1 = [x[1] for x in data_low if x[0] > med_low]
g2 = [x[1] for x in data_mid]
g3 = [x[1] for x in data_high if x[0] <= med_high]
g4 = [x[1] for x in data_high if x[0] > med_high]

for idx, g in enumerate([g0, g1, g2, g3, g4]):
  with open(f'$out_dir/group_{idx}_lowres.txt', 'w') as out:
    for path in g:
      out.write(path + '\n')
  print(f'Group {idx}: {len(g)} images')
"

# 5. Run 2-pass image_subset per group
group_indices="0 1 2 3 4"
for g in $group_indices; do
  glist="$out_dir/group_${g}_lowres.txt"
  [ ! -s "$glist" ] && continue
  echo "=== Running 2-pass image_subset on Group $g ($(wc -l < "$glist") images) ==="
  bash "$tools_dir/image_subset_2x.sh" "$glist" "$out_dir/sel_group_${g}" "$curr_dir" "$thresh"
done

# 6. Aggregate primary, extra, and 2x covers across all groups
cat "$out_dir"/sel_group_*_primary.txt 2>/dev/null > "$out_dir/all_primary.txt" || true
cat "$out_dir"/sel_group_*_extra.txt 2>/dev/null > "$out_dir/all_extra.txt" || true
cat "$out_dir"/sel_group_*_2x.txt 2>/dev/null > "$out_dir/all_2x.txt" || true

echo "=== Selection Complete ==="
echo "Primary cover: $(wc -l < "$out_dir/all_primary.txt") images"
echo "Extra cover:   $(wc -l < "$out_dir/all_extra.txt") images"
echo "Total 2x union: $(wc -l < "$out_dir/all_2x.txt") images"
