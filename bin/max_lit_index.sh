#!/bin/bash

# Max-lit mosaic with a per-pixel source-image index map
# (dem_mosaic --max --save-index-map). Pair with add_rat_to_vrt.py to map the
# index DN values back to source LROC NAC product ids in QGIS. A single-node
# worker; qsub it. De-pbs'd from run_max_lit_indexes.pbs.
#
# Args:
#   imageList   text file of mapprojected images, one per line
#   outName     output mosaic tif
#   currDir     work dir, pass as $(pwd)
# Env:
#   PROJWIN   optional "xmin ymin xmax ymax" to limit the output extent
#   THREADS   dem_mosaic threads (default: all cores, nproc)

if [ "$#" -lt 3 ]; then echo "Usage: $0 imageList outName currDir"; exit 1; fi
imageList=$1; outName=$2; currDir=$3
cd "$currDir" || exit 1

export ASPROOT=${ASPROOT:-$HOME/projects/BinaryBuilder/StereoPipeline}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
export PATH=$ASPROOT/bin:$ISISROOT/bin:$PATH
umask 022
ulimit -c 0

threads=${THREADS:-${NCPUS:-$(nproc --all)}}
args=(--max --save-index-map --threads "$threads")
[ -n "$PROJWIN" ] && args+=(--t_projwin $PROJWIN)
args+=(-l "$imageList" -o "$outName")

out=output_$(basename "${outName%.tif}").index.txt
echo "dem_mosaic --max --save-index-map -> $outName (log $out)"
dem_mosaic "${args[@]}" >> "$out" 2>&1
