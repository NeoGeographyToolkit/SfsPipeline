#!/bin/bash
# Fetch and prepare an LRO NAC EDR image by product id, via the ODE REST API.
#
# Usage:
#   fetch_lro_nac.sh <PRODUCTID> [outdir] [--prep]
#     PRODUCTID   e.g. M167222041RE  (LE/RE suffix required)
#     outdir      where to put files (default: current dir)
#     --prep      also run the ISIS ingest pipeline (lronac2isis, and if ISIS
#                 kernels/calibration are present: spiceinit, lronaccal, lronacecho)
#
# Why this tool exists: ODE is poorly scriptable and the codes are non-obvious.
# The ONLY product type that works for raw NAC is pt=EDRNAC4 (NOT "EDRNAC"), with
# target=moon, ihid=LRO, iid=LROC, and pdsid = "nac." + lowercase(productid).
# We always fetch the EDR (raw) and do our OWN radiometric calibration + echo.
#
# ISIS env note (pfe): use the FULL ISIS env (has libLinearMath), e.g.
#   ISISROOT=$HOME/miniconda3/envs/asp_deps   (a full ISIS env; note isis10asp lacks
#   libLinearMath and the ISIS apps fail to load). Set ISISROOT + PATH + ISISDATA
#   before --prep. lronac2isis needs no kernels; spiceinit/lronaccal need a
#   populated ISISDATA (base + lro). See the lro-nac / isis-data skills.

set -e
pid="$1"; outdir="${2:-.}"; prep=0
for a in "$@"; do [ "$a" = "--prep" ] && prep=1; done
if [ -z "$pid" ] || [ "$pid" = "--prep" ]; then
  echo "Usage: $0 <PRODUCTID e.g. M167222041RE> [outdir] [--prep]"; exit 1
fi
[ "$outdir" = "--prep" ] && outdir="."
mkdir -p "$outdir"; cd "$outdir"

low=$(echo "$pid" | tr 'A-Z' 'a-z')
pdsid="nac.${low}"
q="https://oderest.rsl.wustl.edu/live2/?query=product&output=JSON&target=moon&ihid=LRO&iid=LROC&pt=EDRNAC4&pdsid=${pdsid}&results=pdf"
echo "ODE query: $q"
curl -sS "$q" -o "${pid}.ode.json"
url=$(python3 -c "
import json,sys
d=json.load(open('${pid}.ode.json'))
p=d.get('ODEResults',{}).get('Products')
if not p or p=='No Products Found': sys.exit('ODE: no product found for ${pid}')
p=p['Product']; p=p[0] if isinstance(p,list) else p
pf=p['Product_files']['Product_file']
pf=pf if isinstance(pf,list) else [pf]
for f in pf:
    u=f.get('URL','')
    if u.upper().endswith('.IMG'): print(u); break
")
[ -z "$url" ] && { echo "Failed to find .IMG URL"; exit 1; }
echo "IMG URL: $url"
if [ ! -f "${pid}.IMG" ]; then
  echo "Downloading ${pid}.IMG ..."
  curl -sS -L -o "${pid}.IMG" "$url"
fi
ls -la "${pid}.IMG"

if [ "$prep" = "1" ]; then
  command -v lronac2isis >/dev/null || { echo "ISIS not on PATH; set ISISROOT/PATH (isis10) first"; exit 1; }
  echo "=== lronac2isis ==="
  lronac2isis from="${pid}.IMG" to="${pid}.cub"
  echo "cub dims:"; gdalinfo "${pid}.cub" 2>/dev/null | grep "Size is" || true
  if [ -n "$ISISDATA" ] && ls "$ISISDATA"/base/kernels/lsk/*.tls >/dev/null 2>&1; then
    echo "=== spiceinit / lronaccal / lronacecho ==="
    spiceinit from="${pid}.cub"
    lronaccal from="${pid}.cub" to="${pid}.cal.cub"
    lronacecho from="${pid}.cal.cub" to="${pid}.cal.echo.cub"
    echo "Prepared ${pid}.cal.echo.cub"
  else
    echo "NOTE: ISISDATA not populated (no base/kernels/lsk) - skipped spiceinit/cal/echo."
    echo "      The raw ${pid}.cub has correct dims and pairs with an existing CSM"
    echo "      adjusted-state json (json is the camera). Run downloadIsisData to"
    echo "      populate ISISDATA if you need calibration or a fresh CSM via isd_generate."
  fi
fi
echo "Done."
