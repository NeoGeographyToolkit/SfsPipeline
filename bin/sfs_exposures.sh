#!/bin/bash

# Compute exposures only with one process

if [ "$#" -lt 5 ]; then echo Usage imageList baPrefix dem sfsDir currDir; exit; fi

imageList=$1; shift
baPrefix=$1; shift
dem=$1; shift
sfsDir=$1; shift
currDir=$1; shift
cd $currDir

mkdir -p $sfsDir
out=$sfsDir/output_exposures.txt
echo Will write the output to $out
/bin/rm -f $out

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022 # make files readable by others

# Prepare the cameras. Use the inline
# json camera files, not .adjust files.
camList=${sfsDir}/run-camera-list.txt
mkdir -p $(dirname $camList)
/bin/rm -fv $camList
((i=0))
for f in $(cat $imageList | perl -p -e "s#^.*?(M\d+\wE).*?\s*\n#\$1\n#g"); do 
  cam=$(ls ${baPrefix}*${f}*.json)
  if [ ! -f "$cam" ]; then
    echo "Missing camera file: $cam" >> $out
    exit 1
  fi
  #echo $cam $i >> $out
  ((i++))
  echo $cam >> $camList
done

echo imageList=$imageList
echo baPrefix=$baPrefix
echo dem=$dem
echo sfsDir=$sfsDir
echo currDir=$currDir
echo Wrote: $camList

sfs -i $dem                             \
  --image-list $imageList               \
  --camera-list $camList                \
  --compute-exposures-only              \
  --shadow-threshold 0.005              \
  --crop-input-images                   \
  --smoothness-weight 0.08              \
  --initial-dem-constraint-weight 0.001 \
  --reflectance-type 1                  \
  --max-iterations 5                    \
  --save-sparingly                      \
  -o $sfsDir/run                        \
    > $out 2>&1


