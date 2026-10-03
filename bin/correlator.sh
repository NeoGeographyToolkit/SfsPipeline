#!/bin/bash

# Find correlation between mapprojected images. These are expected to have
# the same resolution and same extent and size. 
# TODO: This must be checked on input.

# Option --skip-image-normalization ensure the size is preserved.

leftImage=$1; shift
rightImage=$1; shift 
stereoDir=$1; shift
maxDispSpread=$1; shift
currDir=$1; shift
cd $currDir

echo leftImage=$leftImage
echo rightImage=$rightImage
echo stereoDir=$stereoDir
echo maxDispSpread=$maxDispSpread
echo currDir=$currDir

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022 # needed to handle permissions

# Set up the output file
mkdir -p $stereoDir
out=${stereoDir}/output_corr.txt
rm -fv $out
echo Writing the output to: $out

# These two images must have the same size and resolution. We count on this
# when setting up --corr-search.
leftSize=$(gdalinfo $leftImage | grep Size)
rightSize=$(gdalinfo $rightImage | grep Size)
if [ "$leftSize" != "$rightSize" ]; then
    echo "Error: The left and right images have different sizes:" >> $out
    echo " left: $leftSize" >> $out
    echo " right: $rightSize" >> $out
    exit 1
else
    echo Both images have the same size: $leftSize >> $out
fi

# Set up the nodes file
if [ "$PBS_NODEFILE" = "" ]; then
    # To run locally
    PBS_NODEFILE=$(uname -n).txt
    echo $(uname -n) > $PBS_NODEFILE
fi
echo Head node: $(uname -n) >> $out
echo Machines: $(cat ${PBS_NODEFILE}) >> $out
# Ensure some separation in the output file
echo " " >> $out
echo " " >> $out

# Run the correlator. It is very important to set the nodata value to mask the
# shadows.
((half=maxDispSpread/2))
echo half=$half

#  --max-disp-spread $maxDispSpread       \
parallel_stereo                           \
  --nodes-list $PBS_NODEFILE              \
  --correlator-mode                       \
  --nodata-value 0.005                    \
  --skip-image-normalization              \
  --stereo-algorithm asp_bm               \
  --ip-per-image 50000                    \
  --num-matches-from-disparity 20000      \
  $leftImage $rightImage                  \
  --corr-search -$half -$half $half $half \
  ${stereoDir}/run                        \
  >> $out 2>&1

# Look at disparity bands
for b in 1 2 3; do 
  gdal_translate -b $b ${stereoDir}/run-F.tif ${stereoDir}/run-F_b${b}.tif >> $out 2>&1
done

# Make the invalid disparity no-data
t=1e+6
for b in 1 2; do 
  image_calc -c "(var_0 + $t)*var_1 - $t" \
  --output-nodata-value -$t               \
  ${stereoDir}/run-F_b${b}.tif            \
  ${stereoDir}/run-F_b3.tif               \
  -o ${stereoDir}/run-F_b${b}_nodata.tif  \
  >> $out 2>&1
done

# Build low-res pyramids
stereo_gui --create-image-pyramids-only \
  ${stereoDir}/run-F_b1_nodata.tif \
  ${stereoDir}/run-F_b2_nodata.tif \
  >> $out 2>&1
  
# # View colorized disparity with masked no-data
# sgm -10 10 --grid-cols 1 ${stereoDir}/run-F_b1_nodata.tif ${stereoDir}/run-F_b2_nodata.tif &
