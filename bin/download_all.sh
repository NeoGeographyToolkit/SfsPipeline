#!/bin/bash

# Download all urls from the list. Such a list can be generated automatically
# using query_lro.py (or query_lro.sh) --output-urls list.txt, or obtained from
# ODE search results.

if [ "$#" -lt 1 ]; then echo Usage: $0 list.txt; exit; fi

list=$1; shift

# Find number of elements in the list
n=$(cat $list | wc -l)
echo Number of entries in $list: $n

# These start from 1. end is inclusive.
beg=$1; shift
end=$1; shift

# If no beginning and end specified, set to full range
if [ -z "$beg" ]; then beg=1; fi
if [ -z "$end" ]; then end=$n; fi

echo beg=$beg end=$end

# Subtract 1 from beg, as we will use a zero-based index
((b=beg-1))
# Keep e at end, because the end of the range is exclusive
((e=end))

# Iterate through all the files. If a download fails, will try again
# next time around.
allDone=0
while true; do
    
    # Looks like the xml file is not needed later
    allDone=1
    for f in $(cat $list | ~/bin/print_line_range.pl $b $e | grep -i -v xml); do
    
      # This can have non-printable characters such as \r, which need to be removed
      f=$(echo $f | perl -pi -e 's/\s+//g')
      echo link: $f
      
      file=$(basename $f)
      echo file: $file
      if [ -f $file ]; then 
          echo $file already exists, skipping.
          continue
      fi
        
      allDone=0
      echo Trying to download $f
      /usr/bin/time wget --show-progress -N --no-check-certificate $f
      ans=$?
      if [ "$ans" -ne 0 ]; then
            echo Download failed, waiting 30 seconds and trying again.
            sleep 30
        else
            echo Download succeeded. Pause and continue.
            sleep 5
        fi
    done
    
    # If all done, exit
    if [ "$allDone" -eq 1 ]; then
        echo All done, exiting.
        exit
    fi
done

