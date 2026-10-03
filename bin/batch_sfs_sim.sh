#!/bin/bash
# Resolve sibling scripts relative to this one (installed bin dir).
binDir="$(cd "$(dirname "$0")" && pwd)"
#
# Run sfs_sim_align.sh over a range of imageList entries, xargs-parallel,
# with optional pre-existing-mapproj reuse.
#
# Usage:
#   batch_sfs_sim.sh imageList beg end sfsDem imgDir baDir simDir currDir \
#                    [mapList] [procs]
#
#   imageList   file, one image per line; id extracted as M<digits>[LR]E
#   beg, end    line range of imageList to process
#   sfsDem      DEM for mapproject + sim
#   imgDir      dir holding <id>.cub (glob *${id}*.cub)
#   baDir       dir holding cameras (glob *${id}*.json)
#   simDir      output dir for per-image sim-align products
#   currDir     working dir (cd here first)
#   mapList     optional: paired with imageList (line N <-> line N). When
#               given, each image's existing mapproj is passed to
#               sfs_sim_align.sh so the per-image mapproject step is
#               skipped. Empty "" or omitted = no reuse (mapproject is
#               redone per image).
#   procs       optional: xargs concurrency on the allocated node
#               (default 8). Mons precedent says 8 is safe on bro_ele.
#
# Env vars (pass-through to sfs_sim_align.sh):
#   ALIGN_THRESH      e.g. 1e9 for verify-only mode - exit after
#                     image_align with no GCP / BA / re-mapproject step.
#   EXPOSURES_PREFIX  REQUIRED. Path prefix such that
#                     <prefix>-exposures.txt is the file produced by
#                     $binDir/sfs_exposures.sh (or equivalent).
#                     Without exposures the per-image sfs sim renders
#                     blank for darker images and image_align finds no
#                     IPs. sfs_sim_align.sh errors out if unset.
#   SHADOW_THRESHOLD  passed to sfs as --shadow-threshold. Default 0.005
#                     (matches sfs_exposures.sh and parallel_sfs.sh).
#                     sfs's own default is -1 (off), which makes the
#                     per-image exposure init skip mostly-shadow images.
#
# INTERFACE CHANGED 2026-04-20 (breaking):
#   - imageList moved from position 3 -> position 1
#   - optional mapList (pos 9) and procs (pos 10) added at the end
#   - inner loop is now xargs-parallel (was serial for-loop); this turns
#     a fully-utilized bro_ele allocation from 1-cpu into ~28-cpu and
#     reduces SBU cost per image by ~8x
#   - each image now gets its own subdir under simDir
#     (simDir/<id>/...) instead of a flat layout with id-prefixed
#     filenames. Concurrent xargs workers are fully isolated - no
#     path can collide. Downstream aggregation (collecting cams,
#     gcps, stats, residuals into flat dirs) is left to the caller
#     as an offline post-processing step.
# See the README post-SfS registration section for a worked invocation.

if [ "$#" -lt 8 ]; then
    echo "Usage: $0 imageList beg end sfsDem imgDir baDir simDir currDir [mapList] [procs]"
    exit 1
fi

imageList=$1
beg=$2
end=$3
sfsDem=$4
imgDir=$5
baDir=$6
simDir=$7
currDir=$8
mapList=$9
procs=${10}
if [ -z "$procs" ]; then
    procs=8
fi

cd $currDir
umask 022

export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH

echo "imageList=$imageList"
echo "beg=$beg end=$end"
echo "sfsDem=$sfsDem"
echo "imgDir=$imgDir"
echo "baDir=$baDir"
echo "simDir=$simDir"
echo "currDir=$currDir"
if [ -z "$mapList" ]; then
    echo "mapList=(none; mapproject redone per image)"
else
    echo "mapList=$mapList"
fi
echo "procs=$procs"
if [ -z "$ALIGN_THRESH" ]; then
    echo "ALIGN_THRESH=(unset; full sim-align pipeline)"
else
    echo "ALIGN_THRESH=$ALIGN_THRESH"
fi

# Sanity: imageList and mapList must be paired line-by-line.
if [ -n "$mapList" ]; then
    nImg=$(wc -l < "$imageList")
    nMap=$(wc -l < "$mapList")
    if [ "$nImg" != "$nMap" ]; then
        echo "ERROR: imageList ($imageList, $nImg lines) and mapList ($mapList, $nMap lines) must have the same line count."
        exit 1
    fi
fi

out=output_batch_sfs_sim_${beg}_to_${end}.txt
echo "Writing: $out"
/bin/rm -fv $out
mkdir -p "$simDir"

# Build a tmp job file: one line per image, TAB-separated "id\texistingMap".
# When mapList is empty the second column is empty for every row.
jobs=$(mktemp)
imgChunk=$(cat "$imageList" | ~/bin/print_line_range.pl $beg $end)
if [ -z "$mapList" ]; then
    echo "$imgChunk" | perl -ne 'if (/(M\d+[LR]E)/) { print "$1\t\n"; }' > "$jobs"
else
    mapChunk=$(cat "$mapList" | ~/bin/print_line_range.pl $beg $end)
    paste <(echo "$imgChunk") <(echo "$mapChunk") | \
        perl -ne 'if (/(M\d+[LR]E).*?\t(.*)/) { print "$1\t$2\n"; }' > "$jobs"
fi

worker() {
    local line="$1"
    local id="${line%%$'\t'*}"
    local existingMap="${line#*$'\t'}"
    [ -z "$id" ] && return 0
    # Per-image subdir under simDir. Guarantees zero path collisions
    # between concurrent workers - everything for image $id lives
    # under ${simDir}/${id}/ (working files, ba-$id/ BA subdir, etc).
    local perImageSimDir="${simDir}/${id}"
    mkdir -p "$perImageSimDir"
    if [ -z "$existingMap" ]; then
        $binDir/sfs_sim_align.sh "$id" "$sfsDem" "$imgDir" "$baDir" \
            "$perImageSimDir" "$currDir" >> "$out" 2>&1
    else
        $binDir/sfs_sim_align.sh "$id" "$sfsDem" "$imgDir" "$baDir" \
            "$perImageSimDir" "$currDir" "$existingMap" >> "$out" 2>&1
    fi
}
export -f worker
export sfsDem imgDir baDir simDir currDir out ALIGN_THRESH EXPOSURES_PREFIX SHADOW_THRESHOLD

xargs -d '\n' -P $procs -I {} bash -c 'worker "$1"' _ {} < "$jobs"

/bin/rm -f "$jobs"
echo "Done. See $out"
