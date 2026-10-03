#!/usr/bin/env python3
# Break a GeoTIFF into padded tiles for per-tile parallel_sfs. A reusable python port
# of the old ~/bin/tile.pl (which was perl). Tiles are made NEAR-EQUAL in size (the
# requested tile size is rounded so the image divides evenly), then each tile window is
# PADDED by <pad> pixels on all sides, clamped to the image bounds, so neighbor tiles
# overlap and the SfS blend has no seam gaps. Tiles are cut with gdal_translate -srcwin
# and named tile-<N>.tif with N starting at 10001 - the numeric id that
# launch_sfs_tiles.sh keys on. gdal_translate must be on PATH (StereoPipeline build or a
# gdal conda env; on pfe use the `geo` env - see the pfe-nas skill).
#
# Usage: tile_dem.py <input.tif> <tileSizeX> <tileSizeY> <outDir> <pad>
#   e.g. tile_dem.py ref/lola_1mpp_extra_noblur.tif 4000 4000 tiles 200
import argparse, os, subprocess, sys
from osgeo import gdal

gdal.UseExceptions()

def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("input")
  ap.add_argument("tileX", type=int)
  ap.add_argument("tileY", type=int)
  ap.add_argument("outDir")
  ap.add_argument("pad", type=int)
  a = ap.parse_args()

  ds = gdal.Open(a.input)
  if ds is None:
    sys.exit(f"cannot open {a.input}")
  sizeX, sizeY = ds.RasterXSize, ds.RasterYSize
  tx, ty, pad = a.tileX, a.tileY, a.pad

  # round the tile count so tiles come out near-equal (mirror tile.pl)
  nX = int(sizeX / tx + 0.5) or 1
  nY = int(sizeY / ty + 0.5) or 1
  tx = sizeX // nX; nX = (sizeX // tx) or 1
  ty = sizeY // nY; nY = (sizeY // ty) or 1

  # output prefix, mirroring tile.pl: a slash in outDir splits dir/base -> "dir/base-tile-"
  if "/" in a.outDir:
    first, rest = a.outDir.split("/", 1)
    outDir, pref = first, f"{first}/{rest}-tile-"
  else:
    outDir, pref = a.outDir, f"{a.outDir}/tile-"
  os.makedirs(outDir, exist_ok=True)

  print(f"size {sizeX}x{sizeY}, {nX}x{nY} tiles of ~{tx}x{ty} px, pad {pad}")
  count = 10000
  made = 0
  for x in range(nX):
    for y in range(nY):
      count += 1
      begX = max(0, x * tx - pad); endX = min(sizeX, (x + 1) * tx + pad); widX = endX - begX
      begY = max(0, y * ty - pad); endY = min(sizeY, (y + 1) * ty + pad); widY = endY - begY
      if widX <= 0 or widY <= 0:
        continue
      tile = f"{pref}{count}.tif"
      cmd = ["gdal_translate", "-q",
             "-co", "TILED=yes", "-co", "INTERLEAVE=BAND",
             "-co", "BLOCKXSIZE=256", "-co", "BLOCKYSIZE=256",
             "-co", "compress=lzw", "-co", "BIGTIFF=YES",
             "-srcwin", str(begX), str(begY), str(widX), str(widY),
             a.input, tile]
      subprocess.run(cmd, check=True)
      made += 1
  print(f"wrote {made} tiles to {outDir}/ (tile-10001.tif ...)")

if __name__ == "__main__":
  main()
