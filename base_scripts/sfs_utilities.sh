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

function get_largest_component_images() {
    # print out the sorted largest components as a single column list
    cat $1 | jq  -r '.["components"][0][]' | sort
}

function filter_remove_if_either_side_matches() {
    local pairs_file="$1"
    local elements_file="$2"

    awk 'NR==FNR { seen[$1]; next } { if (!($1 in seen) && !($2 in seen)) print }' "$elements_file" "$pairs_file"
}

function filter_keep_if_both_sides_match() {
    local pairs_file="$1"
    local elements_file="$2"

    # Turn list into a lookup table
    awk 'NR==FNR { seen[$1]; next } { if ($1 in seen && $2 in seen) print }' "$elements_file" "$pairs_file"
}

function to_lerc_cog() {
    in_name="$1"
    if [[ -z "$2" ]]; then
        out_name="${in_name%.tif}.lerc.tif"
    else
        out_name="$2"
    fi
    if [[ -z "$3" ]]; then
        PREC=0.0001
    else
        PREC="$3"
    fi
    gdal_translate --config GDAL_NUM_THREADS 8 -co NUM_THREADS=8 -co COMPRESS=LERC_DEFLATE -co MAX_Z_ERROR="$PREC" -co PREDICTOR=3 -ot Float32 -of COG "$in_name" "$out_name"
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

function collect_geojson_stream() {
    local dir="$1"
    local postfix="${2:-.geojson}"

    # Print opening of the FeatureCollection
    printf '{"type":"FeatureCollection","features":['

    local first=1
    # find + xargs -n1 ensures we feed one file at a time
    find "$dir" -maxdepth 1 -type f -name "*$postfix" -print0 \
      | xargs -0 -n1 jq -c '.features[]' \
      | while IFS= read -r feat; do
          if (( first )); then
            printf '%s' "$feat"
            first=0
          else
            printf ',%s' "$feat"
          fi
        done

    # Print closing bracket
    printf ']}'
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

function geojsonld_to_geojson() {
    # given a line delimited geojson file, conf
    ogr2ogr -of GeoJSON $2 $1
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


function extract_disparity_bands() {
    # pretty much just https://stereopipeline.readthedocs.io/en/latest/tools/image_calc.html#extract-disparity-bands-respecting-invalid-disparities
    disp_file="$1"
    if [[ -z "$2" ]]; then
        MAX_DISP=1e+6
    else
        MAX_DISP=$2
    fi

    basename="${disp_file%.tif}"
    
    for b in 1 2 3; do
        gdal_translate -b $b $disp_file ${basename}_b${b}.vrt
    done

    for b in 1 2; do
      image_calc -c "(var_0 + $MAX_DISP)*var_1 - $MAX_DISP" \
      --output-nodata-value -$MAX_DISP          \
      ${basename}_b${b}.vrt ${basename}_b3.vrt                    \
      -o ${basename}_b${b}_nodata.tif
      to_lerc_cog ${basename}_b${b}_nodata.tif
      rm ${basename}_b${b}_nodata.tif
    done

    for b in 1 2 3; do
        rm ${basename}_b${b}.vrt
    done

}

function blur_to_lola() {
    # blur a sfs dem to match a 5mpp lola dem in terms of quality
    in_dem="$1"
    if [[ -z "$2" ]]; then
        sigma=4
    else
        sigma=$2
    fi
    out_dem="${in_dem%.tif}.blur.tif"
    tmp_5dem="_tmp_${in_dem%.tif}_5m.tif"
    tmp_5dem_blur="_tmp_${in_dem%.tif}_5m_blur.tif"
    dem_mosaic --tr 5.0 "$in_dem" -o "$tmp_5dem" 
    dem_mosaic --dem-blur-sigma "$sigma" "$tmp_5dem" -o "$tmp_5dem_blur"
    gdal_translate -tr 1 1 -r cubic "$tmp_5dem_blur" "$out_dem"
    rm "$tmp_5dem_blur"
    rm "$tmp_5dem"
    echo "$out_dem"
}

function hillshade_dem() {
    # function to simplify hillshading to keep the altitude consistent
    in_dem="$1"
    out_dem="${in_dem%.tif}.h.tif"
    gdaldem hillshade -of COG -alt 15 -z 1 "$in_dem" "$out_dem"
}

function hill_shade_align(){
    echo "warning! be sure to have blured your sfs dem!"
    sleep 5
    ref=$(realpath "$1")
    src=$(realpath "$2")
    echo "ref: $ref"
    echo "src: $src"
    pc_align --hillshade-options '--cache-size-mb 4096 --azimuth 300 --elevation 20 --align-to-georef' --ipmatch-options '--debug-image --inlier-threshold 100 --ransac-iterations 10000 --ransac-constraint similarity' --cache-size-mb 4096 --max-displacement -1 --max-num-reference-points 1000 --max-num-source-points 1000 --initial-transform-from-hillshading similarity --num-iterations 0 $ref $src -o hill_align/run 
}

function apply_transform() {
    transform="$1"
    ref="$2"
    src="$3"
    # I think we need to apply the normal "non inverted transform" here and we need to transform the src points
    pc_align --cache-size-mb 4096 --save-transformed-source-points --max-num-reference-points 1000 --max-num-source-points 1000 --max-displacement -1 --num-iterations 0 --initial-transform "$transform" "$ref" "$src" -o transformed/run
    echo "done! you'll need to run point2dem on the correct files in ./transformed/run"
}

function apply_transform_to_ba() {
    PREFIX="$1"
    IMGS=$(realpath "$PREFIX-image_list.txt")
    CAMS=$(realpath "$PREFIX-camera_list.txt")
    TRFM=$(realpath "$2")
    OUT_PREFIX="$3"
    bundle_adjust --image-list $IMGS --camera-list $CAMS --initial-transform $TRFM --apply-initial-transform-only -o "$OUT_PREFIX"
}