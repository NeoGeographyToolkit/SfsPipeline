#!/bin/bash
# Query solar azimuth for all SFS images
# Usage: qsub ... -- query_azimuth.sh $(pwd)

set -u
currDir=$1; shift
cd $currDir

# Set up the environment (ASPROOT, ISISROOT, ISISDATA from your .bashrc)
binDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$binDir/sfs_env.sh" || exit 1

sfs --query \
  -i ref/MM_1m_lola.tif \
  --image-list lists/sfs_image_list_rc3.txt \
  --camera-list lists/sfs_camera_list_rc3.txt \
  -o sfs_query/run | tee out_sfs_query.txt

grep azi out_sfs_query.txt | awk '{print $6, $8}' | sort -k2 -n > lists/azimuth.txt
echo "Done. Azimuth list in lists/azimuth.txt"
