#!/bin/bash
# Query solar azimuth for all SFS images
# Usage: qsub ... -- query_azimuth.sh $(pwd)

set -u
currDir=$1; shift
cd $currDir

export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022

sfs --query \
  -i ref/MM_1m_lola.tif \
  --image-list lists/sfs_image_list_rc3.txt \
  --camera-list lists/sfs_camera_list_rc3.txt \
  -o sfs_query/run | tee out_sfs_query.txt

grep azi out_sfs_query.txt | awk '{print $6, $8}' | sort -k2 -n > lists/azimuth.txt
echo "Done. Azimuth list in lists/azimuth.txt"
