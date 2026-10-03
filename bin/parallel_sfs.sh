#!/bin/bash

# Run parallel_sfs on a big DEM. We may have about 650 jobs (or more, for big
# DEMs). Use 6 jobs per machine as they can run out of memory. Each job takes
# maybe an hour or two. Use 8 - 16 machines for 16 hours.

# The exposures are computed on-the-fly, before the distribution of the jobs,
# unless it already exists and has as many lines as the image file.

# If estimError is 1, the DEM passed in must be the produced SfS DEM (after sfs_blend).
# On output, it will write:
# <output prefix>-height-error.tif
# The DEM will not change.

# The image list must have, on each line text of the form:
# <something>M<digits>{LE,RE}<something>. Extra text in it will be wiped,
# only the id will be kept: M<digits>{LE,RE}.

# Use a low-light-threshold, if pased in

if [ "$#" -lt 7 ]; then 
    echo Usage: $0 dem numCpu baPrefix imageList estimError sfsPrefix currDir
    exit 
fi

dem=$1; shift
numCpu=$1; shift # this needs decreasing for many images
baPrefix=$1; shift
imageList=$1; shift
estimError=$1; shift
sfsPrefix=$1; shift
currDir=$1; shift
demWeight=$1; shift
shadowThresh=$1; shift
lowLightThresh=$1; shift
cd $currDir

# If no demWeight is given, use 0.001
if [ "$demWeight" = "" ]; then
  demWeight=0.001
fi
# if no shadow thresh, use 0.005
if [ "$shadowThresh" = "" ]; then
  shadowThresh=0.005
fi

echo dem=$dem
echo numCpu=$numCpu
echo baPrefix=$baPrefix
echo imageList=$imageList
echo estimError=$estimError
echo sfsPrefix=$sfsPrefix
echo currDir=$currDir
echo demWeight=$demWeight
echo shadowThresh=$shadowThresh
echo lowLightThresh=$lowLightThresh

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022 # make files readable by others

sfsDir=$(dirname $sfsPrefix)
mkdir -p $sfsDir

out=${sfsDir}/output.txt
rm -fv $out

echo Writing the output to: $out

if [ "$PBS_NODEFILE" = "" ]; then
    # To run locally
    PBS_NODEFILE=$(uname -n).txt
    echo $(uname -n) > $PBS_NODEFILE
fi
echo Head node: $(uname -n) >> $out
echo Machines: $(cat ${PBS_NODEFILE}) >> $out

# dem must exist
if [ ! -f "$dem" ]; then
    echo "Missing DEM file: $dem" >> $out
    exit 1
fi

# Prepare the image list. Each tile's input list may have any text per
# line; we extract the M<digits>{LE,RE} id and rebuild the path using
# IMAGE_DIR/<id>IMAGE_SUFFIX (e.g. img/M1234LE.cal.echo.cub).
# IMAGE_DIR and IMAGE_SUFFIX are env vars; set them per-site to match
# your filesystem layout.
#   Default IMAGE_DIR:    img
#   Default IMAGE_SUFFIX: .cal.echo.cub   (Earth/Mars LRO NAC examples)
#   Mons Mouton uses:     IMAGE_DIR=IMAGES  IMAGE_SUFFIX=.ech.cub
if [ -z "$IMAGE_DIR" ]; then
    IMAGE_DIR=img
fi
if [ -z "$IMAGE_SUFFIX" ]; then
    IMAGE_SUFFIX=.cal.echo.cub
fi
echo IMAGE_DIR=$IMAGE_DIR
echo IMAGE_SUFFIX=$IMAGE_SUFFIX
cat $imageList | perl -p -e "s#^.*?(M\d+\wE).*?\n#${IMAGE_DIR}/\$1${IMAGE_SUFFIX}\n#g" \
  > ${sfsPrefix}-image-list.txt
imageList=${sfsPrefix}-image-list.txt

# Prepare the cameras. Use the inline json camera files, not .adjust files.
camList=${sfsPrefix}-camera-list.txt
mkdir -p $(dirname $camList)
/bin/rm -fv $camList
((i=0))
for f in $(cat $imageList | perl -p -e "s#^.*?(M\d+\wE).*?\n#\$1\n#g"); do 
  cam=$(ls ${baPrefix}*${f}*.json)
  if [ ! -f "$cam" ]; then
    echo "Missing camera file: $cam" >> $out
    exit 1
  fi
  #echo $cam $i >> $out
  ((i++))
  echo $cam >> $camList
done

opt=""
if [ "$estimError" -eq "1" ]; then
    opt="--estimate-height-errors"
fi

# If low-light-thresh is given, use it
if [ "$lowLightThresh" != "" ]; then
  opt="$opt --low-light-threshold $lowLightThresh"
fi

echo imageList=$imageList
echo camList=$camList

# Exposures
exposures=${sfsPrefix}-exposures.txt

# Exposures must exist if we estimate errors as by then SfS is done
if [ "$estimError" -eq "1" ] && [ ! -f "$exposures" ]; then
  echo "Missing exposures file: $exposures" >> $out
  exit 1
fi

# If exposures exist, and have as many lines as the images, use them.
if [ -f "$exposures" ]; then
  
  numExposures=$(wc -l < $exposures)
  numImages=$(wc -l < $imageList)
  if [ "$numExposures" -ge "$numImages" ]; then
    echo Will use the exposures file $exposures >> $out
    opt="$opt --image-exposures-prefix $sfsPrefix"
  else
    echo "The exposures file $exposures is inconsistent with the image list." >> $out
    echo "Will recompute the exposures." >> $out
  fi
else 
  echo No exposures file. Will calculate it from scratch. >> $out
fi

echo opt=$opt

parallel_sfs                                   \
    --resume                                   \
    -i $dem                                    \
    --image-list $imageList                    \
    --camera-list $camList                     \
    --shadow-threshold $shadowThresh           \
    --allow-borderline-data                    \
    --crop-input-images                        \
    --blending-dist 10                         \
    --min-blend-size 50                        \
    --threads 8                                \
    --smoothness-weight 0.08                   \
    --initial-dem-constraint-weight $demWeight \
    --reflectance-type 1                       \
    --max-iterations 5                         \
    --save-sparingly                           \
    $opt                                       \
    --nodes-list ${PBS_NODEFILE}               \
    --tile-size 200                            \
    --padding 50                               \
    --processes $numCpu                        \
    -o $sfsPrefix                              \
    >> $out 2>&1 

# Produce a hillshade of the final DEM, if height errors are not estimated
if [ "$estimError" -eq "0" ]; then
  f=$(ls $sfsPrefix*-DEM-final.tif)
  g=${f/.tif/_hill.tif}
  gdaldem hillshade -multidirectional -compute_edges $f $g >> $out 2>&1
fi
