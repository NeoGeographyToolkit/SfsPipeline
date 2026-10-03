#!/bin/bash

# gdalwarp a raster onto a fixed target grid (extent + resolution), in the
# SAME projection (no -t_srs, so PROJ data is not needed). Used to put a
# blended/mosaic product onto the delivered LOLA grid, matching the max-lit.
#
# No PBS logic here; the caller (project notes/plan) sets any qsub.
#
# Args:
#   input     input tif
#   output    output tif (on the target grid)
#   te        target extent as ONE quoted string: "xmin ymin xmax ymax"
#   tr        target resolution (meters), applied as -tr tr tr
#   currDir   working dir to cd into

if [ "$#" -lt 5 ]; then
    echo "Usage: $0 <input> <output> '<xmin ymin xmax ymax>' <tr> <currDir>"
    exit 1
fi
input=$1
output=$2
te=$3
tr=$4
currDir=$5
cd $currDir
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/StereoPipeline}/bin:${ISISROOT:-$HOME/miniconda3/envs/asp_deps}/bin:$PATH
umask 022

out=output_regrid_$(basename $output .tif).txt
exec >> "$out" 2>&1
echo "gdalwarp $input -> $output  te=[$te] tr=$tr"
echo "start $(date)"
gdalwarp -overwrite -tr $tr $tr -te $te -r cubicspline -dstnodata -1e+06 \
    "$input" "$output"
echo "rc=$?"
echo "done $(date)"
