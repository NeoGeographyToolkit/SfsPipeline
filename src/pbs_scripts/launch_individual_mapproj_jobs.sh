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
# Bundle Adjust prefix
if [[ -z "$BA_PREFIX" ]]; then
    export BA_PREFIX='noba'
fi
echo "Bundle Adjust Prefix: $BA_PREFIX"
# Ensure the work dir is set to something
if [[ -z "$WORKDIR" ]]; then
    # we will default to the current working directory wherever that is
    export WORKDIR="$PWD"
fi
echo "Workdir: $WORKDIR"
##############################################
# source asp environment
source init_asp.sh
# echo out ISISDATA and ISISROOT
echo ISIS data is "$ISISDATA" 
echo ISIS root is "$ISISROOT"
# echo out PATH
echo PATH is "$PATH"
##############################################
# Create a temp file
TMPFILE=$(mktemp "$WORKDIR/launch_mapproj_cmds.XXXXXX")
# Ensure cleanup on exit or error
trap 'rm -f "$TMPFILE"' EXIT
# Generate commands dynamically and store in temp file
{
    trap '' DEBUG
    while read -r IMG CAM; do
        if [[ ! -f $IMG ]]; then
            echo "Image not found!: $IMG"
            continue
        elif [[ ! -f $CAM ]]; then
            echo "Camera not found!: $CAM"
            continue
        else
            img_id=$(echo "${IMG##*/}" | cut -d. -f1)
            cam_id=$(echo "${CAM##*/}" | cut -c 5- | cut -d. -f1)
            if [[ "$img_id" != "$cam_id" ]]; then
                echo "IMG and CAM don't match!"
                echo "$img_id" "$cam_id"
            else 
                # should only get here if all files exist and match correctly
                echo "export SUBMIT=true; export NOSLEEP=true; export BA_PREFIX=$BA_PREFIX; export DEM=$DEM; export IMG=$IMG; export CAM=$CAM; export WORKDIR=$WORKDIR; run_individual_mapproj.pbs" >> "$TMPFILE";
            fi
        fi
        # okay 
    done < <(paste "$IMAGE_PAIR_LIST" "$CAMERA_PAIR_LIST")
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
        sleep 0.25
    done < "$TMPFILE"
else
    # we are in debug mode so just log out the commands that would
    # have been given the parallel
    cat "$TMPFILE"
fi
# we are now done!
echo "Job finished at $(date)"