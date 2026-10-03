#!/bin/bash
# Query solar azimuth and elevation for an image and camera list using ASP sfs --query
# Usage:
#   sfs_query.sh <dem.tif> <image_list.txt> <camera_list.txt> <out_dir> [num_processes]

set -e
set -u

if [ $# -lt 4 ]; then
  echo "Usage: $0 <dem.tif> <image_list.txt> <camera_list.txt> <out_dir> [num_processes]"
  exit 1
fi

dem="$1"
imgList="$2"
camList="$3"
outDir="$4"
numProc="${5:-1}"

if [ ! -f "$dem" ]; then
  echo "Error: DEM file not found: $dem"
  exit 1
fi

if [ ! -f "$imgList" ]; then
  echo "Error: Image list not found: $imgList"
  exit 1
fi

if [ ! -f "$camList" ]; then
  echo "Error: Camera list not found: $camList"
  exit 1
fi

mkdir -p "$outDir"

# Environment configuration
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/libexec:$ISISROOT/bin:$PATH
export LD_LIBRARY_PATH=$ISISROOT/lib:${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/lib:${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/lib/csmplugins:${LD_LIBRARY_PATH:-}
umask 022
ulimit -c 0

totalImgs=$(wc -l < "$imgList" | tr -d ' ')
echo "Querying solar azimuth for $totalImgs images using DEM: $dem (processes: $numProc)"

if [ "$numProc" -le 1 ]; then
  sfs --threads 1 --query \
    -i "$dem" \
    --image-list "$imgList" \
    --camera-list "$camList" \
    -o "$outDir/run" 2>&1 | tee "$outDir/out_sfs_query.txt"
else
  # Multi-process parallel chunk execution
  chunkDir="$outDir/chunks"
  mkdir -p "$chunkDir"
  rm -rf "${chunkDir:?}"/*

  linesPerChunk=$(( (totalImgs + numProc - 1) / numProc ))
  split -l "$linesPerChunk" -d -a 3 "$imgList" "$chunkDir/imgs_chunk_"
  split -l "$linesPerChunk" -d -a 3 "$camList" "$chunkDir/cams_chunk_"

  pids=()
  for c_img in "$chunkDir"/imgs_chunk_*; do
    idx="${c_img##*_}"
    c_cam="$chunkDir/cams_chunk_$idx"
    c_out="$chunkDir/run_$idx"

    sfs --threads 1 --query \
      -i "$dem" \
      --image-list "$c_img" \
      --camera-list "$c_cam" \
      -o "$c_out" > "$chunkDir/out_$idx.txt" 2>&1 &
    pids+=($!)
  done

  # Wait for all chunk workers to complete
  for pid in "${pids[@]}"; do
    wait "$pid"
  done

  cat "$chunkDir"/out_*.txt > "$outDir/out_sfs_query.txt"
fi

# Parse output into structured table:
# image_path raw_azimuth normalized_azimuth_0_360 elevation
grep "Sun azimuth and elevation for:" "$outDir/out_sfs_query.txt" | \
  awk '{
    raw_az = $8;
    norm_az = raw_az;
    while (norm_az < 0) norm_az += 360.0;
    while (norm_az >= 360.0) norm_az -= 360.0;
    print $6, raw_az, norm_az, $10
  }' | sort -k1 > "$outDir/azimuth_table.txt"

count=$(wc -l < "$outDir/azimuth_table.txt" | tr -d ' ')
echo "Finished querying azimuths. Recovered $count / $totalImgs values in $outDir/azimuth_table.txt"
