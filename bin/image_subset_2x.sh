#!/bin/bash
# Two-pass image_subset for 2x coverage.
#
# image_subset (ASP, :numref:`image_subset`) picks a minimal subset of overlapping
# georeferenced images that reproduces almost the full coverage, ranked by contribution.
# It has no --exclude, so to get a SECOND independent cover (redundancy / illumination
# diversity for SfS) we run it once (primary), remove those images from the input, and
# run it again on the remainder (extra). The union is the 2x cover.
#
# Optional t_projwin restricts coverage SCORING to a sub-box (e.g. one quadrant) so an
# image is judged only on how it covers that box. All inputs must share one projection.
#
# image_subset is slow (O(n^2 * output pixels)) and reads each image fully into memory:
# feed it LOW-RES sub images (see prepare_lowres.sh) and 50-150 images per call (split by
# quadrant and Sun azimuth first). Threshold: a pixel >= threshold counts as covered.
# 0.01 is the ASP default but is often too permissive (keeps nearly everything); try
# 0.05-0.1 to actually thin the set, and tune by clicking pixel values in stereo_gui.
#
# Usage: image_subset_2x.sh <lowresList> <outPrefix> <currDir> [threshold] [projwin]
#   projwin (optional): "xmin ymin xmax ymax" (unquoted 4 numbers passed to --t_projwin)
# Outputs (image path + contributing-pixel count per line, ranked):
#   <outPrefix>_primary.txt  <outPrefix>_extra.txt
# and the combined image-only union:
#   <outPrefix>_2x.txt
set -e
if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <lowresList> <outPrefix> <currDir> [threshold] [projwin]"
  exit 1
fi
inList=$1; shift
outPfx=$1; shift
currDir=$1; shift
thresh=${1:-0.01}; [ "$#" -ge 1 ] && shift || true
projwin=${1:-}
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

th=${THREADS:-20}
pwarg=""
[ -n "$projwin" ] && pwarg="--t_projwin $projwin"

n=$(wc -l < "$inList")
echo "image_subset_2x: $n input images, threshold=$thresh, projwin=[${projwin:-none}]"

# pass 1: primary minimal cover
image_subset --threads "$th" --threshold "$thresh" --image-list "$inList" $pwarg -o "${outPfx}_primary.txt"
np=$(wc -l < "${outPfx}_primary.txt")
echo "  primary: $np images"

# pass 2: remove primary, cover the remainder
awk '{print $1}' "${outPfx}_primary.txt" > "${outPfx}_primary_paths.txt"
grep -vF -f "${outPfx}_primary_paths.txt" "$inList" > "${outPfx}_remain.txt" || true
nr=$(wc -l < "${outPfx}_remain.txt")
if [ "$nr" -gt 0 ]; then
  image_subset --threads "$th" --threshold "$thresh" --image-list "${outPfx}_remain.txt" $pwarg -o "${outPfx}_extra.txt"
  ne=$(wc -l < "${outPfx}_extra.txt")
else
  : > "${outPfx}_extra.txt"; ne=0
fi
echo "  extra: $ne images ($nr remained)"

# union (image paths only)
cat "${outPfx}_primary_paths.txt" <(awk '{print $1}' "${outPfx}_extra.txt") > "${outPfx}_2x.txt"
echo "  2x union: $(wc -l < "${outPfx}_2x.txt") images -> ${outPfx}_2x.txt"
