#!/bin/bash

# Run bundle_adjust with: a reference DEM (heights-from-dem + mapproj-dem),
# a GCP file, an existing prefix of clean match files (no rematching), and
# pairwise images/cameras supplied via lists.
#
# Use case: shift an existing camera set into the LOLA frame using GCPs that
# have been transformed from the SfS frame to the LOLA frame by trans_gcp.sh,
# while reusing the match files from the prior bundle adjustment.
# --heights-from-dem and --mapproj-dem are both the LOLA DEM.
# The --mapproj-dem option enables per-image ground-offset residuals
# in bundle_adjust output (run-mapproj_match_offset_*).
#
# Usage:
#   bundle_adjust_dem_gcp.sh <imageList> <cameraList> <dem> <gcpFile> \
#                            <matchPrefix> <outDir> <currDir>
#
#   imageList     list of image (cub) paths. Paths must match what the
#                 GCP file s image observations reference, so BA can link
#                 a GCP row to an image in this list.
#   cameraList    list of camera files paired with imageList.
#   dem           DEM for both --heights-from-dem and --mapproj-dem.
#                 Use the same DEM the GCPs are in (typically the
#                 LOLA reference DEM the disparity transform mapped to).
#   gcpFile       GCP file produced by trans_gcp.sh.
#   matchPrefix   prefix for *-clean.match files from the previous BA
#                 (e.g., ba2s_ref/ba2s_ref).
#   outDir        BA output dir (will hold outDir/run-* outputs).
#   currDir       working dir (cd here first).
#
# Optional env vars:
#   DEM_UNCERTAINTY        --heights-from-dem-uncertainty meters
#                          (default 25.0; loose enough to let GCPs pull
#                          the cameras ~10 m or so without DEM dominating).
#   GCP_SIGMA              bundle_adjust does not accept a --gcp-sigma
#                          override. The sigmas baked in the .gcp file
#                          (columns 5,6,7) are authoritative. Set GCP_SIGMA
#                          at GCP-file creation time (dem2gcp.sh /
#                          trans_gcp.sh) instead.
#   MAX_PAIRWISE_MATCHES   --max-pairwise-matches (default 6000).
#   MAX_GCP_REPROJ_ERR     --max-gcp-reproj-err pixels (default 50).
#                          Drops GCPs whose reprojection residual is
#                          larger than this. Catches transformed GCPs
#                          that landed in disparity-blow-up regions.
#                          Loose at 50 - removes only obvious outliers.
#   CAM_POS_UNC            --camera-position-uncertainty "hor,vert" meters (1 sigma)
#                          for ALL cameras. Only added when set. Use a LOOSE value
#                          (e.g. 50,50) for a gentle re-registration: large enough
#                          not to block the intended ~meters ground move, small
#                          enough to stop weak cameras from flying off km-scale.
#                          Unset = no position constraint (cameras fully free).

set -u

if [ "$#" -lt 7 ]; then
    echo "Usage: $0 <imageList> <cameraList> <dem> <gcpFile> \\"
    echo "  <matchPrefix> <outDir> <currDir>"
    exit 1
fi

imageList=$1; shift
cameraList=$1; shift
dem=$1; shift
gcpFile=$1; shift
matchPrefix=$1; shift
outDir=$1; shift
currDir=$1; shift
cd $currDir

demUnc=${DEM_UNCERTAINTY:-25.0}
maxPairwise=${MAX_PAIRWISE_MATCHES:-6000}
maxGcpErr=${MAX_GCP_REPROJ_ERR:-50}
# Optional cap on GCP count relative to tri points (ASP build 2026/10+). Only added
# to the command when set, so the script still runs on builds that lack the flag.
ratioOpt=""
if [ "${MAX_GCP_TO_TRI_RATIO:-}" != "" ]; then
  ratioOpt="--max-gcp-to-tri-points-ratio ${MAX_GCP_TO_TRI_RATIO}"
fi
# Loose camera-position clamp (all cameras), default 20,20 meters (hor,vert). It keeps weak
# cameras from flying off while the GCPs move the block toward the reference. Override with
# CAM_POS_UNC, or set it to "none" to disable the clamp entirely. Note the comma in the
# value breaks a qsub -v list, so set it through the environment, not -v.
CAM_POS_UNC=${CAM_POS_UNC:-"20,20"}
camPosOpt=""
if [ "${CAM_POS_UNC}" != "" ] && [ "${CAM_POS_UNC}" != "none" ]; then
  camPosOpt="--camera-position-uncertainty ${CAM_POS_UNC}"
fi

# Optional robust (Cauchy) loss on the GCP position residual. The threshold acts on the
# residual ALREADY NORMALIZED by the per-GCP sigma (columns 5,6,7 of the GCP file), so its
# units are sigma-multiples, i.e. meters divided by the gcp sigma. Default -1 = off (pure
# L2, GCP treated as exact). Set it ABOVE the normalized legitimate shift so good control
# keeps full pull and only gross outliers are softened. Example: a 5 m expected shift at
# gcp sigma 0.25 normalizes to 5/0.25 = 20, so use 40 (knee at ~10 m ground offset, 2x the
# shift) to leave the real move untouched and down-weight only blunders.
GCP_ROBUST_THRESHOLD=${GCP_ROBUST_THRESHOLD:--1}
gcpRobustOpt=""
if [ "${GCP_ROBUST_THRESHOLD}" != "" ] && [ "${GCP_ROBUST_THRESHOLD}" != "-1" ]; then
  gcpRobustOpt="--gcp-robust-threshold ${GCP_ROBUST_THRESHOLD}"
fi

# Threads: default to ALL cores of the node (nproc). The ASP/VW default (~8 via
# .vwrc) badly under-uses a full node. Override with NUM_THREADS.
numThreads=${NUM_THREADS:-${NCPUS:-$(nproc --all)}}

echo imageList=$imageList
echo cameraList=$cameraList
echo dem=$dem
echo gcpFile=$gcpFile
echo matchPrefix=$matchPrefix
echo outDir=$outDir
echo currDir=$currDir
echo demUnc=$demUnc
echo maxPairwise=$maxPairwise
echo maxGcpErr=$maxGcpErr
echo ratioOpt=$ratioOpt
echo camPosOpt=$camPosOpt
echo gcpRobustOpt=$gcpRobustOpt
echo numThreads=$numThreads

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-${CONDA_PREFIX:-$HOME/miniconda3/envs/isis}}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022

mkdir -p $outDir
out=output_${outDir##*/}.txt
echo "Writing log to: $out"
/bin/rm -fv $out

if [ "$PBS_NODEFILE" = "" ]; then
    PBS_NODEFILE=$(uname -n).txt
    echo $(uname -n) > $PBS_NODEFILE
fi
echo "Head node: $(uname -n)" >> $out
echo "Machines:  $(cat ${PBS_NODEFILE})" >> $out

/usr/bin/time -f                            \
    "Elapsed=%E memory=%M (kb)"             \
    bundle_adjust                           \
    --threads $numThreads                   \
    --image-list $imageList                 \
    --camera-list $cameraList               \
    $gcpFile                                \
    --clean-match-files-prefix $matchPrefix \
    --max-pairwise-matches $maxPairwise     \
    --datum D_MOON                          \
    --heights-from-dem $dem                 \
    --heights-from-dem-uncertainty $demUnc  \
    --mapproj-dem $dem                      \
    --max-gcp-reproj-err $maxGcpErr         \
    $ratioOpt                               \
    $camPosOpt                              \
    $gcpRobustOpt                           \
    --num-iterations 100                    \
    --num-passes 2                          \
    --min-matches 1                         \
    --min-triangulation-angle 1e-10         \
    --forced-triangulation-distance 100000  \
    --remove-outliers-params                \
    "75.0 3.0 100 100"                      \
    --parameter-tolerance 1e-12             \
    -o $outDir/run                          \
    >> $out 2>&1
