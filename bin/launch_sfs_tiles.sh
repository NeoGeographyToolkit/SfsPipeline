#!/bin/bash
# Resolve sibling scripts relative to this one (installed bin dir).
binDir="$(cd "$(dirname "$0")" && pwd)"

# Generic per-tile SfS launcher. Submits one qsub per tile in $tileDir
# via parallel_sfs.sh. Node type (bro_ele), ncpus and walltime are
# queue (normal), walltime, and node count; takes the flags that
# actually vary between runs as args. Env vars (with defaults) for
# the less-frequently tuned knobs.
#
# Usage:
#   launch_sfs_tiles.sh <tileDir> <imageList> <baPrefix> \
#                       <exposuresFile> <sfsBaseDir> <estimError> \
#                       <currDir>
#
# Args:
#   tileDir        dir with tile-*.tif from tile_dem.py
#   imageList      images-per-line text file (ids or paths, same
#                  format parallel_sfs.sh expects)
#   baPrefix       prefix for camera glob (e.g. ba_final/run)
#   exposuresFile  precomputed exposures; copied into each tile's
#                  sfs dir as run-exposures.txt
#   sfsBaseDir     per-tile outputs go under $sfsBaseDir/clip<id>/
#   estimError     0 = regular SfS run; 1 = uncertainty pass
#                  (requires DEM = pre-run SfS blend, not LOLA)
#   currDir        working directory for the qsub
#
# Env var overrides (defaults in parens):
#   DEM_WEIGHT     (0.0025)
#   SHADOW_THRESH  (0.005)
#   NUM_CPU        (6)          per-node worker count (keep low for mem)
#   NUM_NODES      (4)
#   WALLTIME       (20:00:00)
#   QUEUE          (unset)      let PBS auto-route by walltime;
#                                set e.g. "devel" for rehearsal, or
#                                "long" when forcing a specific queue.
#                                With a 20h default WALLTIME, PBS
#                                routes to "long" automatically.
#   QSUB_BIN       (/PBS/bin/qsub)   qsub binary; on athfe use
#                                    /opt/pbs/bin/qsub.
#   MODEL          (bro_ele)         node model. tur_ath supported.
#   NCPUS          (28)              cpus per selected node;
#                                    256 for tur_ath.
#
# Env var pass-through (forwarded to the parallel_sfs.sh workers through qsub -V,
# which exports the whole submitting environment):
#   IMAGE_DIR / IMAGE_SUFFIX - where the cubs live (img/<id>.cal.echo.cub). These
#     are defaulted below (img / .cal.echo.cub) so they are always set. An UNSET
#     name in a qsub -v list makes PBS reject the whole job with "cannot send
#     environment with the job", silently - a banner, no job id, nothing in qstat.
#
# Example (regular run):
#   cd /path/to/your/project
#   launch_sfs_tiles.sh                        \
#     tiles lists/mapproj_final_selected.txt ba_final/run     \
#     lists/exposures.txt sfs_v1 0 $(pwd)
#
# Example (uncertainty pass, tiles from the produced SfS blend):
#   tile_dem.py sfs_v1/sfs_dem_blend.tif 4000 4000 tiles_sfs 200
#   launch_sfs_tiles.sh                        \
#     tiles_sfs lists/mapproj_final_selected.txt ba_final/run \
#     lists/exposures.txt sfs_unc 1 $(pwd)

set -u

if [ "$#" -lt 7 ]; then
    echo "Usage: $0 <tileDir> <imageList> <baPrefix> <exposuresFile> <sfsBaseDir> <estimError> <currDir>"
    exit 1
fi

tileDir=$1;       shift
imageList=$1;     shift
baPrefix=$1;      shift
exposuresFile=$1; shift
sfsBaseDir=$1;    shift
estimError=$1;    shift
currDir=$1;       shift

demWeight=${DEM_WEIGHT:-0.0025}
shadowThresh=${SHADOW_THRESH:-0.005}
numCpu=${NUM_CPU:-6}
numNodes=${NUM_NODES:-4}
walltime=${WALLTIME:-20:00:00}
queue=${QUEUE:-}   # empty -> let PBS auto-route by walltime
qsubBin=${QSUB_BIN:-/PBS/bin/qsub}
model=${MODEL:-bro_ele}
ncpus=${NCPUS:-28}

# Worker image-location vars forwarded to parallel_sfs.sh. Default and export them so
# they are ALWAYS set: an unset name in a qsub -v list makes PBS reject the whole job
# ("cannot send environment with the job") silently. -V (used below) forwards all set
# vars; defaulting these guarantees the worker finds the cubs at img/<id>.cal.echo.cub.
export IMAGE_DIR=${IMAGE_DIR:-img}
export IMAGE_SUFFIX=${IMAGE_SUFFIX:-.cal.echo.cub}

cd $currDir
umask 022

if [ ! -d "$tileDir" ]; then
    echo "ERROR: tile dir not found: $tileDir"
    exit 1
fi
if [ ! -f "$exposuresFile" ]; then
    echo "ERROR: exposures file not found: $exposuresFile"
    exit 1
fi
if [ -z "${groupName:-}" ]; then
    echo "ERROR: set groupName (the PBS allocation / group_list) before submitting"
    exit 1
fi

shopt -s nullglob
tiles=( $tileDir/tile-*.tif )
shopt -u nullglob
if [ ${#tiles[@]} -eq 0 ]; then
    echo "ERROR: no tile-*.tif files in $tileDir"
    exit 1
fi

echo "launch_sfs_tiles:"
echo "  tileDir       = $tileDir (${#tiles[@]} tiles)"
echo "  imageList     = $imageList"
echo "  baPrefix      = $baPrefix"
echo "  exposuresFile = $exposuresFile"
echo "  sfsBaseDir    = $sfsBaseDir"
echo "  estimError    = $estimError"
echo "  demWeight     = $demWeight"
echo "  shadowThresh  = $shadowThresh"
echo "  numCpu/node   = $numCpu"
echo "  nodes         = $numNodes ($model x $ncpus cpus)"
echo "  walltime      = $walltime"
echo "  queue         = ${queue:-(auto-route by walltime)}"
echo "  currDir       = $currDir"

for tile in "${tiles[@]}"; do
    id=$(echo "$tile" | perl -p -e "s#^.*?([0-9]+)\.tif\$#\$1#g")
    sfsDir=$sfsBaseDir/clip${id}
    sfsPrefix=$sfsDir/run
    mkdir -p $sfsDir
    cp -f $exposuresFile $sfsDir/run-exposures.txt
    qFlag=""
    if [ -n "$queue" ]; then qFlag="-q $queue"; fi
    jobid=$($qsubBin $qFlag -V -m n -r n -N sfs${id}           \
        -l walltime=$walltime -W group_list=$groupName         \
        -j oe -S /bin/bash                                     \
        -o $currDir/                                           \
        -l select=${numNodes}:ncpus=${ncpus}:model=${model} -- \
        $binDir/parallel_sfs.sh                                \
          $tile $numCpu $baPrefix $imageList $estimError       \
          $sfsPrefix $currDir $demWeight $shadowThresh)
    rc=$?
    # A failed qsub (bad queue, unset -v name, over-limit walltime) prints a banner to
    # stderr, returns non-zero, and emits NO job id. Abort loudly rather than march on
    # having silently queued nothing.
    if [ $rc -ne 0 ] || [ -z "$jobid" ]; then
        echo "ERROR: qsub failed for tile $tile (rc=$rc), job id empty - aborting." >&2
        echo "       see the qsub banner above for the reason." >&2
        exit 1
    fi
    echo "  submitted $jobid for $tile"
    sleep 2
done
