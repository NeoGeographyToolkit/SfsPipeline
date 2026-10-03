#!/bin/bash

# Cull mapprojected images that do not contribute lit pixels to the area of
# interest, preserving the input order (which is expected to be by solar
# azimuth, per sfs_usage.rst image selection).
#
# For each mapprojected tif in inList, read its maximum pixel value with
# gdalinfo -stats. Keep the file only if it exists and its maximum is at or
# above the threshold. Images that did not intersect the region produce no
# mapprojected file (mapproject skips out-of-range footprints), so they are
# absent from inList or fail the existence test. Images fully in shadow have a
# maximum near zero and are dropped. For calibrated LRO NAC the lit terrain is
# ~0.05 to 0.3 in reflectance, so a threshold of 0.005 cleanly separates lit
# from shadow (same value as the SfS shadow threshold).
#
# The kept paths are written to outList in the same order as inList. A sidecar
# log with the per-image maxima is written next to outList.

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 inList outList currDir [threshold]"
  echo "  inList    mapprojected tif paths, one per line, in azimuth order"
  echo "  outList   kept tif paths, same order"
  echo "  currDir   work dir to cd into"
  echo "  threshold minimum STATISTICS_MAXIMUM to keep (default 0.005)"
  exit 1
fi

inList=$1; shift
outList=$1; shift
currDir=$1; shift
threshold=${1:-0.005}
cd "$currDir"

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022 # make files readable by others
ulimit -c 0 # no core dumps

procs=${PROCS:-16} # parallel gdalinfo workers

echo "inList=$inList"
echo "outList=$outList"
echo "currDir=$currDir"
echo "threshold=$threshold"
echo "procs=$procs"

maxLog=output_$(basename "$outList" .txt)_max_vals.txt
/bin/rm -f "$maxLog"
echo "Writing per-image maxima to $maxLog"

# Emit "path max" for each existing file, in parallel. Missing files are skipped
# here and thus dropped. An all-nodata file yields no STATISTICS_MAXIMUM and is
# also dropped.
getMax() {
  f="$1"
  if [ ! -s "$f" ]; then return; fi
  m=$(gdalinfo -stats "$f" 2>/dev/null | grep STATISTICS_MAXIMUM | head -n 1 | perl -p -e "s#.*=##g")
  if [ -n "$m" ]; then echo "$f $m"; fi
}
export -f getMax

# Preserve inList order: number the lines, compute maxima in parallel, then sort
# back by the original line index before applying the threshold.
nl -ba -w1 -s' ' "$inList" \
  | xargs -P "$procs" -n2 bash -c 'idx=$1; f=$2; out=$(getMax "$f"); [ -n "$out" ] && echo "$idx $out"' _ \
  | sort -n -k1,1 > "$maxLog"

# Keep files whose max is at or above the threshold, dropping the index column.
awk -v t="$threshold" '$3 >= t {print $2}' "$maxLog" > "$outList"

nIn=$(wc -l < "$inList")
nKept=$(wc -l < "$outList")
echo "Kept $nKept of $nIn images (threshold $threshold)."
