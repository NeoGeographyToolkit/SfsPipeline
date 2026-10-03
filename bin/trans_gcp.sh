#!/bin/bash

# Transform existing GCP files from a warped-DEM frame to a reference-DEM
# frame via a precomputed warped->ref disparity. Wrapper around dem2gcp in
# its --input-gcp-list mode (no new match-derived GCPs, only transformation
# of the supplied GCP triangulated points).
#
# See ASP docs: dem2gcp.rst, section "Transforming existing GCP files"
# (https://stereopipeline.readthedocs.io tools/dem2gcp).
#
# Use case in this repo: take per-image GCPs produced by
# sfs_sim_align.sh (or its batched form
# batch_sfs_sim.sh), which are measured against the SfS DEM,
# and transform their ground positions to the LOLA frame via the SfS->LOLA
# disparity from dense_correlator.sh. The output is one
# merged GCP file in LOLA coords, ready for bundle_adjust.
#
# Usage:
#   trans_gcp.sh <inputGcpList> <sfsDem> <refDem> <disparity> \
#                <imageList> <cameraList> <gcpFile> <currDir>
#
#   inputGcpList   text file, one GCP file path per line
#   sfsDem         warped DEM (the SfS DEM the input GCPs were measured against)
#   refDem         reference DEM (LOLA)
#   disparity      warped-to-ref disparity (run-F.tif from
#                  dense_correlator.sh)
#   imageList      list of image (cub) paths that the input GCPs reference;
#                  paths must match what is stored in the GCP files
#   cameraList     list of camera files paired with imageList
#   gcpFile        output GCP file (LOLA-frame ground coords)
#   currDir        working dir (cd here first)
#
# Optional env vars:
#   GCP_SIGMA      sigma assigned to output GCPs in meters (default 5.0)
#   MAX_NUM_GCP    max GCP rows to write (default 5000000)
#   MAX_DISP       drop input GCP if disparity magnitude exceeds this
#                  pixel value (default 30; site-dependent)
#   SEARCH_LEN     DEM pixels to search around a GCP for a valid
#                  disparity, when local pixel is invalid (default 3)

set -u

if [ "$#" -lt 8 ]; then
    echo "Usage: $0 <inputGcpList> <sfsDem> <refDem> <disparity> \\"
    echo "  <imageList> <cameraList> <gcpFile> <currDir>"
    exit 1
fi

inputGcpList=$1; shift
sfsDem=$1; shift
refDem=$1; shift
disparity=$1; shift
imageList=$1; shift
cameraList=$1; shift
gcpFile=$1; shift
currDir=$1; shift
cd $currDir

gcpSigma=${GCP_SIGMA:-5.0}
maxNumGcp=${MAX_NUM_GCP:-5000000}
maxDisp=${MAX_DISP:-30}
searchLen=${SEARCH_LEN:-3}

echo inputGcpList=$inputGcpList
echo sfsDem=$sfsDem
echo refDem=$refDem
echo disparity=$disparity
echo imageList=$imageList
echo cameraList=$cameraList
echo gcpFile=$gcpFile
echo currDir=$currDir
echo gcpSigma=$gcpSigma
echo maxNumGcp=$maxNumGcp
echo maxDisp=$maxDisp
echo searchLen=$searchLen

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

# --max-pairwise-matches 0 disables match-derived GCP generation. Only
# the points from --input-gcp-list are emitted, each with its ground
# position remapped via the disparity to the reference DEM.
dem2gcp                                      \
    --warped-dem $sfsDem                     \
    --ref-dem $refDem                        \
    --warped-to-ref-disparity $disparity     \
    --image-list $imageList                  \
    --camera-list $cameraList                \
    --input-gcp-list $inputGcpList           \
    --max-pairwise-matches 0                 \
    --max-num-gcp $maxNumGcp                 \
    --gcp-sigma $gcpSigma                    \
    --max-disp $maxDisp                      \
    --search-len $searchLen                  \
    --output-gcp ${gcpFile}                  \
    >> $out 2>&1
