# this file needs to be sourced


function gim {                                    
  gdalinfo -stats $1 | grep -i Maximum | grep -i mean
}

function jim {
  gdalinfo $1 -stats -json | jq -c ".bands[0].metadata | .[""] + {file: \"$1\"}"
}

function check_files() {
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
  jq '{"type": "FeatureCollection", "features": [.[] | .features[]]}' --slurp "$1"/*.geojson
}

