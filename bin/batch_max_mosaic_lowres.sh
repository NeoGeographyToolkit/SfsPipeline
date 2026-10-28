#!/bin/bash

# Make low-res mosaics

# Check for arguments
if [ "$#" -lt 2 ]; then echo Usage: $0 list.txt currDir; exit; fi

list=$1; shift
currDir=$1; shift
cd $currDir

# Set up the environment (ASPROOT, ISISROOT, ISISDATA from your .bashrc)
binDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$binDir/sfs_env.sh" || exit 1

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
  sed -n "$((beg + 1)),${end}p" "$list" > $curr_list
  dem_mosaic --max --tr 10 --dem-list $curr_list -o mosaics/mosaic_${beg}_${end}.tif > $out
done

