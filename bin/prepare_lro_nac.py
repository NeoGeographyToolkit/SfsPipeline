#!/usr/bin/env python3
# Fetch and prepare LRO NAC images: radiometric calibration, echo correction,
# linear ephemeris reduction, and CSM model state generation.
#
# Follows ASP documentation (examples/lronac.rst):
#   fetch .IMG -> lronac2isis -> spiceinit -> lronaccal -> lronacecho -> isd_generate
# Wipes intermediate files (.IMG, .lbl, raw .cub, .cal.cub), keeping only final
# .cal.echo.cub, .cal.echo.json, and .ode.json.
#
# spiceinit uses standard mission kernels by default.
# Pass --usgs-polar to use the USGS South Pole custom polar kernels (2009-2013).
#
# Usage:
#   prepare_lro_nac.py [--list image_list.txt] [--outdir DIR] [--usgs-polar] [PRODUCT_ID ...]

import argparse
import json
import os
import shutil
import subprocess
import sys

# Default paths on pfe (can be overridden by environment variables)
ISISROOT = os.environ.get("ISISROOT", os.path.expanduser("~/miniconda3/envs/asp_deps"))
ISISDATA = os.environ.get("ISISDATA", os.path.expanduser("~/projects/isis3data"))
SP = os.environ.get("ASPROOT", os.path.expanduser("~/projects/BinaryBuilder/StereoPipeline"))
SPK_MK = f"{ISISDATA}/lro_south/usgs_polar_spk.mk"
CK_MK = f"{ISISDATA}/lro_south/usgs_polar_ck.mk"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

def run_cmd(cmd, env=None, cwd=None):
  print(f"Running: {cmd}")
  res = subprocess.run(cmd, shell=True, env=env, cwd=cwd,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       universal_newlines=True)
  if res.returncode != 0:
    print(res.stdout)
    raise RuntimeError(f"Command failed with returncode {res.returncode}: {cmd}")
  return res.stdout

def fix_distortion_coeff(json_path):
  with open(json_path, "r") as f:
    d = json.load(f)
  od = d.get("optical_distortion", {})
  lro = od.get("lrolrocnac", {})
  coeff = lro.get("coefficients")
  if isinstance(coeff, (int, float)):
    lro["coefficients"] = [coeff]
    with open(json_path, "w") as f:
      json.dump(d, f, indent=2)
    print(f"Patched scalar coefficient {coeff} -> [{coeff}] in {os.path.basename(json_path)}")

def find_fetch_tool():
  # Prefer sibling fetch_lro_nac.sh in 
  cand1 = os.path.join(SCRIPT_DIR, "fetch_lro_nac.sh")
  if os.path.exists(cand1) and os.access(cand1, os.X_OK):
    return cand1
  # Fall back to ~/bin/fetch_lro_nac.sh
  cand2 = os.path.expanduser("~/bin/fetch_lro_nac.sh")
  if os.path.exists(cand2) and os.access(cand2, os.X_OK):
    return cand2
  # Fall back to PATH
  which_tool = shutil.which("fetch_lro_nac.sh")
  if which_tool:
    return which_tool
  return cand1

def process_product(pid, out_dir, use_polar=False):
  pid = pid.strip().upper()
  if not pid:
    return

  final_cub = os.path.join(out_dir, f"{pid}.cal.echo.cub")
  final_json = os.path.join(out_dir, f"{pid}.cal.echo.json")
  raw_cub = os.path.join(out_dir, f"{pid}.raw.cub")
  cal_cub = os.path.join(out_dir, f"{pid}.cal.cub")
  old_cub = os.path.join(out_dir, f"{pid}.cub")
  old_json = os.path.join(out_dir, f"{pid}.json")
  img_path = os.path.join(out_dir, f"{pid}.IMG")
  lbl_path = os.path.join(out_dir, f"{pid}.LBL")
  lbl_lower = os.path.join(out_dir, f"{pid}.lbl")

  print(f"\n=======================================================")
  print(f"Processing LRO NAC image: {pid}")
  print(f"=======================================================")

  # If already fully prepared as final cal.echo product, clean any residual raw files and exit
  if os.path.exists(final_cub) and os.path.exists(final_json) and os.path.getsize(final_json) > 1000:
    print(f"Already prepared final product: {final_cub} and {final_json}")
    for residual in [img_path, lbl_path, lbl_lower, raw_cub, cal_cub, old_cub, old_json]:
      if os.path.exists(residual):
        os.remove(residual)
        print(f"Removed residual intermediate file {os.path.basename(residual)}.")
    return

  # Environment for ISIS tools
  env_isis = os.environ.copy()
  env_isis["ISISROOT"] = ISISROOT
  env_isis["ISISDATA"] = ISISDATA
  env_isis["ALESPICEROOT"] = ISISDATA
  env_isis["PATH"] = f"{ISISROOT}/bin:{os.path.expanduser('~/bin')}:{env_isis.get('PATH', '')}"

  # Step 1: If pre-existing uncalibrated .cub exists, rename it to raw.cub
  if os.path.exists(old_cub) and not os.path.exists(raw_cub):
    os.rename(old_cub, raw_cub)

  # Fetch and ingest if raw_cub does not exist
  if not os.path.exists(raw_cub):
    if not os.path.exists(img_path):
      fetch_script = find_fetch_tool()
      cmd_fetch = f"{fetch_script} {pid} {out_dir}"
      run_cmd(cmd_fetch, env=env_isis)

    # Ingest with lronac2isis
    cmd_ingest = f"{ISISROOT}/bin/lronac2isis from={img_path} to={raw_cub}"
    run_cmd(cmd_ingest, env=env_isis)

  # Step 2: spiceinit on raw_cub. Vanilla (standard mission kernels) by default;
  # USGS South Pole custom polar kernels only when explicitly requested.
  if use_polar:
    cmd_spice = (
      f"{ISISROOT}/bin/spiceinit from={raw_cub} "
      f"spk={SPK_MK} ck={CK_MK} web=false"
    )
  else:
    cmd_spice = f"{ISISROOT}/bin/spiceinit from={raw_cub} web=false"
  run_cmd(cmd_spice, env=env_isis)
  print("spiceinit attached kernels successfully.")

  # Step 3: lronaccal (radiometric calibration)
  cmd_cal = f"{ISISROOT}/bin/lronaccal from={raw_cub} to={cal_cub}"
  run_cmd(cmd_cal, env=env_isis)
  print(f"Radiometric calibration complete: {cal_cub}")

  # Step 4: lronacecho (echo correction)
  cmd_echo = f"{ISISROOT}/bin/lronacecho from={cal_cub} to={final_cub}"
  run_cmd(cmd_echo, env=env_isis)
  print(f"Echo correction complete: {final_cub}")

  # Step 5: isd_generate from final cal.echo.cub with linear reduction
  cmd_isd = f"{ISISROOT}/bin/isd_generate -k {final_cub} {final_cub} --reduction linear -o {final_json}"
  run_cmd(cmd_isd, env=env_isis)
  print(f"Generated raw ISD JSON: {final_json}")

  # Step 6: Patch distortion coefficient for USGSCSM compatibility
  fix_distortion_coeff(final_json)

  # Step 7: Validate with cam_test
  env_asp = os.environ.copy()
  env_asp["PATH"] = f"{SP}/bin:{SP}/libexec:{env_asp.get('PATH', '')}"
  isis_asp = os.environ.get("ISIS_ASP", os.path.expanduser("~/miniconda3/envs/asp_deps"))
  env_asp["ISISROOT"] = isis_asp
  env_asp["LD_LIBRARY_PATH"] = f"{isis_asp}/lib:{SP}/lib:{SP}/lib/csmplugins:{env_asp.get('LD_LIBRARY_PATH', '')}"
  env_asp["GDAL_DATA"] = f"{SP}/share/gdal"
  env_asp["PROJ_DATA"] = f"{SP}/share/proj"
  env_asp["ISISDATA"] = ISISDATA

  # cam_test is a sanity check only; non-fatal
  cmd_camtest = f"cam_test --image {final_cub} --cam1 {final_cub} --cam2 {final_json} --sample-rate 5000"
  try:
    out_test = run_cmd(cmd_camtest, env=env_asp, cwd=out_dir)
    for line in out_test.splitlines():
      if "pixel diff" in line or "diff norm" in line or "diff (meters)" in line or "Median:" in line:
        print(f"  {line}")
  except Exception as e:
    print(f"Warning: cam_test validation failed for {pid} (non-fatal): {e}")

  # Step 8: Clean up intermediate files, keeping only final cal.echo products
  for intermediate in [img_path, lbl_path, lbl_lower, raw_cub, cal_cub, old_cub, old_json]:
    if os.path.exists(intermediate):
      os.remove(intermediate)
      print(f"Removed intermediate file {os.path.basename(intermediate)} to save storage.")

  print(f"Successfully finished {pid}! Final product: {final_cub}")

def main():
  parser = argparse.ArgumentParser(
    description="Fetch and prepare LRO NAC images with radiometric calibration, "
                "echo correction, linear ephemeris reduction, and CSM camera modeling."
  )
  parser.add_argument("products", nargs="*", help="Product IDs (e.g. M135007317RE)")
  parser.add_argument("--list", help="File with list of product IDs")
  parser.add_argument("--outdir", default=".",
                      help="Output directory (default: current directory)")
  parser.add_argument("--usgs-polar", dest="usgs_polar", action="store_true", default=False,
                      help="Use the USGS South Pole custom polar SPICE kernels in "
                           "spiceinit (valid only for 2009-2013 controlled images).")
  parser.add_argument("--no-usgs-polar", dest="usgs_polar", action="store_false",
                      help="Use standard mission kernels in spiceinit (default).")
  args = parser.parse_args()

  pids = list(args.products)
  if args.list and os.path.exists(args.list):
    with open(args.list) as f:
      for line in f:
        line = line.strip()
        if line and not line.startswith("#"):
          pids.append(line.split()[0])

  if not pids:
    sys.exit("No product IDs specified.")

  os.makedirs(args.outdir, exist_ok=True)
  for pid in pids:
    try:
      process_product(pid, args.outdir, use_polar=args.usgs_polar)
    except Exception as e:
      print(f"Error processing {pid}: {e}")

if __name__ == "__main__":
  main()
