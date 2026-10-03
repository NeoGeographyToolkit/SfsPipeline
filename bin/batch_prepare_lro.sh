#!/bin/bash
# Head-node friendly batch ingest runner for LRO NAC images.
# Processes one image at a time with 1 process, 1 thread, and a 10s sleep between new images.
# Fully resumable with fast-skip logic: immediately skips already-finished products.
#
# Usage:
#   batch_prepare_lro.sh <list.txt> <out_dir> [--usgs-polar|--no-usgs-polar] [log_file]

set -u
umask 022

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <list.txt> <out_dir> [--usgs-polar|--no-usgs-polar] [log_file]"
  exit 1
fi

list_file="$1"
out_dir="$2"
polar_flag="--no-usgs-polar"
log_file="${out_dir}/ingest.log"

shift 2
while [ "$#" -gt 0 ]; do
  case "$1" in
    --usgs-polar) polar_flag="--usgs-polar" ;;
    --no-usgs-polar) polar_flag="--no-usgs-polar" ;;
    *) log_file="$1" ;;
  esac
  shift
done

mkdir -p "$out_dir"

# Find prepare_lro_nac.py
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tool=""
if [ -x "$script_dir/prepare_lro_nac.py" ]; then
  tool="$script_dir/prepare_lro_nac.py"
elif [ -x "$HOME/bin/prepare_usgs_nac.py" ]; then
  tool="$HOME/bin/prepare_usgs_nac.py"
elif command -v prepare_lro_nac.py >/dev/null 2>&1; then
  tool="$(command -v prepare_lro_nac.py)"
else
  echo "Error: Cannot find prepare_lro_nac.py"
  exit 1
fi

total=$(grep -c . "$list_file" || true)
echo "===== Batch Ingest Start: $(date) ($total products, polar=$polar_flag) =====" | tee -a "$log_file"
n=0

while read -r pid; do
  [ -z "$pid" ] && continue
  case "$pid" in \#*) continue ;; esac
  pid=$(echo "$pid" | awk '{print $1}')
  n=$((n + 1))

  final_cub="$out_dir/${pid}.cal.echo.cub"
  final_json="$out_dir/${pid}.cal.echo.json"
  if [ -f "$final_cub" ] && [ -f "$final_json" ]; then
    continue
  fi

  echo "----- [$n/$total] $pid $(date) -----" | tee -a "$log_file"
  python3 "$tool" "$polar_flag" --outdir "$out_dir" "$pid" >> "$log_file" 2>&1
  sleep 10
done < "$list_file"

echo "===== Batch Ingest Done: $(date). Output cubs: $(ls "$out_dir"/*.cub 2>/dev/null | wc -l) =====" | tee -a "$log_file"
