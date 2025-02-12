#!/usr/bin/env bash
# Log the PBS_NODEFILE if available
if [ -n "$PBS_NODEFILE" ]; then
    echo "Running on PBS node: $(uname -a)"
fi
##############################################
# source asap environment
source init_asap.sh
# echo out ISISDATA and ISISROOT
echo ISIS data is $ISISDATA 
echo ISIS root is $ISISROOT
# echo out PATH
echo PATH is $PATH
################################################
# Must have 1 arguments. Print usage on failure.
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <i>"
    exit 1
fi
in_img=$1
echo IN IMG is $in_img
# use asap to calibrate EDR
asap lrocnac calibrate_edr $1
# get the final cub name
ech_cub="${in_img%.IMG}.ech.cub"
# use isd_generate to generate CSM camera model using only spiceinit info from ISIS
isd_generate -i $ech_cub
# done!

