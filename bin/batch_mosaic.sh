#!/bin/bash

# Build the full and pruned max-lit for a jitter run on a COMPUTE NODE (via qsub),
# never on the head node. Running several dem_mosaic jobs on a pfe head node, even
# at --threads 1, reads as a multi-process load and gets reaped with a policy-
# violation email, so max-lit assembly belongs on a compute node.
#
# Full   = dem_mosaic --max over every per-image mapprojected tif (includes any
#          recovered images). Pruned = the same minus the wild cameras (p95 ground
#          smear > WILD_P95 m, default 50, from the run's run-mapproj_match_offset_stats.txt).
# After each mosaic it checks VALID_PERCENT and FAILS if the output is all-nodata,
# so a junk max-lit can never be silently produced.
#
# This script is the compute-node worker. Submit it, do NOT run it on the head node:
#   /PBS/bin/qsub -q normal -m n -r y -N mosaic -l walltime=1:00:00 -W group_list=<alloc> \
#     -j oe -S /bin/bash -l select=1:ncpus=28:model=bro_ele -- \
#     /path/to/SfsPipeline/bin/batch_mosaic.sh <run> <workDir>
#
# Usage (on the compute node): batch_mosaic.sh <run> <workDir>

set -u
run=$1
wd=$2
cd "$wd"

# Set up the environment (ASPROOT, ISISROOT, ISISDATA from your .bashrc)
binDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$binDir/sfs_env.sh" || exit 1
nt=${NCPUS:-28}
wildP95=${WILD_P95:-50}
stats=jitter_${run}/run-mapproj_match_offset_stats.txt

ls map_${run}/*.cal.echo.map.tr1.tif | grep -vE "_sub" > lists/mosaic_full_${run}.txt
awk -v t="$wildP95" 'NR>2 && $6>t {print $1}' "$stats" \
  | sed 's|.*/||; s|\.cal\.echo\.cub||' > lists/wild_${run}.txt
if [ -s lists/wild_${run}.txt ]; then
  grep -vFf lists/wild_${run}.txt lists/mosaic_full_${run}.txt > lists/mosaic_pruned_${run}.txt
else
  cp lists/mosaic_full_${run}.txt lists/mosaic_pruned_${run}.txt
fi
echo "$run: full $(wc -l < lists/mosaic_full_${run}.txt) imgs, pruned $(wc -l < lists/mosaic_pruned_${run}.txt) (dropped $(wc -l < lists/wild_${run}.txt) wild)"

build() {
  out=$1; lst=$2
  dem_mosaic --max --threads "$nt" --dem-list "$lst" -o "$out"
  vp=$(gdalinfo -stats "$out" 2>/dev/null | grep -oE "VALID_PERCENT=[0-9.]+" | head -1 | cut -d= -f2)
  echo "$out VALID_PERCENT=${vp:-none}"
  if [ -z "$vp" ] || [ "${vp%%.*}" -eq 0 ] 2>/dev/null; then
    echo "ERROR: $out is all nodata - not a usable max-lit"; exit 1
  fi
}

build maxlit_primary_new_${run}.tif lists/mosaic_full_${run}.txt
build maxlit_pruned_${run}.tif      lists/mosaic_pruned_${run}.txt
echo "$run DONE: both max-lits built and verified non-empty"
