#!/bin/bash

# Run jitter_solve with a GCP file (from dem2gcp.sh), a reference DEM
# (--heights-from-dem + --mapproj-dem), anchor points, and reused clean match
# files. The per-line-pose analogue of bundle_adjust_dem_gcp.sh: it applies the
# SAME SfS->LOLA GCP pull as the bundle run, but with per-line flexibility. Use
# it as the parallel experiment to bundle_adjust_dem_gcp.sh - run both from the
# same start, judge on the GROUND (run-mapproj_match_offset_stats.txt, dh/dv vs
# the reference, geodiff), keep whichever is better behaved.
#
# Tuned for a GENTLE global re-registration (a ~few-meter SfS->LOLA shift), NOT
# high-frequency jitter: tight camera-position clamp, coarse position knots,
# orientation knots at 2000 lines, and anchor points kept fairly tight (strength
# set by --anchor-dem-uncertainty; --anchor-weight is deprecated), since the GCP
# do the real registration. See the jitter-solve and sfs-run-align skills.
#
# Usage:
#   jitter_gcp.sh <imageList> <cameraList> <dem> <gcpFile> <matchPrefix> \
#                 <outDir> <currDir>
#
#   imageList    list of .cub image paths (must match the GCP file's image refs)
#   cameraList   list of .json cameras, 1-to-1 with imageList
#   dem          reference (LOLA) DEM, used for heights-from-dem AND mapproj-dem
#                (and as the anchor DEM unless ANCHOR_DEM is set)
#   gcpFile      GCP file from dem2gcp.sh (passed positionally)
#   matchPrefix  prefix of clean match files to reuse (e.g. ba/run)
#   outDir       output dir (holds outDir/run-*)
#   currDir      working dir (cd here first)
#
# Env vars (defaults in parens) - the gentle-align settings:
#   NUM_LINES_POS      (15000)  --num-lines-per-position (coarse = stiff)
#   NUM_LINES_ORIENT   (2000)   --num-lines-per-orientation (NEVER below 1000,
#                               the smearing trap; finer knots track the shift
#                               better, kept stable by the many anchor points)
#   CAM_POS_UNC        (20,20)  --camera-position-uncertainty (meters; gentle,
#                               loose enough to let cameras follow the GCP pull)
#   DEM_UNC            (20)     --heights-from-dem-uncertainty
#   ANCHOR_DEM         ($dem)   --anchor-dem. The ref DEM is enough ONLY if no
#                               frame footprint (or loose orientation knot) reaches
#                               past the domain edge. With borderline/edge frames
#                               AND finer orientation knots, override with a genuine
#                               DEM padded well beyond the domain (+4 km/side here,
#                               10-40 km for long tracks). Anchor coverage is bounded
#                               by this DEM's extent, so an out-of-domain knot gets no
#                               anchors and smears; more anchors inside do not help.
#                               Grow only this DEM; keep heights/mapproj on the domain
#                               DEM.
#   ANCHOR_DEM_UNC     (20)     --anchor-dem-uncertainty (meters; GCP at sigma 1
#                               does the real registration, so anchors stay fairly
#                               tight at the ~20 m expected move - 50 was too loose)
#   NUM_ANCHOR         (5000)   --num-anchor-points (PER IMAGE)
#   ANCHOR_EXTRA_LINES (2000)   --num-anchor-points-extra-lines
#   MAX_PAIRWISE       (5000)   --max-pairwise-matches (watch Jacobian memory)
#   MAX_GCP_REPROJ_ERR (50)     --max-gcp-reproj-err
#   NUM_ITER           (75)     --num-iterations
#   NUM_PASSES         (2)      --num-passes
#   ROBUST_THRESHOLD   (2)      --robust-threshold (reprojection; NOT GCP)
#   GCP_ROBUST_THRESHOLD (-1=off) --gcp-robust-threshold (GCP position residual, sigma
#                               units; set ~20 for a 5-10 m shift to down-weight only outliers)
#   ORIENTATION_UNC    (0=off)  --orientation-uncertainty (per-pose guard; usually leave off)
#   Balance caps (ASP build 2026/10+, always passed):
#   MAX_NUM_TRI          (300000)  --max-num-tri-points (the master knob)
#   MAX_GCP_TO_TRI_RATIO (2.0)     --max-gcp-to-tri-points-ratio
#   MAX_ANCHOR_TO_TRI_RATIO (4.0)  --max-anchor-points-to-tri-points-ratio
#   The GCP and anchor caps are set relative to MAX_NUM_TRI via the ratios.
#   About 300000 suits a site up to ~15 by 15 km with a few hundred to ~1000 NAC
#   images. Increase it for larger sites or long tracks with many frames.

set -u

if [ "$#" -lt 7 ]; then
    echo "Usage: $0 <imageList> <cameraList> <dem> <gcpFile> <matchPrefix> <outDir> <currDir>"
    exit 1
fi

imageList=$1;   shift
cameraList=$1;  shift
dem=$1;         shift
gcpFile=$1;     shift
matchPrefix=$1; shift
outDir=$1;      shift
currDir=$1;     shift
cd $currDir

numLinesPos=${NUM_LINES_POS:-15000}
numLinesOrient=${NUM_LINES_ORIENT:-2000}
camPosUnc=${CAM_POS_UNC:-20,20}
demUnc=${DEM_UNC:-20}
anchorDem=${ANCHOR_DEM:-$dem}
anchorUnc=${ANCHOR_DEM_UNC:-20}
numAnchor=${NUM_ANCHOR:-5000}
anchorExtra=${ANCHOR_EXTRA_LINES:-2000}
maxPairwise=${MAX_PAIRWISE:-5000}
maxGcpErr=${MAX_GCP_REPROJ_ERR:-50}
numIter=${NUM_ITER:-75}
numPasses=${NUM_PASSES:-2}
robustThresh=${ROBUST_THRESHOLD:-2}
# Robust (Cauchy) loss on the GCP position residual, in gcp-sigma units (meters when
# the gcp sigma is 1). -1 = off (pure L2, default). Set it ABOVE the legitimate shift
# (about 20 for a 5-10 m SfS->LOLA shift) so real control keeps full pull and only true
# outliers soften.
gcpRobustThresh=${GCP_ROBUST_THRESHOLD:--1}
# Per-pose metric orientation guard (1 sigma, meters). 0 = off. Pins every orientation
# knot (incl yaw) regardless of anchor coverage. Usually leave OFF: dense anchors (below)
# constrain the knots, and the guard is an avoidable detour that can add a washboard.
orientUnc=${ORIENTATION_UNC:-0}

# Balance caps (ASP build 2026/10+, always passed). MAX_NUM_TRI is the master knob; the
# GCP and anchor caps are set relative to it via the ratios. SCALE BOTH tri and anchor
# counts with the site: too few and specific orientation knots fall in the solver null
# space and blow up (large yaw swings throwing the ground point tens of km) - the solution
# is good but poorly constrained, not wrong. A ~15 by 15 km / ~1000-image polar site runs
# well at the default 300000 tri x anchor-ratio 4 (about 1.2M anchors). Fewer tri or a
# smaller anchor ratio leaves knots starved. Raise MAX_NUM_TRI and the anchor ratio for larger sites or long tracks.
# The Ceres problem size (memory) is the control-point TOTAL = MAX_NUM_TRI x (1 + gcp-ratio +
# anchor-ratio); for a very large site keep that under the solver limit. MAX_PAIRWISE can stay
# generous (5000) since these caps, not the match count, bound what enters the solve.
maxNumTri=${MAX_NUM_TRI:-300000}
maxGcpToTriRatio=${MAX_GCP_TO_TRI_RATIO:-2.0}
maxAnchorToTriRatio=${MAX_ANCHOR_TO_TRI_RATIO:-4.0}

# Threads: default to the PBS-allocated core count ($NCPUS); the ASP/VW default
# (~8 via .vwrc) badly under-uses a full node. Fall back to all physical cores
# (nproc --all) off PBS. Bare nproc is avoided: under a PBS cpuset it honors the
# affinity mask and can return 1. Override with NUM_THREADS.
numThreads=${NUM_THREADS:-${NCPUS:-$(nproc --all)}}

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-${CONDA_PREFIX:-$HOME/miniconda3/envs/isis}}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=${ASP_BUILD:-StereoPipeline}   # override to test an alternate BinaryBuilder build
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022
ulimit -c 0

mkdir -p $outDir
out=output_${outDir##*/}.txt
echo "Writing log to: $out"
/bin/rm -fv $out

echo imageList=$imageList      >> $out
echo cameraList=$cameraList    >> $out
echo dem=$dem                  >> $out
echo gcpFile=$gcpFile          >> $out
echo matchPrefix=$matchPrefix  >> $out
echo outDir=$outDir            >> $out
echo numLinesPos=$numLinesPos numLinesOrient=$numLinesOrient camPosUnc=$camPosUnc >> $out
echo demUnc=$demUnc anchorDem=$anchorDem anchorUnc=$anchorUnc                     >> $out
echo numAnchor=$numAnchor anchorExtra=$anchorExtra maxPairwise=$maxPairwise       >> $out
echo maxNumTri=$maxNumTri maxGcpToTriRatio=$maxGcpToTriRatio maxAnchorToTriRatio=$maxAnchorToTriRatio >> $out
echo "numThreads=$numThreads"  >> $out

/usr/bin/time -f                                                 \
    "Elapsed=%E memory=%M (kb)"                                  \
    jitter_solve                                                 \
    --threads $numThreads                                        \
    --image-list $imageList                                      \
    --camera-list $cameraList                                    \
    $gcpFile                                                     \
    --clean-match-files-prefix $matchPrefix                      \
    --num-lines-per-position $numLinesPos                        \
    --num-lines-per-orientation $numLinesOrient                  \
    --camera-position-uncertainty $camPosUnc                     \
    --max-pairwise-matches $maxPairwise                          \
    --heights-from-dem $dem                                      \
    --heights-from-dem-uncertainty $demUnc                       \
    --anchor-dem $anchorDem                                      \
    --anchor-dem-uncertainty $anchorUnc                          \
    --num-anchor-points $numAnchor                               \
    --num-anchor-points-extra-lines $anchorExtra                 \
    --mapproj-dem $dem                                           \
    --max-gcp-reproj-err $maxGcpErr                              \
    --max-num-tri-points $maxNumTri                              \
    --max-gcp-to-tri-points-ratio $maxGcpToTriRatio              \
    --max-anchor-points-to-tri-points-ratio $maxAnchorToTriRatio \
    --robust-threshold $robustThresh                             \
    --gcp-robust-threshold $gcpRobustThresh                      \
    --orientation-uncertainty $orientUnc                         \
    --min-triangulation-angle 1e-10                              \
    --forced-triangulation-distance 100000                       \
    --max-initial-reprojection-error 50                          \
    --num-iterations $numIter                                    \
    --num-passes $numPasses                                      \
    --parameter-tolerance 1e-20                                  \
    -o $outDir/run                                               \
    >> $out 2>&1
