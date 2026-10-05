#!/bin/bash

# STANDALONE DEM-to-DEM hillshade CORRELATOR - dh/dv only, NO alignment.
#
# This is the correlate-only counterpart to hillshade_correlator.sh (which also runs
# pc_align to emit an aligned DEM). Here we only gdaldem-hillshade both DEMs and run
# parallel_stereo in --correlator-mode, then emit the dx/dy disparity. Use this whenever
# you just want the horizontal dh/dv pattern between two DEMs (e.g. a SfS->LOLA shift, a
# sensitivity check); use hillshade_correlator.sh with DO_PC_ALIGN=1 when you also need the
# alignment transform. See the dem-comparison skill.
#
# Correlate HILLSHADES with asp_mgm, NOT asp_bm: hillshades are smooth/low-texture, so
# block matching (asp_bm) finds almost nothing (~0-12% valid), while SGM/MGM fills via
# global smoothness (~66-88%). asp_bm is for TEXTURED images (max-lit orthos -> correlator.sh).
#
# Usage: hillshade_corr.sh <leftDem> <rightDem> <stereoDir> <currDir> [maxSearch=20]
#   Output: <stereoDir>/run-F_b1_nodata.tif = dx , run-F_b2_nodata.tif = dy (meters on a 1 m grid).
# Env (defaults): STEREO_ALGO=asp_mgm  COST_MODE=3 (census, robust to illumination mismatch)
#   HILLSHADE_OPTS="-multidirectional -compute_edges"  NCPUS=28

set -e
leftDem=$1; rightDem=$2; stereoDir=$3; currDir=$4; maxSearch=${5:-20}
cd "$currDir"
umask 022
ulimit -c 0

export ASPROOT=${ASPROOT:-$HOME/projects/BinaryBuilder/StereoPipeline}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
export PATH=$ASPROOT/bin:$ISISROOT/bin:$PATH

N=${NCPUS:-28}
algo=${STEREO_ALGO:-asp_mgm}
costMode=${COST_MODE:-3}
hsOpts=${HILLSHADE_OPTS:--multidirectional -compute_edges}

mkdir -p "$stereoDir"
out=$stereoDir/output_corr.txt
exec > "$out" 2>&1
echo "hillshade_corr: left=$leftDem right=$rightDem algo=$algo costMode=$costMode hsOpts='$hsOpts' maxSearch=$maxSearch"

# gdaldem hillshades (fresh copies). gdaldem hillshade is pixel-based (no proj.db needed).
leftHill=${leftDem%.tif}_gdhill.tif
rightHill=${rightDem%.tif}_gdhill.tif
[ -f "$leftHill" ]  || gdaldem hillshade $hsOpts "$leftDem"  "$leftHill"
[ -f "$rightHill" ] || gdaldem hillshade $hsOpts "$rightDem" "$rightHill"

# Short alias for the corr-search half-window, to keep the option below compact.
s=$maxSearch
parallel_stereo \
  --correlator-mode \
  --stereo-algorithm $algo \
  --cost-mode $costMode \
  --corr-kernel 9 9 \
  --subpixel-mode 9 \
  --corr-search -$s -$s $s $s \
  --nodata-value 0 \
  --ip-per-image 40000 \
  --processes 8 \
  --threads 4 \
  --nodes-list "$PBS_NODEFILE" \
  "$leftHill" "$rightHill" \
  --num-matches-from-disparity 40000 \
  "$stereoDir/run"

for b in 1 2 3; do
  gdal_translate -b $b "$stereoDir/run-F.tif" "$stereoDir/run-F_b${b}.tif"
done
t=1e+6
for b in 1 2; do
  image_calc -c "(var_0 + $t)*var_1 - $t" --output-nodata-value -$t \
    "$stereoDir/run-F_b${b}.tif" "$stereoDir/run-F_b3.tif" \
    -o "$stereoDir/run-F_b${b}_nodata.tif"
done
echo "dx = $stereoDir/run-F_b1_nodata.tif ; dy = $stereoDir/run-F_b2_nodata.tif"
echo DONE
