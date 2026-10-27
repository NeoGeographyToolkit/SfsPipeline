#!/bin/bash
# Re-spiceinit already-prepared LRO NAC .cal.echo.cub files with the USGS South
# Pole custom polar SPICE kernels, producing USGS-registered CSM cameras WITHOUT
# re-fetching or re-calibrating. Use this on cubes that were already ingested with
# the standard (vanilla) kernels (e.g. by batch_prepare_lro.sh --no-usgs-polar)
# and that appear in the USGS South Pole controlled-image list.
#
# For each product id it:
#   cp <srcDir>/<id>.cal.echo.cub <outDir>/        (vanilla cub in srcDir untouched)
#   spiceinit from=<outDir cub> spk=<polar_spk.mk> ck=<polar_ck.mk> web=false
#   isd_generate -k <cub> <cub> --reduction linear -o <cub>.json
#   patch any scalar distortion coefficient to a one-element list (USGSCSM compat)
#   cam_test sanity check (non-fatal)
#
# spiceinit rewrites only the SPICE (geometry) blobs of the cub, so the radiometric
# calibration already baked into the .cal.echo.cub is preserved. Keeping the output
# in a separate <outDir> leaves the vanilla-spiceinit cub in <srcDir> intact for the
# non-registered mapproject path.
#
# Serial, 1 process, 1 thread - head-node friendly (spiceinit web=false reads local
# kernels only, no internet, so this can also be qsubbed to a compute node).
# Resumable: skips ids whose output .json already exists and is non-trivial.
#
# Writes, in outDir, usgs_built_<idList>.txt: the ids whose registered camera built
# successfully (a non-trivial json). This is the authoritative success list, since
# a few in-window ids can still fail the polar spiceinit. Aggregate these files
# across sublists to form the fixed-camera list for bundle adjustment. The ids that
# fail are simply absent, and stay in the solve later with their plain cameras.
#
# Usage:
#   redo_spiceinit_usgs.sh <idList> <srcDir> <outDir> <workDir>
#     idList  - file of LRO NAC product ids (one per line, e.g. M123456789LE)
#     srcDir  - dir holding the already-prepared <id>.cal.echo.cub (e.g. img)
#     outDir  - dir to write the USGS-registered <id>.cal.echo.cub + .json
#     workDir - dir to cd into first (all paths are relative to it)
#
# Env overrides (same defaults as prepare_lro_nac.py; set these for your system):
#   ISISROOT   full ISIS env with spiceinit + isd_generate
#   ISISDATA   populated ISIS kernel tree, must contain lro_south/usgs_polar_*.mk
#   ASPROOT    ASP build whose bin/ wrapper runs cam_test

set -u
umask 022
ulimit -c 0

if [ "$#" -lt 4 ]; then
  echo "Usage: $0 <idList> <srcDir> <outDir> <workDir>"
  exit 1
fi

idList="$1"
srcDir="$2"
outDir="$3"
workDir="$4"
cd "$workDir" || { echo "Cannot cd to $workDir"; exit 1; }

ISISROOT="${ISISROOT:-${CONDA_PREFIX:-$HOME/miniconda3/envs/asp_deps}}"
ISISDATA="${ISISDATA:-$HOME/projects/isis3data}"
ASPROOT="${ASPROOT:-$HOME/projects/BinaryBuilder/StereoPipeline}"
export ISISROOT ISISDATA
export ALESPICEROOT="$ISISDATA"
export PATH="$ISISROOT/bin:$PATH"
export LD_LIBRARY_PATH="$ISISROOT/lib:${LD_LIBRARY_PATH:-}"

spk="$ISISDATA/lro_south/usgs_polar_spk.mk"
ck="$ISISDATA/lro_south/usgs_polar_ck.mk"
for mk in "$spk" "$ck"; do
  if [ ! -f "$mk" ]; then
    echo "ERROR: USGS polar meta-kernel missing: $mk"
    exit 1
  fi
done

mkdir -p "$outDir"

# Authoritative list of ids whose registered camera built. Named by the input
# sublist so parallel instances sharing outDir do not race on one file. Truncated
# at the start so each run regenerates the full list for its sublist.
builtList="$outDir/usgs_built_$(basename "$idList" .txt).txt"
: > "$builtList"

total=$(grep -c . "$idList" || true)
echo "redo_spiceinit_usgs: $total ids, src=$srcDir out=$outDir, $(date)"
n=0; ok=0; miss=0; fail=0
while read -r id; do
  [ -z "$id" ] && continue
  case "$id" in \#*) continue ;; esac
  id=$(echo "$id" | awk '{print $1}')
  n=$((n + 1))

  srcCub="$srcDir/$id.cal.echo.cub"
  outCub="$outDir/$id.cal.echo.cub"
  outJson="$outDir/$id.cal.echo.json"

  if [ -f "$outJson" ] && [ "$(wc -c < "$outJson")" -gt 1000 ]; then
    ok=$((ok + 1))
    echo "$id" >> "$builtList"
    continue
  fi
  if [ ! -f "$srcCub" ]; then
    echo "[$n/$total] $id: source cub missing, skipping"
    miss=$((miss + 1))
    continue
  fi

  echo "[$n/$total] $id $(date)"
  cp -f "$srcCub" "$outCub"

  if ! spiceinit from="$outCub" spk="$spk" ck="$ck" web=false > "$outDir/$id.log" 2>&1; then
    echo "  spiceinit FAILED (see $outDir/$id.log)"
    rm -f "$outCub"
    fail=$((fail + 1))
    continue
  fi

  if ! isd_generate -k "$outCub" "$outCub" --reduction linear -o "$outJson" >> "$outDir/$id.log" 2>&1; then
    echo "  isd_generate FAILED (see $outDir/$id.log)"
    rm -f "$outJson"
    fail=$((fail + 1))
    continue
  fi

  # Patch a scalar lrolrocnac distortion coefficient to a one-element list.
  python3 - "$outJson" <<'PYEOF' >> "$outDir/$id.log" 2>&1
import json, sys
p = sys.argv[1]
with open(p) as f:
    d = json.load(f)
lro = d.get("optical_distortion", {}).get("lrolrocnac", {})
c = lro.get("coefficients")
if isinstance(c, (int, float)):
    lro["coefficients"] = [c]
    with open(p, "w") as f:
        json.dump(d, f, indent=2)
    print("patched scalar distortion coefficient")
PYEOF

  # Non-fatal sanity check through the ASP bin/ wrapper (handles its own libs).
  "$ASPROOT/bin/cam_test" --image "$outCub" --cam1 "$outCub" --cam2 "$outJson" \
    --sample-rate 5000 >> "$outDir/$id.log" 2>&1 || true

  if [ -f "$outJson" ] && [ "$(wc -c < "$outJson")" -gt 1000 ]; then
    ok=$((ok + 1))
    echo "$id" >> "$builtList"
  else
    echo "  output json missing/too small after run"
    fail=$((fail + 1))
  fi
done < "$idList"

echo "redo_spiceinit_usgs DONE $(date): ok=$ok missing=$miss failed=$fail of $n processed"
echo "Successfully-built ids written to $builtList"
