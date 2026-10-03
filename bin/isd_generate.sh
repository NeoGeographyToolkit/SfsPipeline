#!/bin/bash
# Generate CSM ISD JSON cameras with linear reduction for a list of ISIS cubes.
#
# Usage:
#   isd_generate.sh <cub_list.txt|file.cub> [num_processes] [out_dir]
#
# If out_dir is omitted, each output JSON is written in place next to the cub
# (replacing .cub with .json).
#
# If num_processes is omitted or 1, processes are run sequentially.
# If num_processes > 1, the list is split and processed in parallel.

set -e
set -u

if [ $# -lt 1 ]; then
  echo "Usage: $0 <cub_list.txt|file.cub> [num_processes] [out_dir]"
  exit 1
fi

inputTarget="$1"
numProc="${2:-${NCPUS:-1}}"
outDir="${3:-}"

# Configure environment
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}

export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
if [ -n "${ISISROOT:-}" ]; then
  export PATH=$ISISROOT/bin:$PATH
fi

umask 022
ulimit -c 0

# Optional ephem sample rate override
EPHEM_OPT=""
if [ -n "${EPHEM_SAMPLE_RATE:-}" ]; then
  EPHEM_OPT="--ephem_sample_rate $EPHEM_SAMPLE_RATE"
fi

# Function to process a single cube
process_single_cub() {
  local cub="$1"
  local target_json="$2"

  if [ ! -f "$cub" ]; then
    echo "Warning: cube file not found: $cub" >&2
    return 1
  fi

  if [ -z "$target_json" ]; then
    target_json="${cub%.*}.json"
  fi

  # Run isd_generate with linear reduction
  isd_generate -k "$cub" "$cub" --reduction linear $EPHEM_OPT -o "$target_json"

  # Patch ALE scalar distortion coefficient for USGSCSM compatibility
  python3 -c '
import json, sys
p = sys.argv[1]
try:
  with open(p, "r") as f:
    d = json.load(f)
  od = d.get("optical_distortion", {})
  lro = od.get("lrolrocnac", {})
  coeff = lro.get("coefficients")
  if isinstance(coeff, (int, float)):
    lro["coefficients"] = [coeff]
    with open(p, "w") as f:
      json.dump(d, f, indent=2)
except Exception as e:
  sys.stderr.write(f"Warning: could not patch distortion in {p}: {e}\n")
' "$target_json"

  echo "Generated: $target_json"
}

export -f process_single_cub

if [ -n "$outDir" ]; then
  mkdir -p "$outDir"
fi

# Single cube file mode
if [[ "$inputTarget" == *.cub ]] && [ -f "$inputTarget" ]; then
  target=""
  if [ -n "$outDir" ]; then
    base=$(basename "$inputTarget" .cub)
    target="$outDir/${base}.json"
  fi
  process_single_cub "$inputTarget" "$target"
  exit 0
fi

if [ ! -f "$inputTarget" ]; then
  echo "Error: Input file not found: $inputTarget"
  exit 1
fi

totalCubs=$(grep -c . "$inputTarget" || true)
echo "===== Starting isd_generate batch at $(date) ====="
echo "List:      $inputTarget ($totalCubs items)"
echo "Processes: $numProc"
if [ -n "$outDir" ]; then
  echo "OutDir:    $outDir"
else
  echo "OutDir:    in-place next to cubes"
fi

if [ "$numProc" -le 1 ]; then
  count=0
  while read -r line; do
    cub=$(echo "$line" | awk '{print $1}')
    [ -z "$cub" ] && continue
    case "$cub" in \#*) continue ;; esac

    target=""
    if [ -n "$outDir" ]; then
      base=$(basename "$cub" .cub)
      target="$outDir/${base}.json"
    fi
    process_single_cub "$cub" "$target"
    count=$((count + 1))
  done < "$inputTarget"
  echo "===== Completed $count cubes at $(date) ====="
else
  chunkDir=$(mktemp -d -t isd_chunk_XXXXXX)
  trap 'rm -rf "$chunkDir"' EXIT INT TERM

  linesPerChunk=$(( (totalCubs + numProc - 1) / numProc ))
  split -l "$linesPerChunk" -d -a 3 "$inputTarget" "$chunkDir/chunk_"

  pids=()
  for c_file in "$chunkDir"/chunk_*; do
    (
      while read -r line; do
        cub=$(echo "$line" | awk '{print $1}')
        [ -z "$cub" ] && continue
        case "$cub" in \#*) continue ;; esac

        target=""
        if [ -n "$outDir" ]; then
          base=$(basename "$cub" .cub)
          target="$outDir/${base}.json"
        fi
        process_single_cub "$cub" "$target"
      done < "$c_file"
    ) &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    wait "$pid"
  done

  echo "===== Completed parallel isd_generate for $totalCubs cubes at $(date) ====="
fi
