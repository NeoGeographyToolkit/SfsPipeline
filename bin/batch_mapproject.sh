#!/bin/bash
# Resolve sibling scripts relative to this one (installed bin dir).
binDir="$(cd "$(dirname "$0")" && pwd)"

# If cameraList is given, it must have the same line count and ordering
# as imageList - line N of cameraList is used for line N of imageList,
# overriding the baPrefix glob.

if [ "$#" -lt 5 ]; then
    echo "Usage: $0 dem.tif imageList.txt baPrefix mapDir currDir [cameraList.txt]"
    exit
fi
dem=$1; shift
imageList=$1; shift
baPrefix=$1; shift
mapDir=$1; shift
currDir=$1; shift
# Optional 6th arg. If not given, $1 is unset; assigning leaves it empty.
cameraList=$1
cd $currDir

echo dem=$dem
echo imageList=$imageList
echo baPrefix=$baPrefix
echo mapDir=$mapDir
echo currDir=$currDir
if [ -z "$cameraList" ]; then
    echo "cameraList=(none, using baPrefix glob)"
else
    echo "cameraList=$cameraList"
fi

# Set up the paths
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022 # needed to handle permissions
ulimit -c 0

# Run batches. CHUNK_SIZE env var overrides the default.
w=${CHUNK_SIZE:-30}
i=0
while [ 1 ]; do 
  ((beg=i*w)); ((end=i*w+w)) 
  # Stop when ans is empty
  ans=$(cat $imageList | ~/bin/print_line_range.pl $beg $end)
  if [ "$ans" = "" ]; then echo "Done with all images"; break; fi
  echo Will do list $imageList from $beg to $end with $dem in $currDir
  # Env vars for cross-machine portability and mapproject configuration:
  #   QSUB_BIN  - qsub binary path (default `qsub`; tur_ath uses
  #               /opt/pbs/bin/qsub when invoked from athfe01)
  #   MODEL     - node model (default bro_ele; tur_ath, sky_ele,
  #               cas_ait, etc supported)
  #   NCPUS     - cpus per node (default 28 for bro_ele;
  #               256 for tur_ath)
  #   WALLTIME  - walltime (default 6:00:00)
  #   CHUNK_SIZE - number of images per job (default 30)
  #   IMG_DIR / IMG_EXT - forwarded to workers (defaults img / .cal.echo.cub)
  #   TR        - fixed grid resolution in meters/pixel (e.g. TR=0.5)
  #   TR_COL    - column in imageList holding per-image GSD
  #   PROJWIN   - optional target projection window (e.g. "xmin ymin xmax ymax")
  #   PROCESSES - number of worker processes per node (default 10)
  #   THREADS   - threads per process
  #   TILE_SIZE - mapproject tile size (default 2048)
  #   NO_MOSAIC - when set, skip per-chunk dem_mosaic --max
  #   EXTRA_OPTS - any additional flags passed to mapproject
  QSUB_BIN_RES=${QSUB_BIN:-qsub}
  MODEL_RES=${MODEL:-bro_ele}
  NCPUS_RES=${NCPUS:-28}
  WALLTIME_RES=${WALLTIME:-6:00:00}
  # Build the -v list from only the variables that are actually set. The pfe
  # qsub fails with "cannot send environment with the job" if -v names an unset
  # variable, so listing all candidates unconditionally breaks every submission.
  vlist=""
  for v in IMG_DIR IMG_EXT TR TR_COL PROJWIN PROCESSES THREADS TILE_SIZE NO_MOSAIC EXTRA_OPTS; do
    eval "isset=\${$v+yes}"
    [ "$isset" = "yes" ] && vlist="${vlist:+$vlist,}$v"
  done
  vopt=""
  [ -n "$vlist" ] && vopt="-v $vlist"
  $QSUB_BIN_RES -m n -r n -N map_${beg}_${end} -q normal \
    -l walltime=$WALLTIME_RES                            \
    -W group_list=${groupName:?set groupName (PBS allocation) before submitting} -j oe -S /bin/bash               \
    -o $currDir/                                         \
    $vopt                                                \
    -l select=1:ncpus=${NCPUS_RES}:model=${MODEL_RES} -- \
   $binDir/mapproject_chunk.sh                    \
      $dem $imageList $beg $end                          \
      $baPrefix $mapDir $currDir "$cameraList"
  ((i=i+1))
  sleep 2
done
