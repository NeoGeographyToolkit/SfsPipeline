#!/bin/bash

# Query the native ground sample distance (GSD) of each SFS image with
# ASP mapproject --query-projection. That option prints the auto-estimated
# output pixel size for a given camera and drape DEM, without doing the
# mapprojection (it emits a "pixel_size,<gsd>" line, parsed below).
#
# This derives the per-image GSD list for the "better than 1 m/pixel"
# ortho request (Ross/Artemis). For Mons, Ross supplied the GSD per image
# from the PDS RESOLUTION label; for SP/VIPER we have no such list on hand,
# so we compute it here. The queried value is the exact --tr mapproject
# would auto-pick, so it stays consistent with the native-res ortho step.
#
# imageList and cameraList must be paired one-to-one: same order, same
# length (build the camera list FROM the image list). Validated below.
#
# No PBS logic here; the caller (project notes) sets any qsub. This loads
# one camera per image, so run it where the cubes and cameras live (pfe),
# not on a head node for large lists.
#
# Args:
#   imageList   text file, one cube/image path per line
#   cameraList  text file, one camera path per line (paired with imageList)
#   dem         drape DEM (the site LOLA DEM)
#   outPrefix   output list prefix; writes <outPrefix>_all.txt (id gsd) and
#               <outPrefix>_lt<threshold>.txt (rows with gsd < threshold)
#   threshold   GSD cutoff for the filtered list (e.g. 1.0)
#   currDir     project root to cd into

if [ "$#" -lt 6 ]; then
    echo "Usage: $0 <imageList> <cameraList> <dem> <outPrefix> <threshold> <currDir>"
    exit 1
fi
imageList=$1
cameraList=$2
dem=$3
outPrefix=$4
threshold=$5
currDir=$6
cd $currDir

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022

# Validate the paired lists (CLAUDE.md paired-list rule)
nImg=$(wc -l < $imageList)
nCam=$(wc -l < $cameraList)
if [ "$nImg" -ne "$nCam" ]; then
    echo "Error: imageList ($nImg rows) and cameraList ($nCam rows) differ in length."
    exit 1
fi

allOut=${outPrefix}_all.txt
ltOut=${outPrefix}_lt${threshold}.txt
/bin/rm -f $allOut $ltOut

i=1
while [ "$i" -le "$nImg" ]; do
    img=$(sed -n "${i}p" $imageList)
    cam=$(sed -n "${i}p" $cameraList)
    id=$(basename $img | sed 's/\.[^.]*$//')
    # A 4th positional (dummy output) is REQUIRED when image and camera are
    # separate files: the mapproject wrapper otherwise reads the camera as the
    # output ("output file is a camera"). --query-projection never writes it.
    gsd=$(mapproject --query-projection $dem $img $cam /tmp/query_gsd_dummy.tif 2>/dev/null \
            | grep '^pixel_size,' | cut -d, -f2)
    if [ -z "$gsd" ]; then
        echo "Warning: no GSD for $id (query failed)" 1>&2
        gsd=NaN
    fi
    echo "$id $gsd" >> $allOut
    i=$((i+1))
done

# Filtered list: GSD strictly below threshold (skips NaN rows)
awk -v t=$threshold '$2 != "NaN" && $2 < t {print}' $allOut > $ltOut

echo "Wrote $allOut ($(wc -l < $allOut) rows)"
echo "Wrote $ltOut ($(wc -l < $ltOut) rows with gsd < $threshold)"
