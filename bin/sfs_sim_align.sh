#!/bin/bash

# Mapproject onto the SfS DEM, find the simulated image, then align and generate
# GCPs, and update the camera with GCPs using bundle_adjust.

if [ "$#" -lt 6 ]; then
    echo "Usage: $0 imageId sfsDem imgDir baDir simDir currDir [measMap] [--gcp-only]"
    echo "Example: $0 M1105304585RE sfs_v2/sfs_dem.tif img ba_htdem_fix sfs_sim $(pwd)"
    echo "If measMap is provided, skip mapprojection and use this file instead."
    echo "If --gcp-only is passed, stop after gcp_gen (skip BA/re-mapproject)."
    exit 1
fi

imageId=$1; shift
sfsDem=$1; shift
imgDir=$1; shift
baDir=$1; shift
simDir=$1; shift
currDir=$1; shift
existingMeasMap=""
gcpOnly=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --gcp-only) gcpOnly=1 ;;
        *) existingMeasMap="$1" ;;
    esac
    shift
done
cd $currDir

# EXPOSURES_PREFIX is REQUIRED. Without per-image exposures the sfs
# --save-sim-intensity-only step uses its default starting exposure
# (~1.0) and does not iterate to refine it, so darker images render
# as blank sim (all zeros) -> image_align finds no IPs and no GCP
# can be made. Run sfs_exposures.sh first (or have
# Andrew s exposures consolidated to one file) and point this var at
# the prefix such that <prefix>-exposures.txt is the file.
if [ -z "${EXPOSURES_PREFIX:-}" ]; then
    echo "ERROR: EXPOSURES_PREFIX env var must be set (path prefix"
    echo "       such that <prefix>-exposures.txt is the file)."
    echo "       Example: export EXPOSURES_PREFIX=sfs_exp/run"
    exit 1
fi
if [ ! -f "${EXPOSURES_PREFIX}-exposures.txt" ]; then
    echo "ERROR: EXPOSURES_PREFIX=${EXPOSURES_PREFIX} but"
    echo "       ${EXPOSURES_PREFIX}-exposures.txt does not exist."
    exit 1
fi

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022 

# Create output directory and log file
mkdir -p $simDir
out=${simDir}/output_log_${imageId}.txt
rm -fv $out
echo "Writing log to: $out"

# Look up the image in imgDir. Must end with cub.
inputCub=$(ls $imgDir/${imageId}*.cub 2>/dev/null)

if [ -z "$inputCub" ] || [ ! -f "$inputCub" ]; then
    echo "Error: Could not find image file for image ID $imageId in $imgDir"
    exit 1
fi

# Look up the camera
inputCam=$(ls $baDir/*${imageId}*.json 2>/dev/null)

if [ -z "$inputCam" ] || [ ! -f "$inputCam" ]; then
    echo "Error: Could not find camera file for image ID $imageId in $baDir"
    exit 1
fi

echo "Image ID: $imageId"
echo "DEM: $sfsDem"
echo "Input image: $inputCub"
echo "Input cam: $inputCam"

# Sanity: image, camera, and (if provided) existing mapproj must all
# share the same imageId in their filenames.
for f in "$inputCub" "$inputCam" "$existingMeasMap"; do
    if [ -n "$f" ] && [[ "$(basename "$f")" != *"${imageId}"* ]]; then
        echo "ERROR: file '$f' does not contain imageId '$imageId' in its name."
        exit 1
    fi
done

# Define intermediate filenames
measMap=${simDir}/${imageId}.meas.map.tif
alignPrefix=${simDir}/run-align-${imageId}
alignFile=${simDir}/${imageId}_align.tif
gcpFile=${simDir}/${imageId}_gcp.gcp
gcpBaPrefix=${simDir}/ba-${imageId}
alignMap=${simDir}/${imageId}.align.map.tif

# Wipe per-image intermediate match/vwip files on every exit path
# (early skip, failure, or success). Keeps disk usage in check on shared
# filesystems with quotas. -transform.txt and the .gcp / .tif outputs
# fall outside the glob and are preserved.
cleanup_intermediates() {
    # Only wipe via a non-empty prefix. An empty prefix would let the glob
    # match unrelated *.vwip/*.match files in the working directory.
    [ -n "$alignPrefix"  ] && rm -fv "${alignPrefix}"*.vwip  "${alignPrefix}"*.match  2>/dev/null
    [ -n "$gcpBaPrefix" ] && rm -fv "${gcpBaPrefix}"*.vwip "${gcpBaPrefix}"*.match 2>/dev/null
}
# Disabled by default - we want to keep matches/vwip for inspection.
# Re-enable the trap below for very large batches (e.g. Mons-style
# multi-thousand-image runs) where the .vwip / .match clutter eats disk.
# trap 'cleanup_intermediates >> "$out" 2>&1' EXIT

# Threshold (in pixels). Below this, skip GCP/BA/re-mapproject.
# Can be overridden via env var ALIGN_THRESH (e.g., huge value for verify
# runs that should always exit after image_align).
alignThresh=${ALIGN_THRESH:-2.0}

# Shadow threshold for sfs sim. sfs default is -1 (off). Without
# shadow masking, the per-image exposure init in sfs (the
# imgmean/refmean/albedo ratio in calcExposureHazeSkipImages,
# SfsImageProc.cc) sees zero-reflectance shadow pixels flooding the
# means and can return "Skipped image" for any image whose footprint
# is mostly in shadow (sun near or below horizon). The downstream
# rendered sim is then all zeros and image_align fails with 0 IPs.
# Setting --shadow-threshold matches the convention in
# sfs_exposures.sh (0.005) and parallel_sfs.sh. EXPOSURES_PREFIX is
# the stronger guard (bypasses the init via the "do not overwrite if
# supplied" branch in sfs.cc line ~791), but setting shadow-threshold
# is consistent and defensive.
shadowThresh=${SHADOW_THRESHOLD:-0.005}

{ # Start output redirection block

# If an existing mapproj image was provided, use it directly
echo "1. Mapprojecting measured image onto DEM"
if [ -n "$existingMeasMap" ] && [ -f "$existingMeasMap" ]; then
    echo "Using provided mapproj image: $existingMeasMap"
    measMap="$existingMeasMap"
elif [ -f "$measMap" ]; then
    echo "Measured map $measMap already exists, skipping mapproject"
    touch "$measMap"
else
    # Reduced processes/threads to avoid oversubscription when this script
    # is called many times in parallel (e.g., 8 parallel jobs per node).
    mapproject --tr 1.0 --processes 4 --threads 4 \
        "$sfsDem"       \
        "$inputCub"     \
        "$inputCam"     \
        "$measMap"
fi

echo "2. Producing simulated intensity image"
# If the sim image already exists, skip. This will fail when there are multiple
# files, and that's on purpose. There must be only one file.
simMap=$(ls ${simDir}/*${imageId}*sim-intensity.tif 2>/dev/null)
# If nonempty and exists
if [ ! -z "$simMap" ] && [ -f "$simMap" ]; then
    echo "Simulated map $simMap already exists, skipping sfs"
    # Touch it up though to redo the alignment and gcp steps
    touch "$simMap"
else
    sfs -i "$sfsDem"                              \
        --save-sim-intensity-only                 \
        --image-exposures-prefix $EXPOSURES_PREFIX \
        --shadow-threshold $shadowThresh          \
        "$inputCub"                               \
        "$inputCam"                               \
        --ref-map "$measMap"                      \
        -o "${simDir}/run"
fi

# Resolve the specific sim map filename generated by sfs
simMap=$(ls ${simDir}/*${imageId}*sim-intensity.tif 2>/dev/null)
if [ ! -f "$simMap" ]; then
    echo "Error: Could not find generated simulation map"
    exit 1
fi
echo "simMap=$simMap"

# Align the meas image to the sim one. Note how the sim one is specified first.
# This is the same convention used in pc_align. This will print the amount of
# misalignment in pixels as the alignment transform, which is a very valuable
# measure. We use a translation-only transform so we can easily see the shift.
echo "3. Aligning measured map to simulated map"
image_align                           \
    --ip-detect-method 0              \
    --inlier-threshold 50             \
    --ip-per-tile 2500                \
    --ip-per-image 0                  \
    --alignment-transform translation \
    "$simMap"                         \
    "$measMap"                        \
    --output-prefix "$alignPrefix"    \
    -o "$alignFile"

# Parse the alignment shift magnitude from the transform file.
# File format:
#   1 0 <x_shift>
#   0 1 <y_shift>
#   0 0 1
# If --gcp-only is passed, the threshold check is skipped and gcp_gen
# runs for all images.
alignXForm=${alignPrefix}-transform.txt
if [ "$gcpOnly" -ne 1 ]; then
    if [ -f "$alignXForm" ]; then
        shift_mag=$(awk 'NR==1 {dx=$3} NR==2 {dy=$3} END {print sqrt(dx*dx+dy*dy)}' "$alignXForm")
        echo "Alignment shift magnitude: $shift_mag px"
        small=$(awk -v s="$shift_mag" -v t="$alignThresh" 'BEGIN {print (s<t) ? 1 : 0}')
        if [ "$small" -eq 1 ]; then
            echo "Shift $shift_mag < $alignThresh px: image already aligned, stopping."
            exit 0
        fi
        echo "Shift $shift_mag >= $alignThresh px: proceeding with GCP/BA/re-mapproject."
    else
        # image_align did not produce a transform (no matches found). Stop.
        echo "No transform file from image_align: assume matching failed, stopping."
        exit 0
    fi
fi

# Form GCP with these visually similar images. Here, the image to align to
# is passed in as the orthoimage. Here will use --gcp-sigma 1, as the uncertainty
# in gcp is about 1 meter, which is the image resolution.
echo "4. Generating GCPs"
# Use the same output prefix as image_align so gcp_gen reuses cached matches
# instead of rematching sim vs meas from scratch.
gcp_gen                             \
    --ip-detect-method 0            \
    --inlier-threshold 50           \
    --ip-per-image 0                \
    --ip-per-tile 2500              \
    --gcp-sigma 1.0                 \
    --camera-image "$inputCub"      \
    --mapproj-image "$measMap"      \
    --ortho-image "$simMap"         \
    --dem "$sfsDem"                 \
    --output-prefix "$alignPrefix"  \
    -o "$gcpFile"

# In GCP-only mode, stop here - GCP file is the output
if [ "$gcpOnly" -eq 1 ]; then
    echo "GCP-only mode: stopping after gcp_gen."
    exit 0
fi

echo "5. Running Bundle Adjust with generated GCPs"
bundle_adjust   \
    "$inputCub" \
    "$inputCam" \
    "$gcpFile"  \
    -o "$gcpBaPrefix"

alignCam=$(ls $gcpBaPrefix*.json 2>/dev/null)
# Must exist
if [ ! -f "$alignCam" ]; then
    echo "Error: Could not find aligned camera file"
    exit 1
fi
echo alignCam=$alignCam

# Mapproject with the aligned camera.
# Reduced processes/threads to avoid oversubscription when this script
# is called many times in parallel (e.g., 8 parallel jobs per node).
mapproject --tr 1.0 --processes 4 --threads 4 \
    "$sfsDem"       \
    "$inputCub"     \
    "$alignCam"     \
    "$alignMap"
    
echo alignMap=$alignMap
} >> $out 2>&1
