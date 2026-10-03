#!/bin/bash

# Make low-res mosaics

# Check for arguments
if [ "$#" -lt 2 ]; then echo Usage: $0 list.txt currDir; exit; fi

list=$1; shift
currDir=$1; shift
cd $currDir

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH

out=output_mosaic.txt
echo Will write the output to $out
rm -f $out

# Make max-list mosaics in batches of 20. The inputs are sorted by illumination.
w=20
num=$(cat $list | wc -l)
echo num=$num >> $out
batches=$(( (num + w - 1) / w )) 
echo batches=$batches >> $out
for ((i=0; i<batches; i++)); do
  ((beg=i*w))
  ((end=i*w+w))
  echo beg=$beg end=$end >> $out
  
  curr_list=tmp_mosaic_list.txt
  cat $list | ~/bin/print_line_range.pl $beg $end > $curr_list
  dem_mosaic --max --tr 10 --dem-list $curr_list -o mosaics/mosaic_${beg}_${end}.tif > $out
done

