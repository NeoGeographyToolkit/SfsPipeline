#!/usr/bin/env python3
# Assign mapprojected images to spatial quadrants (with overlap) for image_subset.
#
# For a large terrain, image_subset is run per quadrant (ASP manual :numref:`image_subset`):
# smaller area, fewer images, faster, more relevant. This tool splits the box into four
# quadrants (ll, lr, ul, ur) that OVERLAP by a margin, and assigns each image to every
# quadrant its footprint intersects (an image straddling the middle lands in several).
# It also prints each quadrant's projwin, to pass to image_subset --t_projwin so coverage
# is scored only within that quadrant.
#
# All images must share one projection (they are mapprojected on the same DEM). Bounds
# come from each raster's geotransform (metadata only, fast).
#
# Usage:
#   split_quadrants.py --map-list L --out-dir D
#                      (--dem dem.tif | --extent "xmin ymin xmax ymax")
#                      [--overlap-m 1000] [--lowres-list LR]
#
# --lowres-list LR : a list parallel to --map-list (one line per map, same order, e.g.
#   from prepare_lowres.sh). When given, the quadrant lists are written with the LOW-RES
#   paths (what image_subset should read), while assignment still uses the full-res
#   footprints. Without it, the full-res map paths are written.
#
# Writes, in out-dir:
#   quad_ll.txt quad_lr.txt quad_ul.txt quad_ur.txt   image lists per quadrant
#   quad_projwins.txt                                  "name xmin ymin xmax ymax" per line
import argparse, os, sys
from osgeo import gdal

gdal.UseExceptions()

def bounds(path):
  ds = gdal.Open(path)
  if ds is None:
    return None
  gt = ds.GetGeoTransform()
  nx, ny = ds.RasterXSize, ds.RasterYSize
  xs = [gt[0], gt[0] + nx * gt[1]]
  ys = [gt[3], gt[3] + ny * gt[5]]
  return min(xs), min(ys), max(xs), max(ys)

def intersects(a, b):
  return not (a[2] <= b[0] or a[0] >= b[2] or a[3] <= b[1] or a[1] >= b[3])

def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--map-list", required=True)
  ap.add_argument("--out-dir", required=True)
  ap.add_argument("--dem")
  ap.add_argument("--extent")
  ap.add_argument("--overlap-m", type=float, default=1000.0)
  ap.add_argument("--lowres-list")
  a = ap.parse_args()

  if a.extent:
    xmin, ymin, xmax, ymax = map(float, a.extent.split())
  elif a.dem:
    xmin, ymin, xmax, ymax = bounds(a.dem)
  else:
    sys.exit("need --dem or --extent")

  maps = [l.strip() for l in open(a.map_list) if l.strip()]
  lowres = None
  if a.lowres_list:
    lowres = [l.strip() for l in open(a.lowres_list) if l.strip()]
    if len(lowres) != len(maps):
      sys.exit(f"lowres-list ({len(lowres)}) and map-list ({len(maps)}) differ in length")

  mx, my = (xmin + xmax) / 2.0, (ymin + ymax) / 2.0
  ov = a.overlap_m
  quads = {
    "ll": (xmin,      ymin,      mx + ov,   my + ov),
    "lr": (mx - ov,   ymin,      xmax,      my + ov),
    "ul": (xmin,      my - ov,   mx + ov,   ymax),
    "ur": (mx - ov,   my - ov,   xmax,      ymax),
  }

  os.makedirs(a.out_dir, exist_ok=True)
  fh = {q: open(os.path.join(a.out_dir, f"quad_{q}.txt"), "w") for q in quads}
  counts = {q: 0 for q in quads}
  nobounds = 0
  for i, m in enumerate(maps):
    b = bounds(m)
    if b is None:
      nobounds += 1
      continue
    out_path = lowres[i] if lowres else m
    for q, box in quads.items():
      if intersects(b, box):
        fh[q].write(out_path + "\n")
        counts[q] += 1
  for q in quads:
    fh[q].close()

  with open(os.path.join(a.out_dir, "quad_projwins.txt"), "w") as pw:
    for q, box in quads.items():
      pw.write(f"{q} {box[0]:.1f} {box[1]:.1f} {box[2]:.1f} {box[3]:.1f}\n")

  print(f"box: {xmin:.1f} {ymin:.1f} {xmax:.1f} {ymax:.1f}  overlap={ov} m")
  for q, box in quads.items():
    print(f"  quad_{q}: {counts[q]} images  projwin {box[0]:.1f} {box[1]:.1f} {box[2]:.1f} {box[3]:.1f}")
  if nobounds:
    print(f"  ({nobounds} maps had no readable bounds, skipped)")

if __name__ == "__main__":
  main()
