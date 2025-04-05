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
    echo "Error: BA_PREFIX is not set. Use $USAGE"
    exit 1
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
TMPFILE=$(mktemp $WORKDIR/launch_stereo_cmds.XXXXXX)
# Ensure cleanup on exit or error
trap 'rm -f "$TMPFILE"' EXIT
# Generate commands dynamically and store in temp file
{
    trap '' DEBUG
    while read -r LIMG RIMG LCAM RCAM; do
        if [[ ! -f $LIMG ]]; then
            echo "LEFT image not found!: $LIMG"
            continue
        elif [[ ! -f $RIMG ]]; then
            echo "RIGHT image not found!: $RIMG"
            continue
        elif [[ ! -f $LCAM ]]; then
            echo "LEFT camera not found!: $LCAM"
            continue
        elif [[ ! -f $RCAM ]]; then
            echo "RIGHT camera not found!: $RCAM"
            continue
        else
            l_img_id=$(echo "${LIMG##*/}" | cut -d. -f1)
            r_img_id=$(echo "${RIMG##*/}" | cut -d. -f1)
            l_cam_id=$(echo "${LCAM##*/}" | cut -c 5- | cut -d. -f1)
            r_cam_id=$(echo "${RCAM##*/}" | cut -c 5- | cut -d. -f1)
            if [[ "$l_img_id" != "$l_cam_id" ]]; then
                echo "LEFT IMG and CAM don't match!"
                echo "$l_img_id" "$l_cam_id"
            elif [[ "$r_img_id" != "$r_cam_id" ]]; then
                echo "RIGHT IMG and CAM don't match!"
                echo "$r_img_id" "$r_cam_id"
            else 
                # should only get here if all files exist and match correctly
                echo "export SUBMIT=true; export NOSLEEP=true; export BA_PREFIX=$BA_PREFIX; export DEM=$DEM; export LIMG=$LIMG; export RIMG=$RIMG; export LCAM=$LCAM; export RCAM=$RCAM; export WORKDIR=$WORKDIR; run_individual_stereo.pbs" >> "$TMPFILE";
            fi
        fi
        # okay 
    done < <(paste "$IMAGE_PAIR_LIST" "$CAMERA_PAIR_LIST")
    # sort the TMPFILE to ensure repeatability
    sort -o "$TMPFILE"{,}
    #
    if [[ "$DEBUG" == "true" ]]; then
        trap '(read -p "[$BASH_SOURCE:$LINENO] $BASH_COMMAND ")' DEBUG
    fi
}
# log we are about to start 
echo "launching jobs"
if [[ -z "$DEBUG" && -n "$SUBMIT" ]]; then 
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