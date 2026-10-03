#!/bin/bash

# Run dem2gcp to create GCPs from a disparity (warped SfS DEM aligned to
# reference LOLA DEM). Generic wrapper; all paths passed as arguments.
#
# NOTE (2026-04-15): this script no longer calls bundle_adjust. In the
# production Mons Mouton workflow we found that GCP-only BA (no matches)
# with a large number of GCPs (5M) and a stronger sigma (0.2) gives the
# best inter-camera consistency. Bundle_adjust is now expected to be run
# SEPARATELY after this script (e.g. bundle_adjust.sh or
# a site-specific variant) using the GCP file produced here.
#
# Usage:
#   dem2gcp.sh <sfsDem> <refDem> <disparity> <imageList> <cameraList> \
#     <matchPrefix> <maxDisp> <gcpFile> <currDir>
#
# sfsDem:       warped (SfS) DEM
# refDem:       reference (LOLA) DEM
# disparity:    warped-to-ref disparity (run-F.tif from correlator)
# imageList:    list of .cub files
# cameraList:   list of .json camera files
# matchPrefix:  prefix for clean match files used by dem2gcp (e.g.,
#               ba_0iter/run)
# maxDisp:      max disparity norm in pixels for GCP creation. At
#               1 m/pixel this is meters. Use ~20 for CA, raise to
#               ~30 for Mons-Mouton-scale shifts.
# gcpFile:      output GCP file path
# currDir:      working directory

set -u

if [ "$#" -lt 9 ]; then
  echo "Usage: $0 <sfsDem> <refDem> <disparity> <imageList> <cameraList> \\"
  echo "  <matchPrefix> <maxDisp> <gcpFile> <currDir>"
  exit 1
fi

sfsDem=$1; shift
refDem=$1; shift
disparity=$1; shift
imageList=$1; shift
cameraList=$1; shift
matchPrefix=$1; shift
maxDisp=$1; shift
gcpFile=$1; shift
currDir=$1; shift
cd $currDir

# Optional env var GCP_SIGMA (default 1.0 - matches ASP doc default
# and most prior projects). Set higher (e.g. 5) when GCPs have known
# transform-introduced uncertainty (e.g. when matches.gcp pairs with
# a trans_gcp run that uses sigma 5).
gcpSigma=${GCP_SIGMA:-1.0}

echo sfsDem=$sfsDem
echo refDem=$refDem
echo disparity=$disparity
echo imageList=$imageList
echo cameraList=$cameraList
echo matchPrefix=$matchPrefix
echo maxDisp=$maxDisp
echo gcpFile=$gcpFile
echo currDir=$currDir

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022

mkdir -p $(dirname $gcpFile)
out=output_$(basename $gcpFile .gcp).txt
echo "Writing log to: $out"
/bin/rm -fv $out

# Run dem2gcp with clean matches.
# --gcp-sigma 1.0 aligns with ASP documentation and our production
# experience. The Mons Mouton work briefly used 0.2 at creation time
# but ended up re-sigma'd to 1.0 for BA. Per-GCP pull is moderate;
# total constraint comes from the large --max-num-gcp count.
# --max-num-gcp 5000000 was the MM-validated value for inter-camera
# consistency; smaller counts (~500K-2M) were insufficient.
dem2gcp                                     \
  --warped-dem $sfsDem                      \
  --ref-dem $refDem                         \
  --warped-to-ref-disparity $disparity      \
  --image-list $imageList                   \
  --camera-list $cameraList                 \
  --clean-match-files-prefix ${matchPrefix} \
  --max-pairwise-matches 5000               \
  --gcp-sigma $gcpSigma                     \
  --max-disp $maxDisp                       \
  --max-num-gcp 5000000                     \
  --output-gcp ${gcpFile}                   \
  >> $out 2>&1
