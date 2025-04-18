# this file needs to be sourced


function gim {                                    
  gdalinfo -stats $1 | grep -i Maximum | grep -i mean
}

function jim {
    # use gdal info to get the statistics for a raster in a json object including the filename in the json 
    gdalinfo $1 -stats -json | jq -c ".bands[0].metadata | .[""] + {file: \"$1\"}"
}

function unique_from_pairs() {
    # given a list of pairs separated by space, get the unique values from the unpaired list 
    awk '{print $1; print $2}' "$1" | sort -u
}

function check_files() {
    # for each file in a list file check if it exists, return false at the first missed file
    local list_file="$1"
    while IFS= read -r file; do
        if [ ! -r "$file" ]; then
            echo "no"
            return 1
        fi
    done < "$list_file"
    echo "yes"
    return 0
}

function collect_geojson() {
    # given a folder with geojson files into 
    if [[ -z "$2" ]]; then
        POSTFIX='.geojson'
    else
        POSTFIX="$2"
    fi
    jq '{"type": "FeatureCollection", "features": [.[] | .features[]]}' --slurp "$1/"*"$POSTFIX"
}

function monitor_throughput() {
    # Check that at least two arguments are provided: filename and total expected lines.
    if [ $# -lt 2 ]; then
        echo "Usage: monitor_throughput <file> <total_lines> [interval_seconds]"
        return 1
    fi

    local file="$1"
    local total="$2"
    # Update interval (in seconds); default is 60 seconds.
    local interval="${3:-60}"

    # Check that the file exists.
    if [ ! -f "$file" ]; then
        echo "Error: File '$file' not found."
        return 1
    fi

    # Get the starting line count and current timestamp.
    local start_count
    start_count=$(wc -l < "$file")
    local start_time
    start_time=$(date +%s)

    # Function to print a simple text-based progress bar.
    progress_bar() {
        local progress=$1
        local total=$2
        local bar_width=40
        # Calculate how many characters to fill.
        local done=$(( progress * bar_width / total ))
        local left=$(( bar_width - done ))
        printf "["
        for i in $(seq 1 $done); do
            printf "#"
        done
        for i in $(seq 1 $left); do
            printf "."
        done
        printf "]"
    }

    # Monitoring loop.
    while true; do
        sleep "$interval"

        # Get the current line count and current time.
        local current
        current=$(wc -l < "$file")
        local now
        now=$(date +%s)
        local elapsed=$(( now - start_time ))
        local new_lines=$(( current - start_count ))
        
        # Calculate throughput in lines per minute.
        local lpm=0
        if [ "$elapsed" -gt 0 ]; then
            lpm=$(( new_lines * 60 / elapsed ))
        fi
        
        # Calculate throughput in lines per hour.
        local lph=$(( lpm * 60 ))

        # Calculate remaining lines and ETA (in minutes), if throughput is nonzero.
        local remaining=$(( total - current ))
        local eta="N/A"
        if [ "$lpm" -gt 0 ]; then
            eta=$(( remaining / lpm ))
        fi

        # Clear the screen for a fresh update.
        clear

        # Print statistics.
        echo "Monitoring file: $file"
        echo "Total expected lines: $total"
        echo "Time elapsed: ${elapsed} seconds"
        echo "Current line count: $current"
        echo "New lines since start: $new_lines"
        echo "Throughput: ${lpm} lines/min, ${lph} lines/hr"
        echo "Remaining lines: $remaining"
        echo "ETA: ${eta} minutes"
        echo

        # Print a simple progress bar and percentage complete.
        progress_bar "$current" "$total"
        # Calculate the percentage complete (integer).
        local percent=$(( current * 100 / total ))
        echo " $(printf "%3d" "$percent")% complete"
        echo "-----------------------------------------------------"
    done
}
