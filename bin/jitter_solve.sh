#!/bin/bash

if [ "$#" -lt 5 ]; then 
    echo Usage: $0 inDir cleanMatchDir outDir dem currDir
fi

inDir=$1; shift
cleanMatchDir=$1; shift
outDir=$1; shift
dem=$1; shift
currDir=$1; shift
cd $currDir

out=output_${outDir}.txt
rm -fv $out
echo Writing: $out

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022 # make files readable by others

if [ "$PBS_NODEFILE" = "" ]; then
    # To run locally
    PBS_NODEFILE=$(uname -n).txt
    echo $(uname -n) > $PBS_NODEFILE
fi
echo Head node: $(uname -n) >> $out
echo Machines: $(cat ${PBS_NODEFILE}) >> $out

/usr/bin/time -f                                   \
   "Elapsed=%E memory=%M (kb)"                     \
   jitter_solve                                    \
   --threads $(nproc)                              \
   --image-list ${inDir}/run-image_list.txt        \
   --camera-list ${inDir}/run-camera_list.txt      \
   --clean-match-files-prefix ${cleanMatchDir}/run \
   --num-lines-per-position 500                    \
   --num-lines-per-orientation 250                 \
   --max-pairwise-matches 20000                    \
   --min-matches 1                                 \
   --min-triangulation-angle 1e-10                 \
   --num-iterations 50                             \
   --num-passes 2                                  \
   --max-initial-reprojection-error 50             \
   --overlap-limit 5000                            \
   --parameter-tolerance 1e-12                     \
   --heights-from-dem ${dem}                       \
   --heights-from-dem-uncertainty 10               \
   --anchor-dem ${dem}                             \
   --num-anchor-points-per-tile 50                 \
   --num-anchor-points-extra-lines 2000            \
   --anchor-weight 0.03                            \
   --mapproj-dem ${dem}                            \
   -o $outDir/run                                  \
    >> $out 2>&1

