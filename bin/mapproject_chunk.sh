#!/bin/bash

# Mapproject a list of images. Camera resolution has two modes:
#   - Glob mode (default): camera for image id F is resolved via
#     "ls ${baPrefix}*${F}*.json". Cameras must share one dir and prefix.
#   - List mode (optional 8th arg): cameraList is a paired list where
#     line N matches imageList line N exactly. Use when cameras come
#     from multiple dirs or naming schemes.
# The output is written to $mapDir. The images (or image ids) are one per line
# in the input list, and the line can have other items too, separated by spaces.
# Supports LRO NAC, OHRC, CTX, and general image paths.
#
# Env vars:
#   TR        - fixed grid resolution in meters/pixel (e.g. TR=0.5).
#   TR_COL    - column index of the image list holding a per-image GSD. When
#               set, each frame is mapprojected at --tr <that GSD> (native-
#               resolution mode) and the output is named <id>.map.tif. When
#               both TR and TR_COL are unset, the legacy single grid --tr 1
#               is used (output named <id>.cal.echo.map.tr1.tif).
#   PROJWIN   - optional target projection window (e.g. "xmin ymin xmax ymax").
#               When unset, maps the full image onto the DEM.
#   PROCESSES - number of worker processes per node (default 10).
#   THREADS   - number of threads per process.
#   TILE_SIZE - tile size for mapproject (default 2048).
#   NO_MOSAIC - when set, skip the per-chunk dem_mosaic --max step.
#   IMG_DIR / IMG_EXT - input image dir and extension (defaults img / .cal.echo.cub).
#   EXTRA_OPTS - any additional flags forwarded to mapproject.

if [ "$#" -lt 7 ]; then
  echo "Usage: $0 dem.tif imageList.txt beg end baPrefix mapDir currDir [cameraList.txt]"
  exit 1
fi
dem=$1; shift
imageList=$1; shift
beg=$1; shift
end=$1; shift
baPrefix=$1; shift
mapDir=$1; shift
currDir=$1; shift
# Optional 8th arg. If not given, $1 is unset; assigning leaves it empty.
cameraList=$1
cd "$currDir"

echo "dem=$dem"
echo "imageList=$imageList"
echo "beg=$beg"
echo "end=$end"
echo "baPrefix=$baPrefix"
echo "mapDir=$mapDir"
echo "currDir=$currDir"
if [ -z "$cameraList" ]; then
  echo "cameraList=(none, using baPrefix glob)"
else
  echo "cameraList=$cameraList"
fi

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
export ASPROOT=${ASPROOT:-$HOME/projects/BinaryBuilder/StereoPipeline}
export PATH=$ASPROOT/bin:$ASPROOT/libexec:$ISISROOT/bin:$PATH
export GDAL_DATA=$ASPROOT/share/gdal PROJ_DATA=$ASPROOT/share/proj PROJ_LIB=$ASPROOT/share/proj
umask 022
ulimit -c 0

mkdir -p "${mapDir}"

out="output_${mapDir}_${beg}_${end}.txt"
echo "Will write the output to $out"

rm -f "$out"

# Hide all job output from the PBS console (qsub spools -o / -j oe and
# dislikes a flood). Send everything from here on to this per-batch log in
# the work dir. Each batch has its own $out (named by beg/end).
exec >> "$out" 2>&1

maps=""

idx=0
for raw_entry in $(cat "$imageList" | ~/bin/print_line_range.pl "$beg" "$end" | ~/bin/print_col.pl 1); do

  # Extract base identifier. Support LRO NAC pattern M<digits><L|R>E as well as general basenames (OHRC, CTX, etc.)
  if [[ "$raw_entry" =~ (M[0-9]+[LR]E) ]]; then
    f="${BASH_REMATCH[1]}"
  else
    b=$(basename "$raw_entry")
    f="${b%.*}"
  fi

  # Determine image file path: use directly if it exists on disk, else construct
  if [ -f "$raw_entry" ]; then
    img="$raw_entry"
  elif [ -f "${currDir}/$raw_entry" ]; then
    img="${currDir}/$raw_entry"
  else
    img="${IMG_DIR:-img}/$f${IMG_EXT:-.cal.echo.cub}"
  fi

  # Map name and per-image resolution:
  # 1. TR env var (e.g. TR=0.5 or TR=1.0)
  # 2. TR_COL env var (read per-image GSD from column)
  # 3. Default: legacy --tr 1
  if [ -n "$TR" ]; then
    tr_opt="--tr $TR"
    map="${mapDir}/${f}.map.tif"
  elif [ -n "$TR_COL" ]; then
    gsd=$(sed -n "$((beg + idx + 1))p" "$imageList" | ~/bin/print_col.pl "$TR_COL")
    tr_opt="--tr $gsd"
    map="${mapDir}/${f}.map.tif"
  else
    tr_opt="--tr 1"
    map="${mapDir}/${f}.cal.echo.map.tr1.tif"
  fi

  # Target projection window (extent): optional via PROJWIN env var
  projwin_opt=""
  if [ -n "$PROJWIN" ]; then
    projwin_opt="--t_projwin $PROJWIN"
  fi

  # Camera resolution
  if [ -n "$cameraList" ]; then
    cam=$(sed -n "$((beg + idx + 1))p" "$cameraList")
    if [ ! -f "$cam" ] && [ -f "${currDir}/$cam" ]; then
      cam="${currDir}/$cam"
    fi
  else
    cam=$(ls ${baPrefix}*${f}*.json 2>/dev/null | head -n 1)
  fi
  ((idx=idx+1))

  echo "img=$img cam=$cam map=$map" >> "$out"

  # Skip if image does not exist
  if [ ! -f "$img" ]; then
    echo "Skip missing image: $img" >> "$out"
    continue
  fi

  # Skip if camera does not exist
  if [ -z "$cam" ] || [ ! -f "$cam" ]; then
    echo "Skip missing camera: $cam" >> "$out"
    continue
  fi

  maps="$maps $map"

  # Skip existing non-empty map
  if [ -s "$map" ]; then
    echo "Skip existing: $map" >> "$out"
    continue
  fi

  echo "Will create: $map" >> "$out"
  tile_opt="--tile-size ${TILE_SIZE:-2048}"
  proc_opt="--processes ${PROCESSES:-10}"
  threads_opt=""
  if [ -n "$THREADS" ]; then
    threads_opt="--threads $THREADS"
  fi

  if ! mapproject $tile_opt $proc_opt $threads_opt $tr_opt $projwin_opt $EXTRA_OPTS \
      "$dem" "$img" "$cam" "$map" >> "$out" 2>&1; then
    echo "Warning: mapproject failed for $img" >> "$out"
    rm -f "$map"
    rm -rf "${map%.tif}_tif_tiles"
    continue
  fi

  if [ -s "$map" ]; then
    stereo_gui --create-image-pyramids-only "$map" >> "$out" 2>&1 || true
  fi

done

# Per-chunk max-lit mosaic. Skipped in native-resolution mode (NO_MOSAIC),
# where frames are on differing grids and a per-chunk max-mosaic is moot.
if [ -n "$NO_MOSAIC" ]; then
  echo "NO_MOSAIC set: skipping per-chunk dem_mosaic" >> "$out"
  exit 0
fi

# Collect existing non-empty maps
mapList=${mapDir}/map_list_${beg}_${end}.txt
/bin/rm -fv "$mapList"
for map in $maps; do
  if [ -s "$map" ]; then
    echo "$map" >> "$mapList"
  fi
done

if [ ! -s "$mapList" ]; then
  echo "No valid maps in chunk, skipping per-chunk dem_mosaic" >> "$out"
  exit 0
fi

mosaic=${mapDir}/max_mosaic_${beg}_${end}.tif

# Skip if mosaic exists
if [ -s "$mosaic" ]; then
  echo "Skip existing: $mosaic" >> "$out"
  exit 0
fi

dem_mosaic --threads $(nproc) --max --dem-list "$mapList" -o "$mosaic" >> "$out" 2>&1
stereo_gui --create-image-pyramids-only "$mosaic" >> "$out" 2>&1



