#!/bin/bash

if [ "$#" -lt 5 ]; then echo Usage: $0 list dem mapDir outPrefix currDir; exit; fi

# Run bundle_adjust. The image list must have, on each line text of the form:
# <something>M<digits>{LE,RE}<something>. Extra text in it will be wiped,
# only the id will be kept: M<digits>{LE,RE}.
#
# Conventions for inputs:
# Images: img/<id>.cal.echo.cub
# Cameras: img/<id>.cal.echo.json
# Mapprojected: ${mapDir}/<id>.cal.echo.map.tr1.tif

list=$1
dem=$2
mapDir=$3
outPrefix=$4
currDir=$5
cd $currDir

echo list=$list
echo dem=$dem
echo mapDir=$mapDir
echo outPrefix=$outPrefix
echo currDir=$currDir

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022 # make files readable by others
ulimit -c 0 # no core dumps

# Tunables, overridable via env. Defaults preserve prior behavior.
#   IMG_DIR        - dir holding <id>.cal.echo.cub / .json (default img)
#   OVERLAP_LIMIT  - match each image to this many subsequent ones (default 100)
#   NUM_ITERATIONS - BA solver iterations. Set 0 for matches-only (default 100)
#   PROCESSES      - parallel_bundle_adjust processes per node (default 10)
#   THREADS        - threads per process (default 8)
imgDir=${IMG_DIR:-img}
overlapLimit=${OVERLAP_LIMIT:-100}
numIterations=${NUM_ITERATIONS:-100}
numProcesses=${PROCESSES:-10}
numThreads=${THREADS:-8}

if [ "$PBS_NODEFILE" = "" ]; then
    # To run locally
    PBS_NODEFILE=$(uname -n).txt
    echo $(uname -n) > $PBS_NODEFILE
fi

out=output_$(dirname $outPrefix).txt
rm -fv $out
echo Writing: $out

echo Head node: $(uname -n) >> $out
echo Machines: $(cat ${PBS_NODEFILE}) >> $out

# Compute the lists of inputs. Name these "-input-*" so they don't
# collide with ASP BA's own "-image_list.txt" / "-camera_list.txt"
# outputs (which BA writes at end of run with paths to the amended
# cameras). Keeps input copies vs BA outputs unambiguous.
mkdir -p $(dirname $outPrefix)
ilist=${outPrefix}-input-image_list.txt
clist=${outPrefix}-input-camera_list.txt
mlist=${outPrefix}-input-mapprojected_data_list.txt

# Check that list is not same as ilist
if [ "$list" = "$ilist" ] || [ "$list" = "$clist" ] || [ "$list" = "$mlist" ]; then
    echo "Error: The input list $list cannot be the same as one of the output lists."
    exit 1
fi

cat $list | perl -p -e "s#^.*?(M\d+[LR]E).*?\n#${imgDir}/\$1.cal.echo.cub\n#g" > $ilist
cat $list | perl -p -e "s#^.*?(M\d+[LR]E).*?\n#${imgDir}/\$1.cal.echo.json\n#g" > $clist
cat $list | perl -p -e "s#^.*?(M\d+[LR]E).*?\n#${mapDir}/\$1.cal.echo.map.tr1.tif\n#g" > $mlist
echo $dem >> $mlist # must append the DEM

# The trickiest parameter is --overlap-limit. Here it is set at 100 to match with
# that many subsequent images. For a large number of images, this is a lot.
 
# Use a high outlier removal threshold, to remove only the most obvious
# outliers. That because sometimes the outliers can prevent convergence to start
# with, and then aggressive outlier removal can remove good points. 

# Use --robust-threshold 2 to make it work harder moving cameras Here we don't
# use that many iterations as the primary goal is to find matches. Later this
# can be refined.

parallel_bundle_adjust                     \
    --nodes-list $PBS_NODEFILE             \
    --processes $numProcesses              \
    --threads $numThreads                  \
    --image-list $ilist                    \
    --camera-list $clist                   \
    --mapprojected-data-list $mlist        \
    --camera-weight 0.00                   \
    --datum D_MOON                         \
    --ip-per-image 50000                   \
    --ip-detect-method 0                   \
    --max-pairwise-matches 5000            \
    --match-first-to-last                  \
    --min-matches 1                        \
    --forced-triangulation-distance 100000 \
    --min-triangulation-angle 1e-10        \
    --num-iterations $numIterations        \
    --num-passes 2                         \
    --remove-outliers-params               \
    "75.0 3.0 100 100"                     \
    --robust-threshold 2                   \
    --overlap-limit $overlapLimit          \
    --parameter-tolerance 1e-12            \
    -o $outPrefix                          \
    >> $out 2>&1
