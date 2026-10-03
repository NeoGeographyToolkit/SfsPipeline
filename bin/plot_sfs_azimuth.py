#!/usr/bin/env python3
"""
Generate a publication-quality polar rose plot of solar azimuth angles
from sfs_query.sh output tables, with optional multi-dataset comparison and HTML reporting.
"""

import argparse
import os
import sys
import numpy as np
import matplotlib.pyplot as plt

def load_azimuth_table(filepath):
  """
  Load azimuth table from sfs_query.sh output.
  Format: image_path raw_azimuth normalized_azimuth_0_to_360 elevation
  """
  azimuths = []
  elevations = []
  pids = []
  if not filepath or not os.path.exists(filepath):
    return np.array(azimuths), np.array(elevations), pids

  with open(filepath, "r") as f:
    for line in f:
      parts = line.strip().split()
      if len(parts) >= 3:
        try:
          pid = os.path.basename(parts[0]).replace(".cal.echo.cub", "").replace(".cub", "")
          raw_az = float(parts[1])
          norm_az = float(parts[2])
          el = float(parts[3]) if len(parts) >= 4 else 0.0
          azimuths.append(norm_az)
          elevations.append(el)
          pids.append(pid)
        except ValueError:
          continue
  return np.array(azimuths), np.array(elevations), pids

def make_polar_plot(az1, az2, label1, label2, title, out_png):
  """
  Create polar rose scatter plot:
  Inner tier (r=1.0): Dataset 1 (blue balls)
  Outer tier (r=1.35): Dataset 2 (coral balls, if present)
  """
  fig = plt.figure(figsize=(9, 9), dpi=300)
  ax = fig.add_subplot(111, projection='polar')

  # Polar configuration: 0 at North, clockwise rotation
  ax.set_theta_zero_location('N')
  ax.set_theta_direction(-1)

  r1 = 1.0
  r2 = 1.35 if len(az2) > 0 else 1.0
  theta_full = np.linspace(0, 2 * np.pi, 500)
  ax.plot(theta_full, [r1] * len(theta_full), color='#b0bec5', linestyle='--', linewidth=0.8, alpha=0.7)
  if len(az2) > 0:
    ax.plot(theta_full, [r2] * len(theta_full), color='#b0bec5', linestyle='--', linewidth=0.8, alpha=0.7)

  if len(az1) > 0:
    ax.scatter(
      np.radians(az1), [r1] * len(az1),
      c='#1f77b4', s=45, alpha=0.75, edgecolors='#0d47a1', linewidths=0.5,
      label=f'{label1} (n={len(az1)})', zorder=3
    )

  if len(az2) > 0:
    ax.scatter(
      np.radians(az2), [r2] * len(az2),
      c='#ff7f0e', s=55, alpha=0.85, edgecolors='#bf360c', linewidths=0.6,
      label=f'{label2} (n={len(az2)})', zorder=4
    )

  # Highlight astronomically forbidden illumination zone (300 to 60 deg) for lunar south pole
  theta_shade1 = np.linspace(np.radians(300), np.radians(360), 50)
  theta_shade2 = np.linspace(0, np.radians(60), 50)
  r_max = 1.55 if len(az2) > 0 else 1.25
  ax.fill_between(theta_shade1, 0, r_max, color='#eceff1', alpha=0.4)
  ax.fill_between(theta_shade2, 0, r_max, color='#eceff1', alpha=0.4)

  # Angular labels every 30 deg
  ticks = np.arange(0, 360, 30)
  tick_labels = [f'{t}°' for t in ticks]
  tick_labels[0] = '0° (N)'
  tick_labels[3] = '90° (E)'
  tick_labels[6] = '180° (S)'
  tick_labels[9] = '270° (W)'
  ax.set_thetagrids(ticks, labels=tick_labels, fontsize=10, weight='bold')

  ax.set_rmax(r_max)
  ax.set_yticklabels([])
  ax.set_rticks([])
  ax.grid(True, linestyle=':', color='#90a4ae', alpha=0.6)

  ax.set_title(title, fontsize=13, weight='bold', pad=25)
  ax.legend(loc='lower center', bbox_to_anchor=(0.5, -0.15), frameon=True,
            facecolor='white', edgecolor='#cfd8dc', fontsize=10, ncol=2)

  plt.tight_layout()
  plt.savefig(out_png, dpi=300, bbox_inches='tight')
  plt.close()
  print(f"Saved polar plot: {out_png}")

def main():
  parser = argparse.ArgumentParser(description="Plot solar azimuth distribution in polar rose format.")
  parser.add_argument("table1", help="Path to first azimuth table (output from sfs_query.sh)")
  parser.add_argument("--table2", help="Optional path to second azimuth table for dual-ring comparison")
  parser.add_argument("--label1", default="Primary Dataset", help="Legend label for table1")
  parser.add_argument("--label2", default="Secondary Dataset", help="Legend label for table2")
  parser.add_argument("--title", default="Solar Azimuth Distribution: LRO NAC Multi-Illumination Coverage",
                      help="Plot title")
  parser.add_argument("-o", "--output-png", default="solar_azimuth_polar.png", help="Output PNG path")
  args = parser.parse_args()

  az1, el1, pids1 = load_azimuth_table(args.table1)
  az2, el2, pids2 = load_azimuth_table(args.table2) if args.table2 else (np.array([]), np.array([]), [])

  if len(az1) == 0 and len(az2) == 0:
    sys.exit(f"Error: No valid azimuth entries found in {args.table1}")

  make_polar_plot(az1, az2, args.label1, args.label2, args.title, args.output_png)

if __name__ == "__main__":
  main()
