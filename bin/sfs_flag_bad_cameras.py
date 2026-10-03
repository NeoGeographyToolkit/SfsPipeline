#!/usr/bin/env python3
# Analyze bundle adjustment residual statistics to detect and flag suspect/whacky
# cameras before Shape-from-Shading (SfS) reconstruction.
#
# Flags cameras satisfying ANY of:
#   1. mapproj-offset-95% > threshold (default: 5.0 m, indicates terrain smear / shift)
#   2. reprojection median > threshold (default: 0.75 px, indicates poor internal fit)
#   3. match count < threshold (default: 50, indicates starved pose)
#   4. camera-center move > threshold (default: 1000 m, indicates drifted/runaway pose)
#
# Usage:
#   sfs_flag_bad_cameras.py <ba_dir_or_prefix> [-o removed_ids.txt] [--report report.txt]

import argparse
import glob
import os
import re
import sys

ID_RE = re.compile(r"(M\d+[LR]E|[A-Za-z0-9_]+)")

def find_file(prefix, pattern):
  # Try exact pattern relative to prefix
  matches = glob.glob(f"{prefix}*{pattern}*")
  if matches:
    return matches[0]
  # Try in parent directory
  pdir = os.path.dirname(prefix) or "."
  matches = glob.glob(f"{pdir}/*{pattern}*")
  if matches:
    return matches[0]
  return None

def main():
  parser = argparse.ArgumentParser(
    description="Flag suspect/whacky cameras from bundle_adjust statistics before SfS."
  )
  parser.add_argument("prefix", help="Bundle adjust prefix or directory (e.g. ba_htdem/run)")
  parser.add_argument("-o", "--out-list", default="removed_ids.txt",
                      help="Output file with flagged product IDs (default: removed_ids.txt)")
  parser.add_argument("--report", default="flagged_report.txt",
                      help="Output analytical report file (default: flagged_report.txt)")
  parser.add_argument("--max-offset-p95", type=float, default=5.0,
                      help="Max allowable 95th percentile mapprojection offset in meters (default: 5.0)")
  parser.add_argument("--max-reproj-med", type=float, default=0.75,
                      help="Max allowable median reprojection error in pixels (default: 0.75)")
  parser.add_argument("--min-matches", type=int, default=50,
                      help="Min required tie point match count (default: 50)")
  parser.add_argument("--max-shift-m", type=float, default=1000.0,
                      help="Max allowable camera center movement in meters (default: 1000.0)")
  args = parser.parse_args()

  prefix = args.prefix
  offset_file = find_file(prefix, "mapproj_match_offset_stats")
  reproj_file = find_file(prefix, "final_residuals_stats")
  shift_file = find_file(prefix, "camera_offsets_stats")

  flagged = {}  # id -> list of reasons

  # 1. Parse mapproj match offset stats
  if offset_file and os.path.exists(offset_file):
    print(f"Reading mapproj offsets: {offset_file}")
    with open(offset_file, "r") as f:
      for line in f:
        if line.startswith("#"):
          continue
        p = line.split()
        if len(p) >= 7:
          m = ID_RE.search(p[0])
          if m:
            pid = m.group(1)
            try:
              p95 = float(p[4])
              count = int(p[6])
              if p95 > args.max_offset_p95:
                flagged.setdefault(pid, []).append(f"mapproj-p95={p95:.2f}m > {args.max_offset_p95}m")
              if count < args.min_matches:
                flagged.setdefault(pid, []).append(f"matches={count} < {args.min_matches}")
            except ValueError:
              pass
  else:
    print(f"Note: mapproj match offset stats not found under {prefix} (skipping offset check)")

  # 2. Parse reprojection residuals
  if reproj_file and os.path.exists(reproj_file):
    print(f"Reading reprojection residuals: {reproj_file}")
    with open(reproj_file, "r") as f:
      for line in f:
        if line.startswith("#"):
          continue
        p = line.split()
        if len(p) >= 3:
          m = ID_RE.search(p[0])
          if m:
            pid = m.group(1)
            try:
              med = float(p[2])
              if med > args.max_reproj_med:
                flagged.setdefault(pid, []).append(f"reproj-median={med:.3f}px > {args.max_reproj_med}px")
            except ValueError:
              pass

  # 3. Parse camera center shift if present
  if shift_file and os.path.exists(shift_file):
    print(f"Reading camera offsets: {shift_file}")
    with open(shift_file, "r") as f:
      for line in f:
        if line.startswith("#"):
          continue
        p = line.split()
        if len(p) >= 2:
          m = ID_RE.search(p[0])
          if m:
            pid = m.group(1)
            try:
              shift = float(p[1])
              if shift > args.max_shift_m:
                flagged.setdefault(pid, []).append(f"shift={shift:.1f}m > {args.max_shift_m}m")
            except ValueError:
              pass

  # Write output ID list
  sorted_ids = sorted(flagged.keys())
  with open(args.out_list, "w") as f:
    for pid in sorted_ids:
      f.write(f"{pid}\n")
  print(f"Flagged {len(sorted_ids)} suspect cameras. Written to {args.out_list}")

  # Write detailed report
  with open(args.report, "w") as f:
    f.write(f"# Flagged Suspect Cameras Report (n={len(sorted_ids)})\n")
    f.write(f"# Evaluated against prefix: {prefix}\n\n")
    for pid in sorted_ids:
      reasons = "; ".join(flagged[pid])
      f.write(f"{pid:16s} : {reasons}\n")
  print(f"Detailed analytical report written to {args.report}")

if __name__ == "__main__":
  main()
