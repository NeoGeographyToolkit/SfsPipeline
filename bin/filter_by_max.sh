#!/bin/bash

# Remove mapprojected images that do not contribute lit pixels to the area of
# interest, preserving the input order (which is expected to be by solar
# azimuth, per sfs_usage.rst image selection).
#
# For each mapprojected tif in inList, read its maximum pixel value and its
# valid-pixel percent with gdalinfo -stats. Keep the file only if it exists, its
# maximum is at or above the max threshold, and its valid percent is at or above
# the min-valid-percent threshold. Images that did not intersect the region
# produce no mapprojected file (mapproject skips out-of-range footprints), so
# they are absent from inList or fail the existence test. Images fully in shadow
# have a maximum near zero and are dropped. For calibrated LRO NAC the lit
# terrain is ~0.05 to 0.3 in reflectance, so a threshold of 0.005 cleanly
# separates lit from shadow (same value as the SfS shadow threshold).
#
# The valid-percent screen removes near-empty slivers. A mapprojected image whose
# footprint barely clips the DEM can pass the max threshold yet have so few valid
# pixels that bundle_adjust's statistics step (which subsamples toward a million
# pixels) finds no valid sample and fails the whole run. Dropping below 0.2
# percent valid stays well clear of that crash, and such tiny-overlap images are
# useless for matching anyway.
#
# The kept paths are written to outList in the same order as inList. A sidecar
# log with the per-image maxima and valid percents is written next to outList.

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 inList outList currDir [threshold] [minValidPercent]"
  echo "  inList          mapprojected tif paths, one per line, in azimuth order"
  echo "  outList         kept tif paths, same order"
  echo "  currDir         work dir to cd into"
  echo "  threshold       minimum STATISTICS_MAXIMUM to keep (default 0.005)"
  echo "  minValidPercent minimum STATISTICS_VALID_PERCENT to keep (default 0.2)"
  exit 1
fi

inList=$1; shift
outList=$1; shift
currDir=$1; shift
threshold=${1:-0.005}
minValidPercent=${2:-${MIN_VALID_PERCENT:-0.2}}
cd "$currDir"

# Set up the environment (ASPROOT, ISISROOT, ISISDATA from your .bashrc)
binDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$binDir/sfs_env.sh" || exit 1

procs=${PROCS:-16} # parallel gdalinfo workers

echo "inList=$inList"
echo "outList=$outList"
echo "currDir=$currDir"
echo "threshold=$threshold"
echo "minValidPercent=$minValidPercent"
echo "procs=$procs"

maxLog=output_$(basename "$outList" .txt)_max_vals.txt
/bin/rm -f "$maxLog"
echo "Writing per-image maxima and valid percents to $maxLog"

# Emit "path max validPercent" for each existing file, in parallel, from a single
# gdalinfo -stats call. Missing files are skipped here and thus dropped. An
# all-nodata file yields no STATISTICS_MAXIMUM and is also dropped. If gdalinfo
# does not report a valid percent, default it to 100 so the file is judged on the
# max threshold alone (non-regressive).
getMax() {
  f="$1"
  if [ ! -s "$f" ]; then return; fi
  info=$(gdalinfo -stats "$f" 2>/dev/null)
  m=$(echo "$info" | grep STATISTICS_MAXIMUM | head -n 1 | perl -p -e "s#.*=##g")
  vp=$(echo "$info" | grep STATISTICS_VALID_PERCENT | head -n 1 | perl -p -e "s#.*=##g")
  vp=${vp:-100}
  if [ -n "$m" ]; then echo "$f $m $vp"; fi
}
export -f getMax

# Preserve inList order: number the lines, compute maxima in parallel, then sort
# back by the original line index before applying the threshold.
nl -ba -w1 -s' ' "$inList" \
  | xargs -P "$procs" -n2 bash -c 'idx=$1; f=$2; out=$(getMax "$f"); [ -n "$out" ] && echo "$idx $out"' _ \
  | sort -n -k1,1 > "$maxLog"

# Keep files whose max is at or above the max threshold and whose valid percent is
# at or above the min, dropping the index column. awk parses scientific notation
# (e.g. a tiny valid percent like 2.5e-05), so the comparison is exact.
awk -v t="$threshold" -v v="$minValidPercent" \
  '$3 >= t && $4 >= v {print $2}' "$maxLog" > "$outList"

nIn=$(wc -l < "$inList")
nKept=$(wc -l < "$outList")
echo "Kept $nKept of $nIn images (max >= $threshold, valid-percent >= $minValidPercent)."
