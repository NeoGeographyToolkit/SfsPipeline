#!/bin/bash

# Run dense correlation between two images (e.g., pre-made hillshades)
# using parallel_stereo in correlator mode with ASP MGM.
#
# Usage:
#   dense_correlator.sh <leftImage> <rightImage> <range> <currDir> [stereoDir]
#
# range: search range in pixels for the correlator (e.g., 25).
# If stereoDir is not given, it defaults to "corr" under currDir.

leftImage=$1; shift
rightImage=$1; shift
range=$1; shift
currDir=$1; shift
stereoDir=$1; shift
cd $currDir

if [ "$stereoDir" = "" ]; then
  stereoDir=corr
fi

echo leftImage=$leftImage
echo rightImage=$rightImage
echo range=$range
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
    PBS_NODEFILE=$(uname -n).txt
    echo $(uname -n) > $PBS_NODEFILE
fi
echo Head node: $(uname -n) >> $out
echo Machines: $(cat ${PBS_NODEFILE}) >> $out
echo " " >> $out

win="-${range} -${range} ${range} ${range}"

# Run dense correlation.
# --corr-seed-mode 0 skips the low-res seeding stage and uses the full
# search range at every tile. Slower but robust: for sites with small
# shift (~1 px or less at the 33x-subsampled low-res stage), the seeded
# correlator can miss the shift entirely because it becomes sub-pixel
# at that scale. Mons Mouton's 20-30 px full-res shift was too small
# to seed. Slower-but-correct wins over fast-but-fragile by default.
parallel_stereo              \
  --correlator-mode          \
  --stereo-algorithm asp_mgm \
  --corr-kernel 9 9          \
  --ip-per-image 40000       \
  --subpixel-mode 9          \
  --corr-seed-mode 0         \
  --corr-search              \
  $win                       \
  --processes 8              \
  --nodes-list $PBS_NODEFILE \
  $leftImage $rightImage     \
  $stereoDir/run >> $out 2>&1

# Extract disparity bands. disparitydebug --raw handles nodata properly.
# Produces run-F-H.tif (horizontal) and run-F-V.tif (vertical).
disparitydebug --raw ${stereoDir}/run-F.tif >> $out 2>&1

echo Done. See $out for details.
echo "View with: sgm -10 10 ${stereoDir}/run-F-H.tif ${stereoDir}/run-F-V.tif"
