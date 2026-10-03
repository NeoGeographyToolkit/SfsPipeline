#!/bin/bash

if [ "$#" -lt 2 ]; then echo Usage: $0 dem currDir; exit; fi

dem=$1; shift
currDir=$1; shift

cd $currDir

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH

umask 022
ulimit -c 0

out=output_mapproject.txt
rm -fv $out
echo Will write the output to $out

for img in $(cat cubes.txt); do 
    cam=${img/.cub/.json}
    map=${img/.cub/.map.tr10.tif}
    
    # Skip if $map exists
    if [ -f "$map" ]; then
        echo "Skip existing: $map" >> $out
        continue
    fi
    
    if ! mapproject --tr 10 --processes 8 --threads 8 \
      --tile-size 512 \
      "$dem" "$img" "$cam" "$map" >> "$out" 2>&1; then
      echo "Warning: mapproject failed for $img" >> "$out"
      rm -f "$map"
      rm -rf "${map%.tif}_tif_tiles"
      continue
    fi

    stereo_gui --create-image-pyramids-only $map >> $out
done

