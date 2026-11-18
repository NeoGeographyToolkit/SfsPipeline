#!/usr/bin/env python3
"""
Compare the per-camera reprojection error of the fixed and the free cameras of a
bundle_adjust run, to validate the anchors of the fixed stage (ba_fix).

The fixed cameras are the ones whose camera center did not move, read from
<prefix>-camera_offsets.txt, or the images in --fixed-list if given. A good
fixed stage has both groups at about 1 px median. If the free cameras fit and
many fixed ones are left at 5 px or more, the fixed cameras disagree with each
other. The usual cause is the plain SPICE cameras held fixed in place of the
registered (USGS) ones.

Usage:
  ba_fixed_check.py <baPrefix> [--fixed-list <file>] [--thresh <px>]

Example:
  ba_fixed_check.py ba_fix/run

Pure Python, no dependencies, single thread, head-node safe.
"""

import argparse
import os
import statistics
import sys


def image_key(path):
    # Match on the image file name, so relative and absolute paths agree
    return os.path.basename(path.strip())


def read_offsets(fileName):
    # Per-image horizontal and vertical camera center change, in meters
    offsets = {}
    with open(fileName) as f:
        for line in f:
            if line.startswith('#') or not line.strip():
                continue
            vals = line.split()
            offsets[image_key(vals[0])] = (float(vals[1]), float(vals[2]))
    return offsets


def read_residuals(fileName):
    # Lines: image, mean, median, count
    medians = {}
    with open(fileName) as f:
        for line in f:
            if line.startswith('#') or not line.strip():
                continue
            vals = [v.strip() for v in line.split(',')]
            try:
                medians[image_key(vals[0])] = float(vals[2])
            except ValueError:
                continue
    return medians


def summary(name, vals, thresh):
    vals = [v for v in vals if v == v]  # drop NaN
    if len(vals) == 0:
        print('%-6s n=0' % name)
        return 0
    numBad = sum(1 for v in vals if v > thresh)
    print('%-6s n=%4d  median %8.2f px  max %8.2f px  over %g px: %d'
          % (name, len(vals), statistics.median(vals), max(vals), thresh, numBad))
    return numBad


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('baPrefix', help='bundle_adjust output prefix, e.g. ba_fix/run')
    parser.add_argument('--fixed-list', default='',
                        help='images held fixed (default: cameras with zero move)')
    parser.add_argument('--thresh', type=float, default=5.0,
                        help='per-camera median error to flag, in pixels (default 5)')
    args = parser.parse_args()

    offsetFile = args.baPrefix + '-camera_offsets.txt'
    if args.fixed_list != '':
        with open(args.fixed_list) as f:
            fixed = set(image_key(l) for l in f if l.strip())
    else:
        offsets = read_offsets(offsetFile)
        fixed = set(k for k, v in offsets.items() if v[0] == 0.0 and v[1] == 0.0)

    if len(fixed) == 0:
        print('No fixed cameras found. Nothing to check.')
        return 0

    bad = 0
    for stage in ['initial', 'final']:
        medians = read_residuals(args.baPrefix + '-' + stage + '_residuals_stats.txt')
        print(stage + ':')
        summary('fixed', [v for k, v in medians.items() if k in fixed], args.thresh)
        numBad = summary('free', [v for k, v in medians.items() if k not in fixed],
                         args.thresh)
        if stage == 'final':
            fixedVals = [v for k, v in medians.items() if k in fixed and v == v]
            bad = sum(1 for v in fixedVals if v > args.thresh)
            worst = sorted([(v, k) for k, v in medians.items() if k in fixed],
                           reverse=True)[:10]

    if bad > 0:
        print('Fixed cameras above %g px after the solve: %d of %d. Worst:'
              % (args.thresh, bad, len(fixedVals)))
        for v, k in worst:
            if v > args.thresh:
                print('  %8.2f px  %s' % (v, k))

    # A few outliers are individual bad frames. Many mean the anchors disagree.
    if bad > max(2, 0.1 * len(fixedVals)):
        print('FAIL: many fixed cameras do not fit, so the anchors disagree with each other.')
        print('Check that the fixed ids point to the registered cameras, not plain SPICE.')
        return 1

    print('OK: the fixed cameras fit.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
