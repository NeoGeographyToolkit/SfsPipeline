#!/bin/bash

# point2dem on a stereo point cloud (a run-PC.tif). A single-node worker; qsub
# it. Converted from the PBS run_point2dem to the worker conventions.
#
# Args:
#   src       the point cloud (PC.tif)
#   currDir   work dir to cd into, pass as $(pwd)
# Env:
#   SRS       target CRS (default IAU_2015:30135)
#   MPP       output resolution in meters (default 1.0)
#   THREADS   point2dem threads (default: all cores, nproc)

if [ "$#" -lt 2 ]; then echo "Usage: $0 src currDir"; exit 1; fi
src=$1; currDir=$2
cd "$currDir" || exit 1

export ASPROOT=${ASPROOT:-$HOME/projects/BinaryBuilder/StereoPipeline}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
export PATH=$ASPROOT/bin:$ISISROOT/bin:$PATH
umask 022
ulimit -c 0

srs=${SRS:-IAU_2015:30135}
mpp=${MPP:-1.0}
threads=${THREADS:-${NCPUS:-$(nproc --all)}}

out=output_$(basename "${src%.tif}").point2dem.txt
echo "point2dem --t_srs $srs --tr $mpp $src (log $out)"
point2dem --t_srs "$srs" --tr "$mpp" --threads "$threads" "$src" >> "$out" 2>&1
