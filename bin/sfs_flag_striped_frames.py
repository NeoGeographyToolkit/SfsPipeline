#!/usr/bin/env python3

# Flag LRO NAC frames that carry a RADIOMETRIC defect - a detector/readout stripe or a
# saturated band - which the geometric screens (interest-point match count, mapproject
# offset, bundle-adjust residual) do NOT catch. A stripe frame passes
# sfs_flag_bad_cameras.py (its geometry is fine) yet pollutes the max-lit mosaic and the
# SfS solve, so it must be detected directly from the imagery.
#
# Two independent per-ortho signals, flagged if EITHER is a robust outlier:
#   (1) BRIGHTNESS outlier - the 99.9-percentile reflectance of a decimated full image.
#       A stripe / saturated frame sits far above the set median. This is the signal
#       that catches the common case (a bright readout band).
#   (2) PERIODIC-STRIPE score - over a crop, high-pass to remove terrain, take the 2D
#       FFT, score = max OFF-AXIS magnitude / mean magnitude. A diagonal detector stripe
#       makes a sharp off-axis FFT peak; cratered terrain does not. The central FFT cross
#       is zeroed so a footprint edge or an axis-aligned gradient cannot masquerade as a
#       stripe. This catches a faint stripe that is not especially bright.
#
# The flagged ids are written one per line, meant to be merged into the SfS removal list
# alongside sfs_flag_bad_cameras.py output (then excluded from the SfS image subset).
# Run in an env with gdal + numpy + scipy (the `geo` conda env on pfe).
#
# Usage:
#   sfs_flag_striped_frames.py <ortho_list> -o <flagged_ids.txt>
#       [--region ulx uly lrx lry]  (projected window for the FFT; default central crop)
#       [--bright-factor 3.0] [--bright-floor 0.08]
#       [--stripe-factor 4.0] [--stripe-floor 50.0]
#       [--decimate 8]
#
# <ortho_list> is one mapprojected ortho path per line; the frame id is parsed as the
# M<digits>{LE,RE} token in the basename (falling back to the basename stem).

import argparse
import os
import re
import sys

import numpy as np
from osgeo import gdal
from scipy.ndimage import uniform_filter

gdal.UseExceptions()


def frame_id(path):
    m = re.search(r"(M\d+[LR]E)", os.path.basename(path))
    return m.group(1) if m else os.path.basename(path).split(".")[0]


def brightness_p999(ds, decimate):
    b = ds.GetRasterBand(1)
    xs = max(1, ds.RasterXSize // decimate)
    ys = max(1, ds.RasterYSize // decimate)
    a = b.ReadAsArray(buf_xsize=xs, buf_ysize=ys).astype(float)
    nod = b.GetNoDataValue()
    m = np.isfinite(a)
    if nod is not None:
        m &= (a != nod)
    m &= (a > 1e-6)
    if m.sum() < 500:
        return None
    return float(np.percentile(a[m], 99.9))


def stripe_score(ds, region):
    gt = ds.GetGeoTransform()
    X, Y = ds.RasterXSize, ds.RasterYSize
    if region is not None:
        ulx, uly, lrx, lry = region
        px = int((ulx - gt[0]) / gt[1]); px2 = int((lrx - gt[0]) / gt[1])
        py = int((uly - gt[3]) / gt[5]); py2 = int((lry - gt[3]) / gt[5])
        x0, x1 = max(0, min(px, px2)), min(X, max(px, px2))
        y0, y1 = max(0, min(py, py2)), min(Y, max(py, py2))
    else:
        # central half of the image
        x0, x1 = X // 4, 3 * X // 4
        y0, y1 = Y // 4, 3 * Y // 4
    if x1 - x0 < 60 or y1 - y0 < 60:
        return None
    a = ds.ReadAsArray(x0, y0, x1 - x0, y1 - y0).astype(float)
    if np.mean(a <= 1e-6) > 0.3:
        return None
    a = a - uniform_filter(a, size=9)              # high-pass: kill terrain, keep stripes
    F = np.abs(np.fft.fftshift(np.fft.fft2(a)))
    cy, cx = np.array(F.shape) // 2
    mean_all = F.mean()
    F[cy - 4:cy + 5, :] = 0                         # zero the central cross (DC + both axes)
    F[:, cx - 4:cx + 5] = 0
    return float(F.max() / (mean_all + 1e-9))


def main():
    ap = argparse.ArgumentParser(description="Flag radiometric stripe / saturated LRO NAC frames.")
    ap.add_argument("ortho_list")
    ap.add_argument("-o", "--output", required=True, help="flagged ids, one per line")
    ap.add_argument("--region", nargs=4, type=float, default=None,
                    metavar=("ULX", "ULY", "LRX", "LRY"),
                    help="projected window for the FFT test (default: central crop)")
    ap.add_argument("--bright-factor", type=float, default=3.0)
    ap.add_argument("--bright-floor", type=float, default=0.08)
    ap.add_argument("--stripe-factor", type=float, default=4.0)
    ap.add_argument("--stripe-floor", type=float, default=50.0)
    ap.add_argument("--decimate", type=int, default=8)
    args = ap.parse_args()

    paths = [l.strip() for l in open(args.ortho_list) if l.strip()]
    rows = []
    for p in paths:
        try:
            ds = gdal.Open(p)
        except Exception:
            ds = None
        if ds is None:
            continue
        br = brightness_p999(ds, args.decimate)
        st = stripe_score(ds, args.region)
        if br is None and st is None:
            continue
        rows.append([frame_id(p), br, st])
    if not rows:
        sys.exit("No readable orthos in %s" % args.ortho_list)

    brs = np.array([r[1] for r in rows if r[1] is not None])
    sts = np.array([r[2] for r in rows if r[2] is not None])
    br_med = float(np.median(brs)) if brs.size else 0.0
    st_med = float(np.median(sts)) if sts.size else 0.0
    br_cut = max(args.bright_factor * br_med, args.bright_floor)
    st_cut = max(args.stripe_factor * st_med, args.stripe_floor)

    flagged = []
    for ident, br, st in rows:
        why = []
        if br is not None and br > br_cut:
            why.append("bright")
        if st is not None and st > st_cut:
            why.append("stripe")
        if why:
            flagged.append((ident, br, st, "+".join(why)))

    rows.sort(key=lambda r: -(r[1] or 0))
    print("# id  p99.9-brightness  stripe-score   (brightness median %.4f cut %.4f, "
          "stripe median %.1f cut %.1f)" % (br_med, br_cut, st_med, st_cut))
    for ident, br, st in rows:
        tag = ""
        for f in flagged:
            if f[0] == ident:
                tag = "  <= FLAGGED " + f[3]
        print("%-16s %8s %12s%s" % (ident,
              ("%.4f" % br) if br is not None else "  NA",
              ("%.1f" % st) if st is not None else "  NA", tag))

    with open(args.output, "w") as f:
        for ident, _, _, _ in flagged:
            f.write(ident + "\n")
    print("\nFlagged %d of %d frames -> %s" % (len(flagged), len(rows), args.output))


if __name__ == "__main__":
    main()
