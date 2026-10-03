#!/bin/bash

# Hillshade DEMs and find correlation

leftDem=$1; shift
rightDem=$1; shift
currDir=$1; shift
stereoDir=$1; shift
maxSearch=$1; shift   # optional 5th arg: corr search half-window in px (default 25)
[ -z "$maxSearch" ] && maxSearch=25
cd $currDir

# Setup stereoDir name if not provided
if [ "$stereoDir" = "" ]; then
  stereoDir=$(basename $leftDem)_$(basename $rightDem)
  stereoDir=$(echo $stereoDir | perl -p -e "s#\.tif##g")
fi

echo leftDem=$leftDem
echo rightDem=$rightDem
echo currDir=$currDir
echo stereoDir=$stereoDir

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

# Hillshade the DEMs with a small elevation to bring out contrast
# Consider using instead:
# gdaldem hillshade -multidirectional -compute_edges -alt 20.
leftHill=${leftDem%.tif}_hill.tif
rightHill=${rightDem%.tif}_hill.tif
# Skip if done already
if [ ! -f "$leftHill" ]; then
    echo Creating left hillshade: $leftHill
    hillshade -e 10 $leftDem -o $leftHill >> $out 2>&1
else
    echo Left hillshade $leftHill exists already, skipping >> $out 2>&1
fi
if [ ! -f "$rightHill" ]; then
    echo Creating right hillshade: $rightHill
    hillshade -e 10 $rightDem -o $rightHill >> $out 2>&1
else
    echo Right hillshade $rightHill exists already, skipping >> $out 2>&1
fi

# Build image pyramids for the hillshades
stereo_gui                     \
  --create-image-pyramids-only \
  $leftHill $rightHill         \
  >> $out 2>&1

# Run asp_mgm with a large kernel size to overcome noise. It is assumed that
# both input DEMs have the same extent, size, and resolution. Use a corr search
# window somewhat bigger than the expected shift.
parallel_stereo                      \
  --correlator-mode                  \
  --stereo-algorithm asp_mgm         \
  --corr-kernel 9 9                  \
  --ip-per-image 40000               \
  --subpixel-mode 9                  \
  --corr-search -$maxSearch -$maxSearch $maxSearch $maxSearch \
  --processes 8                      \
  --nodes-list $PBS_NODEFILE         \
  $leftHill $rightHill               \
  --num-matches-from-disparity 40000 \
  $stereoDir/run >> $out 2>&1

# Look at disparity bands
for b in 1 2 3; do 
  gdal_translate                 \
  -co compress=lzw -co TILED=yes \
  -co INTERLEAVE=BAND            \
  -co BLOCKXSIZE=256             \
  -co BLOCKYSIZE=256             \
  -co BIGTIFF=YES                \
  -b $b ${stereoDir}/run-F.tif   \
  ${stereoDir}/run-F_b${b}.tif >> $out 2>&1
done

# Make the invalid disparity no-data
t=1e+6
for b in 1 2; do 
  image_calc -c "(var_0 + $t)*var_1 - $t" \
  --output-nodata-value -$t               \
  --cache-size-mb 3000                    \
  ${stereoDir}/run-F_b${b}.tif            \
  ${stereoDir}/run-F_b3.tif               \
  -o ${stereoDir}/run-F_b${b}_nodata.tif  \
  >> $out 2>&1
done

# Build low-res pyramids
stereo_gui                         \
  --create-image-pyramids-only     \
  ${stereoDir}/run-F_b1_nodata.tif \
  ${stereoDir}/run-F_b2_nodata.tif \
  >> $out 2>&1
  
# # View colorized disparity with masked no-data
echo sgm -10 10 --grid-cols 1 ${stereoDir}/run-F_b1_nodata.tif ${stereoDir}/run-F_b2_nodata.tif 

# Align with zero iterations to just use the matches from asp_mgm
matchFile=$(ls $stereoDir/run-disp*.match) # there should be only one
echo matchFile=$matchFile
pc_align                                     \
  --max-displacement -1                      \
  --num-iterations 0                         \
  --max-num-reference-points 1000000         \
  --match-file $matchFile                    \
  --initial-transform-from-hillshading rigid \
  --initial-transform-ransac-params 1000 3   \
  --save-transformed-source-points           \
  $leftDem $rightDem                         \
  -o $stereoDir/align                        \
  >> $out 2>&1
point2dem --tr 1.0                           \
  $stereoDir/align-trans_source.tif          \
  >> $out 2>&1
  
# Hillshade
f=$stereoDir/align-trans_source.tif
# Replace .tif by -DEM.tif
f=${f%.tif}-DEM.tif
g=${f%.tif}_hill.tif
hillshade -e 10 $f -o $g >> $out 2>&1

# Build image pyramids for the hillshade
stereo_gui --create-image-pyramids-only \
  $leftHill $rightHill $g               \
  >> $out 2>&1
