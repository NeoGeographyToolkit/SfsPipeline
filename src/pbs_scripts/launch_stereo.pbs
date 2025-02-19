#!/bin/bash
# this script will use qsub to launch a bunch of stereo jobs 

# Enable stepwise debugging if DEBUG is set to "true"
if [[ "$DEBUG" == "true" ]]; then
    trap '(read -p "[$BASH_SOURCE:$LINENO] $BASH_COMMAND ")' DEBUG
fi
# define usage
USAGE="DEM=/path/to/dem.tif;INPUT_GPKG=/path/to/CUB/files/;PROJWIN_EXTENT='0 0 100 100'; $0"
# Ensure a DEM was provided
if [ -z "$DEM" ]; then
    echo "Error: DEM is not set. Use $USAGE"
    exit 1
fi
echo "DEM file: $DEM"
# Ensure an input directory is provided
if [ -z "$INPUT_GPKG" ]; then
    echo "Error: INPUT_GPKG is not set. Use $USAGE"
    exit 1
fi
echo "Path to GPKGs: $INPUT_GPKG"
# get the base file name
filenameext="${INPUT_GPKG##*/}"
LAYER_NAME=$"{filenameext%.gpkg}"
echo "\t Layername in GPKG: $LAYER_NAME"
# Ensure a projwin extent was provided
if [ -z "$PROJWIN_EXTENT" ]; then
    echo "Error: PROJWIN_EXTENT is not set. Use $USAGE"
    exit 1
fi
echo "Projection extent: $PROJWIN_EXTENT"
##############################################
# source asap environment
source init_asap.sh
# verify ogr2ogr/ogrinfo is there
# verify jq and jo is there
##############################################
# Create a temp file
TMPFILE=$(mktemp /nobackup/aannex/launch_stereo_cmds.XXXXXX)
# Ensure cleanup on exit or error
trap 'rm -f "$TMPFILE"' EXIT
# Generate commands dynamically and store in temp file
{
    trap '' DEBUG
    # use ogr2ogr to print out each Left and Right product id
    # something like
    # ogr2ogr -sql 'SELECT ORBIT_NUMBER, VOLUME_ID, PRODUCT_ID, STRFTIME("%Y%j", START_TIME) FROM buffered_1km_mons_mouton_regional' -f CSV /vsistdout/ /tmp/buffered_1km_mons_mouton_regional.gpkg
    # use GeoJSONSeq to get lines like { "type": "Feature", "properties": { "L_PRODUCT_ID": "M1141983027RE", "R_PRODUCT_ID": "M1461112282LE" }, "geometry": null }
    #ogr2ogr -sql "SELECT L_PRODUCT_ID, R_PRODUCT_ID from ${LAYER_NAME}"  -f GeoJSONSeq /vsistdout/ $INPUT_GPKG
    # or just build the command directly in the sql statement
    # below will make "qsub -v L=M1282487784RE,R=M1461112282LE loony_stereo.sh" like lines
    ogr2ogr -sql "SELECT concat('qsub -v L=', L_PRODUCT_ID, ',R=', R_PRODUCT_ID, ' loony_stereo.sh') as lr from ${filenameext%%.gpkg}"  -f CSV /vsistdout/ $INPUT_GPKG > "$TMPFILE";
    # may need to strip quotes from file but that's easy...
    if [[ "$DEBUG" == "true" ]]; then
        trap '(read -p "[$BASH_SOURCE:$LINENO] $BASH_COMMAND ")' DEBUG
    fi
}
# log we are about to start (TODO move below to new script)
echo "launching jobs"
if [[ -z "$DEBUG" ]]; then 
    # Run GNU Parallel with the temp file if not in debug mode
    if [[ $NUM_NODES -gt 1 ]]; then
        parallel --joblog pbs_launch_stereo_job.log --sshloginfile $PBS_NODEFILE  < "$TMPFILE"
    else
        parallel --joblog pbs_launch_stereo_job.log  < "$TMPFILE"
    fi
else
    # we are in debug mode so just log out the commands that would
    # have been given the parallel
    cat "$TMPFILE"
fi
# we are now done!
echo "Job finished at $(date)"