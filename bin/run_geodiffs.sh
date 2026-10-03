#!/bin/bash

# geodiff every matching DEM in a directory against a reference DEM, fanned out
# across the nodes of a PBS job. A worker: qsub with N nodes. De-pbs'd from
# run_geodiffs.pbs; it builds a command list and hands it to run_command_list.sh.
#
# Args:
#   refDem       reference DEM to difference against
#   inputDir     directory of DEMs
#   filePostfix  match files ending in this (e.g. DEM.tif)
#   currDir      work dir, pass as $(pwd)

if [ "$#" -lt 4 ]; then echo "Usage: $0 refDem inputDir filePostfix currDir"; exit 1; fi
refDem=$1; inputDir=$2; filePostfix=$3; currDir=$4
cd "$currDir" || exit 1
binDir="$(cd "$(dirname "$0")" && pwd)"

cmdFile=$(mktemp "$currDir/geodiff_cmds.XXXXXX")
for f in "$inputDir"/*"$filePostfix"; do
  [ -e "$f" ] || continue
  d=$(dirname "$f")
  echo "geodiff --absolute --threads 4 \"$f\" \"$refDem\" -o \"$d/run\"" >> "$cmdFile"
done
echo "built $(wc -l < "$cmdFile") geodiff commands"
exec "$binDir/run_command_list.sh" "$cmdFile" "$currDir"
