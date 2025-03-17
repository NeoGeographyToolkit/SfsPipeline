#!/bin/bash
# Enable stepwise debugging if DEBUG is set to "true"
if [[ "$DEBUG" == "true" ]]; then
    trap '(read -p "[$BASH_SOURCE:$LINENO] $BASH_COMMAND ")' DEBUG
fi
# define usage
USAGE="DEM=/path/to/dem.tif;IMAGE_PAIR_LIST=/path/to/list.txt;CAMERA_PAIR_LIST=/path/to/list.txt $0"
# Ensure a DEM was provided
if [ -z "$DEM" ]; then
    echo "Error: DEM is not set. Use $USAGE"
    exit 1
fi
echo "DEM file: $DEM"
# Ensure a pair list file is provided (simply left and right map projected image file paths seperated by a space)
if [ -z "$IMAGE_PAIR_LIST" ]; then
    echo "Error: IMAGE_PAIR_LIST is not set. Use $USAGE"
    exit 1
fi
echo "Image Pair list file: $IMAGE_PAIR_LIST"
# similar list this time with the bundle adjust prefix and .adjusted_state.json postfix for the adjusted CSM models
if [ -z "$CAMERA_PAIR_LIST" ]; then
    echo "Error: CAMERA_PAIR_LIST is not set. Use $USAGE"
    exit 1
fi
echo "Camera Pair list file: $CAMERA_PAIR_LIST"
##############################################
# source asap environment
source init_asap.sh
# echo out ISISDATA and ISISROOT
echo ISIS data is $ISISDATA 
echo ISIS root is $ISISROOT
# echo out PATH
echo PATH is $PATH
##############################################
# Create a temp file
TMPFILE=$(mktemp /home7/aannex/launch_stereo_cmds.XXXXXX)
# Ensure cleanup on exit or error
trap 'rm -f "$TMPFILE"' EXIT
# Generate commands dynamically and store in temp file
{
    trap '' DEBUG
    while read LIMG RIMG LCAM RCAM; do
        echo "export SUBMIT=true; export NOSLEEP=true; export DEM=$DEM; export LIMG=$LIMG; export RIMG=$RIMG; export LCAM=$LCAM; export RCAM=$RCAM; run_individual_stereo.pbs" >> "$TMPFILE";
        # okay 
    done < <(paste $IMAGE_PAIR_LIST $CAMERA_PAIR_LIST)
    #
    if [[ "$DEBUG" == "true" ]]; then
        trap '(read -p "[$BASH_SOURCE:$LINENO] $BASH_COMMAND ")' DEBUG
    fi
}
# log we are about to start 
echo "launching jobs"
if [[ -z "$DEBUG" && -n $SUBMIT ]]; then 
    # Launch each job with Qsub
    while IFS= read -r line; do
        eval "$line"
        sleep 1
    done < "$TMPFILE"
else
    # we are in debug mode so just log out the commands that would
    # have been given the parallel
    cat "$TMPFILE"
fi
# we are now done!
echo "Job finished at $(date)"