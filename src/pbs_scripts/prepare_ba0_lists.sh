#!/bin/bash
# This script reads a list of base filenames (one per line) from stdin
# and creates three output lists containing the full filenames
# for which all three file extensions exist.

# Variable for the optional DEM parameter
append_dem=""

# # Parse command-line options for an optional parameter
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dem|-d)
      if [[ -n "$2" ]]; then
        append_dem="$2"
        shift 2
      else
        echo "Error: --dem requires a non-empty value." >&2
        exit 1
      fi
      ;;
    *)
      echo "Unknown parameter: $1" >&2
      exit 1
      ;;
  esac
done

# Helper function: returns true if the given file is either a regular file or a symlink.
is_file_or_symlink() {
  local file="$1"
  if [[ -f "$file" || -L "$file" ]]; then
    echo "true"
  else
    echo "false"
  fi
}


# Define output files for each extension type
IMAGES_LIST="$(pwd)/IMAGES.txt"
CAMERAS_LIST="$(pwd)/CAMERAS.txt"
MAPPROJ_LIST="$(pwd)/MAPPROJ_DATA.txt"
echo "$IMAGES_LIST" "$CAMERAS_LIST" "$MAPPROJ_LIST"

# Clear (or create) the output files
echo -n "" > "$IMAGES_LIST"
echo -n "" > "$CAMERAS_LIST"
echo -n "" > "$MAPPROJ_LIST"
counter=0
good=0
# Read each base name from standard input
while IFS= read -r base || [[ -n "$base" ]]; do
  # Skip empty lines, if any
  [[ -z "$base" ]] && continue
  
  # Check if files with all three extensions exist for the base name
  f_img="$(pwd)/${base}.ech.cub" 
  f_camera="$(pwd)/${base}.ech.json"
  f_mapproj="$(pwd)/${base}.ech.map.noba.tif"
  echo "$f_img"

  echo "$counter $good image $(is_file_or_symlink "$f_img") camera $(is_file_or_symlink "$f_camera") map $(is_file_or_symlink "$f_mapproj")"

  if [ "$(is_file_or_symlink "$f_img")" = "true" ] && \
      [ "$(is_file_or_symlink "$f_camera")" = "true" ] && \
      [ "$(is_file_or_symlink "$f_mapproj")" = "true" ]; then
      echo "$f_img" >> "$IMAGES_LIST"
      echo "$f_camera" >> "$CAMERAS_LIST"
      echo "$f_mapproj" >> "$MAPPROJ_LIST"
      ((good++))
  fi
  ((counter++))
done

# 
echo "lengths of lists:"
echo "IMAGES $(cat $IMAGES_LIST | wc -l)"
echo "CAMERAS $(cat $CAMERAS_LIST | wc -l)"
echo "MAPPROJ $(cat $MAPPROJ_LIST | wc -l)"
# append the dem
if [[ -n $append_dem ]]; then
    echo "$append_dem" >> "$MAPPROJ_LIST"
fi
echo "updated length of MAPPROJ:"
echo "MAPPROJ $(cat $MAPPROJ_LIST | wc -l)"
