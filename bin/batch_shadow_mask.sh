#!/bin/bash

# Run shadow_mask.sh over every matching mapprojected image in a directory,
# fanned out across the nodes of a PBS job. A worker: qsub with N nodes.
# De-pbs'd from shadow_mask.pbs; builds a command list for run_command_list.sh.
#
# Args:
#   inputDir     directory of mapprojected images
#   tifPostfix   match files ending in this (e.g. map.noba.tif)
#   shadowThresh lit-vs-shadow threshold (e.g. 0.002)
#   currDir      work dir, pass as $(pwd)

if [ "$#" -lt 4 ]; then echo "Usage: $0 inputDir tifPostfix shadowThresh currDir"; exit 1; fi
inputDir=$1; tifPostfix=$2; shadowThresh=$3; currDir=$4
cd "$currDir" || exit 1
binDir="$(cd "$(dirname "$0")" && pwd)"

cmdFile=$(mktemp "$currDir/shadow_mask_cmds.XXXXXX")
for f in "$inputDir"/*"$tifPostfix"; do
  [ -e "$f" ] || continue
  echo "$binDir/shadow_mask.sh \"$f\" $shadowThresh" >> "$cmdFile"
done
echo "built $(wc -l < "$cmdFile") shadow_mask commands"
exec "$binDir/run_command_list.sh" "$cmdFile" "$currDir"
