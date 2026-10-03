#!/bin/bash
# Generic max-lit mosaic: dem_mosaic --max on a caller-prepared list.
# Supersedes max_lit_full.sh and max_lit_clean.sh (2026-04-15).
#
# Usage: max_lit.sh <list> <output> [<threads>]
#
# <list>    text file, one TIF path per line
# <output>  output tif path
# <threads> optional, default 28
#
# Examples:
#   # Full-site: merge all per-tile max_lits
#   ls map_tiles_v1/MM_1m_lola.tile.*/max_lit_all.tif > /tmp/full.txt
#   bash max_lit.sh /tmp/full.txt map_tiles_v1/max_lit_full.tif
#
#   # Per-tile clean: exclude bad ids from a tile's mapproj dir
#   cd map_tiles_v1/MM_1m_lola.tile.7.5
#   ls *.ech.map.tr1.tif | grep -v thresh | grep -Ev 'M1138776017LE|M1223593164LE' > clean.txt
#   bash max_lit.sh clean.txt max_lit_all_clean.tif

set -e
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <list> <output> [<threads>]"
    exit 1
fi
list=$1
output=$2
threads=${3:-$(nproc)}

export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
s=StereoPipeline
export PATH=${ASPROOT:-$HOME/projects/BinaryBuilder/$s}/bin:$ISISROOT/bin:$PATH
umask 022

# Under PBS, cd to submit dir so log lands next to the lists/ the user
# prepared, not in $HOME. Harmless when not under PBS.
if [ -n "$PBS_O_WORKDIR" ]; then
    cd "$PBS_O_WORKDIR"
fi

out=output_$(basename "$output" .tif).txt
n=$(wc -l < "$list")
echo "max_lit: $n inputs -> $output (threads=$threads)"
echo "log:    $(pwd)/$out"
dem_mosaic --threads $threads --max --dem-list "$list" -o "$output" \
    > "$out" 2>&1
echo "done: $output"
