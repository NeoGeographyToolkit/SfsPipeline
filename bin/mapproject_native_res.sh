#!/bin/bash

# Mapproject a list of images at their OWN native ground sample distance (no
# fixed --tr, so mapproject uses each image's native resolution), with each
# image's registered camera, onto a reference DEM. This builds the native-GSD
# orthoimage set delivered beside the 1 m/pixel set (the frames the PDS lists as
# better than 1 m/pixel). It also writes gsd.csv with the ACTUAL output pixel
# size read back from each ortho.
#
# A plain loop, one mapproject per image; the caller (project notes) sets any
# qsub. Images and cameras are paired line by line (line N of each list).
#
# Args:
#   imageList   text file, one image (cub or tif) per line
#   cameraList  text file, one camera (CSM .json) per line, 1-to-1 with imageList
#   refDem      reference DEM to drape onto
#   outDir      output directory (created if missing)
#   currDir     working dir to cd into (project root)
#   threads     optional, default $NCPUS or nproc

if [ "$#" -lt 5 ]; then
    echo "Usage: $0 <imageList> <cameraList> <refDem> <outDir> <currDir> [threads]"
    exit 1
fi
imageList=$1
cameraList=$2
refDem=$3
outDir=$4
currDir=$5
threads=${6:-${NCPUS:-$(nproc --all)}}
cd "$currDir"

SP=${ASPROOT:-$HOME/projects/BinaryBuilder/StereoPipeline}
export PATH=$SP/bin:$SP/libexec:$PATH
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
umask 022
ulimit -c 0

mkdir -p "$outDir"
log="output_$(basename "$outDir").txt"
echo "mapproject_native_res: $(wc -l < "$imageList") images -> $outDir  threads=$threads" | tee "$log"

paste "$imageList" "$cameraList" | while read -r img cam; do
    id=$(echo "$img" | perl -pe 's#.*?(M\d+[LR]E).*#$1#')
    out="$outDir/$id.map.tif"
    if [ ! -s "$img" ] || [ ! -s "$cam" ]; then
        echo "WARN missing image or camera for $id, skipping" | tee -a "$log"
        continue
    fi
    if [ ! -s "$out" ]; then
        # no --tr: mapproject uses the image's native GSD
        mapproject --threads "$threads" "$refDem" "$img" "$cam" "$out" \
            >> "$log" 2>&1
    fi
done

# gsd.csv from the real outputs (actual output pixel size, in meters)
echo "image_id,native_gsd_m" > "$outDir/gsd.csv"
for out in "$outDir"/*.map.tif; do
    [ -s "$out" ] || continue
    id=$(basename "$out" .map.tif)
    gsd=$(gdalinfo "$out" | perl -ne 'print "$1\n" if /Pixel Size = \(([0-9.]+)/')
    echo "$id,$gsd" >> "$outDir/gsd.csv"
done
echo "done: $(ls "$outDir"/*.map.tif 2>/dev/null | wc -l) orthos, gsd.csv written" | tee -a "$log"
