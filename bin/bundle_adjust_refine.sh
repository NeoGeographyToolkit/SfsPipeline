#!/bin/bash

# Bundle adjustment refinement that reuses already-harvested interest point
# matches. ONE script covers the whole fixed -> free -> heights-from-dem
# refinement chain; the two optional constraints are turned on via env vars:
#
#   FIXED_LIST       file: subset of imageList whose cameras are held fixed
#                    (the registered anchors). Unset -> nothing fixed.
#   REF_DEM          reference DEM: adds --heights-from-dem and --mapproj-dem.
#                    Unset -> no terrain constraint.
#   DEM_UNCERTAINTY  --heights-from-dem-uncertainty in meters (default 20,
#                    per sfs_usage.rst; use larger, e.g. 100, if the cameras
#                    are believed far from the reference terrain, smaller,
#                    e.g. 10, to trust the DEM more). Used only with REF_DEM.
#                    Past runs tried both 20 and 10 with little practical
#                    difference, so 20 is the hardcoded default. It is worth
#                    reconsidering when moving to a wildly different reference
#                    DEM, where how much to trust the terrain matters more.
#   THREADS          bundle_adjust threads (default 20).
#   USE_CLEAN        if set, reuse matchPrefix's CLEAN matches
#                    (--clean-match-files-prefix) instead of the raw ones. Set it
#                    for stages 2 and 3 pointing matchPrefix at stage 1's output
#                    (ba_fix/run): those clean matches were filtered against a
#                    real registered solve. Leave UNSET for stage 1 (raw harvest).
#
# Flags follow the documented registration-refinement command in the ASP manual
# (sfs_usage.rst, "Registration refinement"): matches are reused with
# --skip-matching so they are never recomputed and --camera-weight 0 lets the
# cameras move. NOT --save-intermediate-cameras: it rewrites the FULL camera set
# every iteration (~213 s/save for ~1000 CSM linescan cameras), which dominated
# runtime and nearly blew the walltime; only the final cameras are needed.
#
# So the three refinement stages are the same script with different env:
#   1. fixed : FIXED_LIST=<anchors>   anchor cameras hold the frame
#   2. free  : (no env)               refine all cameras, no constraint
#   3. dem   : REF_DEM=<dem>          tie the result to the terrain
#
# Matches are reused from matchPrefix: by default the RAW matches
# (--match-files-prefix), or the CLEAN matches (--clean-match-files-prefix) when
# USE_CLEAN is set. NEVER reuse the clean matches from a 0-iteration harvest:
# those were outlier-filtered against un-optimized (drifted) cameras and are
# over-culled. Stage 1 uses the raw harvest; stages 2 and 3 may set USE_CLEAN and
# point matchPrefix at stage 1's output, whose clean matches came from a real
# registered solve.
#
# imageList and camList must be in exact 1-to-1 correspondence: line N of
# camList is the camera for line N of imageList. For stage 1 assemble them
# offline, with the anchor images pointing at their registered (USGS) .json
# rather than the vanilla one. For stages 2 and 3 pass the previous stage's
# outDir/run-image_list.txt and outDir/run-camera_list.txt, which already point
# at the adjusted cameras.
#
# Args:
#   imageList    list of image (cub) paths
#   camList      list of camera (json) paths, 1-to-1 with imageList
#   matchPrefix  prefix of the reused matches (e.g. ba/run)
#   outDir       BA output dir (writes outDir/run-*)
#   currDir      working dir to cd into

if [ "$#" -lt 5 ]; then
    echo "Usage: $0 imageList camList matchPrefix outDir currDir"
    echo "  env: FIXED_LIST=<file> REF_DEM=<dem> DEM_UNCERTAINTY=<m>"
    exit 1
fi
imageList=$1; shift
camList=$1; shift
matchPrefix=$1; shift
outDir=$1; shift
currDir=$1; shift
cd $currDir

fixedList=${FIXED_LIST:-}
refDem=${REF_DEM:-}
demUnc=${DEM_UNCERTAINTY:-20}
numThreads=${THREADS:-20}
useClean=${USE_CLEAN:-}

echo imageList=$imageList
echo camList=$camList
echo matchPrefix=$matchPrefix
echo outDir=$outDir
echo currDir=$currDir
echo fixedList=$fixedList
echo refDem=$refDem

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022    # make outputs readable by others
ulimit -c 0  # no core dumps

out=output_$(basename $outDir).txt
rm -fv $out
echo Writing: $out

if [ "$PBS_NODEFILE" = "" ]; then
    # To run locally
    PBS_NODEFILE=$(uname -n).txt
    echo $(uname -n) > $PBS_NODEFILE
fi
echo Head node: $(uname -n) >> $out
echo Machines: $(cat ${PBS_NODEFILE}) >> $out

# Optional constraints, added only when their env var is set.
opts=""
if [ -n "$fixedList" ]; then
    opts="$opts --fixed-image-list $fixedList"
fi
if [ -n "$refDem" ]; then
    opts="$opts --heights-from-dem $refDem --heights-from-dem-uncertainty $demUnc --mapproj-dem $refDem"
fi

# Reuse matches from matchPrefix. Default reads the RAW matches; USE_CLEAN reads
# the CLEAN matches from that prefix instead (the two flags are mutually
# exclusive). Point a USE_CLEAN run at a real prior solve (e.g. ba_fix/run),
# whose clean matches were filtered against optimized cameras, NEVER a
# num-iterations-0 harvest (those are over-culled).
if [ -n "$useClean" ]; then
    matchOpt="--clean-match-files-prefix $matchPrefix"
else
    matchOpt="--match-files-prefix $matchPrefix"
fi

/usr/bin/time -f                           \
    "Elapsed=%E memory=%M (kb)"            \
    bundle_adjust                          \
    --image-list $imageList                \
    --camera-list $camList                 \
    $matchOpt                              \
    --skip-matching                        \
    --datum D_MOON                         \
    --max-pairwise-matches 2000            \
    --match-first-to-last                  \
    --min-matches 1                        \
    --min-triangulation-angle 1e-10        \
    --forced-triangulation-distance 100000 \
    --num-iterations 100                   \
    --num-passes 2                         \
    --camera-weight 0                      \
    --remove-outliers-params               \
    "75.0 3.0 100 100"                     \
    --parameter-tolerance 1e-20            \
    --threads $numThreads                  \
    $opts                                  \
    -o $outDir/run                         \
    >> $out 2>&1
