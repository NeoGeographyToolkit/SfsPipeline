#!/usr/bin/env python3
# Query the PDS Geosciences Node ODE REST API for Lunar Reconnaissance Orbiter (LRO)
# Narrow Angle Camera (NAC) images over a geographic bounding box or DEM extent.
#
# Emits clean product ID lists (for prepare_usgs_nac.py, fetch_lro_nac.sh, or paired
# camera lists) and direct .IMG download URLs (for download_all.sh).
#
# Integration in the SfS Workflow:
#   1. Query candidate images intersecting a site or reference DEM:
#        query_lro.py --dem ref_dem.tif --margin-km 1.0 \
#          --min-incidence 70 --max-incidence 90 \
#          --max-resolution 1.5 \
#          --output-urls lists/urls.txt \
#          --output-products lists/products.txt
#   2. Download raw EDR images (.IMG) in bulk:
#        download_all.sh lists/urls.txt
#   3. Process / calibrate via prepare_usgs_nac.py or process_all.sh.
#
# Arguments and Options:
#   --lat-lon MINLAT MAXLAT WESTLON EASTLON
#       Geographic bounding box in degrees (lat [-90, 90], lon [-180, 180] or [0, 360]).
#   --dem DEM.tif
#       Extract the bounding box directly from a georeferenced DEM GeoTIFF.
#   --margin-km MARGIN_KM
#       Expand DEM geographic bounding box by this margin in km (default: 0.0).
#   --pt PT
#       PDS product type: default EDRNAC4 (raw EDR .IMG); CDRNAC4 for calibrated.
#   --min-incidence DEG, --max-incidence DEG
#       Filter by solar incidence angle in degrees (e.g. 70 to 90 for grazing sun).
#   --min-emission DEG, --max-emission DEG
#       Filter by camera emission angle in degrees.
#   --max-resolution METERS
#       Filter by maximum ground sampling distance in meters/pixel (e.g. 1.5).
#   --start-time UTC, --stop-time UTC
#       Filter by observation time range (e.g. 2018-01-01).
#   --limit N
#       ODE pagination limit per request (default: 100).
#   --max-products N
#       Cap total number of retrieved products (default: 0 = unlimited).
#   --output-urls FILE
#       Path to write direct .IMG download URLs (1 per line, for download_all.sh).
#   --output-products FILE
#       Path to write unique product IDs (1 per line, e.g. M109041171LE).
#   --output-table FILE
#       Path to write whitespace-separated table with metadata (ID, time, angles, GSD, URL).
#
# Examples:
#   # Query by lat/lon box, save URLs for download_all.sh and IDs for processing:
#   query_lro.py --lat-lon -84.95 -84.45 20.7 27.0 \
#     --output-urls urls.txt --output-products products.txt
#
#   # Query using a reference DEM bounding box with 1 km margin and low-sun filter:
#   query_lro.py --dem ref/ref_dem_1mpp.tif --margin-km 1.0 \
#     --min-incidence 70 --max-incidence 90 \
#     --output-urls urls.txt --output-products products.txt
#
#   # Download all discovered images:
#   download_all.sh urls.txt


import argparse
import json
import math
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request

ODE_URL = "https://oderest.rsl.wustl.edu/live2/"
USER_AGENT = "NASA-SfS-Analysis/1.0"
MOON_RADIUS_METERS = 1737400.0

def get_dem_bounds(dem_path, margin_km=0.0):
  """Extract lat/lon bounding box from a georeferenced DEM file."""
  cmd = ["gdalinfo", "-json", dem_path]
  res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
  if res.returncode != 0:
    raise RuntimeError(f"gdalinfo failed on {dem_path}: {res.stderr}")

  info = json.loads(res.stdout)
  corners = info.get("cornerCoordinates", {})
  if not corners:
    raise RuntimeError(f"No cornerCoordinates found in gdalinfo output for {dem_path}")

  srs = info.get("coordinateSystem", {}).get("wkt", "")
  if not srs:
    raise RuntimeError(f"No coordinateSystem found for {dem_path}")

  # Points: upperLeft, lowerLeft, upperRight, lowerRight, center
  pts = [
    corners.get("upperLeft"),
    corners.get("lowerLeft"),
    corners.get("upperRight"),
    corners.get("lowerRight"),
    corners.get("center")
  ]
  pts = [p for p in pts if p is not None]

  # Transform native DEM coordinates to lat/lon on lunar sphere
  pts_str = "\n".join(f"{p[0]} {p[1]}" for p in pts)
  trans_cmd = [
    "gdaltransform",
    "-s_srs", srs,
    "-t_srs", f"+proj=latlong +R={MOON_RADIUS_METERS} +no_defs"
  ]
  t_res = subprocess.run(trans_cmd, input=pts_str, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, universal_newlines=True)
  if t_res.returncode != 0:
    raise RuntimeError(f"gdaltransform failed: {t_res.stderr}")

  lats = []
  lons = []
  for line in t_res.stdout.strip().splitlines():
    tokens = line.split()
    if len(tokens) >= 2:
      lon = float(tokens[0])
      lat = float(tokens[1])
      # Normalize lon to [-180, 180] or [0, 360]
      lons.append(lon)
      lats.append(lat)

  if not lats or not lons:
    raise RuntimeError("Failed to transform DEM corner coordinates.")

  minlat = min(lats)
  maxlat = max(lats)
  westlon = min(lons)
  eastlon = max(lons)

  if margin_km > 0.0:
    # Degree margin approximation
    deg_per_km_lat = 180.0 / (math.pi * (MOON_RADIUS_METERS / 1000.0))
    lat_margin = margin_km * deg_per_km_lat
    mid_lat_rad = math.radians(0.5 * (minlat + maxlat))
    cos_lat = max(0.01, math.cos(mid_lat_rad))
    lon_margin = lat_margin / cos_lat

    minlat = max(-90.0, minlat - lat_margin)
    maxlat = min(90.0, maxlat + lat_margin)
    westlon = westlon - lon_margin
    eastlon = eastlon + lon_margin

  return minlat, maxlat, westlon, eastlon

def query_ode_products(minlat, maxlat, westlon, eastlon,
                       pt="EDRNAC4",
                       min_inc=None, max_inc=None,
                       min_em=None, max_em=None,
                       max_res=None,
                       start_time=None, stop_time=None,
                       limit=100, max_products=0):
  """Query ODE REST API with pagination and optional filters."""
  offset = 0
  all_products = []
  seen_pids = set()

  print(f"Querying ODE: lat [{minlat:.4f}, {maxlat:.4f}], lon [{westlon:.4f}, {eastlon:.4f}], pt={pt}...")

  while True:
    params = {
      "query": "product",
      "output": "JSON",
      "target": "moon",
      "ihid": "LRO",
      "iid": "LROC",
      "pt": pt,
      "minlat": f"{minlat:.6f}",
      "maxlat": f"{maxlat:.6f}",
      "westlon": f"{westlon:.6f}",
      "eastlon": f"{eastlon:.6f}",
      "results": "pmdf",
      "limit": str(limit),
      "offset": str(offset)
    }

    if min_inc is not None:
      params["minimumincidenceangle"] = str(min_inc)
    if max_inc is not None:
      params["maximumincidenceangle"] = str(max_inc)
    if min_em is not None:
      params["minimumemissionangle"] = str(min_em)
    if max_em is not None:
      params["maximumemissionangle"] = str(max_em)
    if start_time is not None:
      params["observationtimemin"] = str(start_time)
    if stop_time is not None:
      params["observationtimemax"] = str(stop_time)

    url = f"{ODE_URL}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})

    data = None
    for attempt in range(5):
      try:
        with urllib.request.urlopen(req, timeout=30) as resp:
          data = json.loads(resp.read().decode("utf-8"))
        break
      except Exception as e:
        wait_sec = 2 ** attempt
        print(f"  Attempt {attempt + 1} failed: {e}. Retrying in {wait_sec}s...")
        time.sleep(wait_sec)

    if not data:
      print("  Failed to retrieve page from ODE after 5 attempts.")
      break

    ode = data.get("ODEResults", {})
    status = ode.get("Status")
    if status != "Success":
      print(f"  ODE status message: {status}")
      break

    prods_block = ode.get("Products")
    if not prods_block:
      break
    prods = prods_block.get("Product", [])
    if isinstance(prods, dict):
      prods = [prods]
    if not prods:
      break

    page_added = 0
    for p in prods:
      lbl_name = p.get("LabelFileName", "")
      pid = p.get("pdsid", "")
      prod_id = lbl_name.replace(".xml", "").replace(".XML", "").upper()
      if not prod_id and pid:
        prod_id = pid.replace("nac.", "").upper()
      if not prod_id or prod_id in seen_pids:
        continue

      # Extract GSD / Map resolution
      res_str = p.get("Map_resolution", "")
      try:
        gsd = float(res_str) if res_str else None
      except ValueError:
        gsd = None

      if max_res is not None and gsd is not None and gsd > max_res:
        continue

      # Find .IMG URL
      img_url = ""
      files_block = p.get("Product_files", {}).get("Product_file", [])
      if isinstance(files_block, dict):
        files_block = [files_block]
      for f in files_block:
        u = f.get("URL", "")
        if u.upper().endswith(".IMG"):
          img_url = u
          break

      item = {
        "product_id": prod_id,
        "pdsid": pid,
        "url": img_url,
        "time": p.get("Observation_time", ""),
        "incidence": p.get("Incidence_angle", ""),
        "emission": p.get("Emission_angle", ""),
        "phase": p.get("Phase_angle", ""),
        "resolution": str(gsd) if gsd is not None else "",
        "center_lat": p.get("Center_latitude", ""),
        "center_lon": p.get("Center_longitude", "")
      }
      seen_pids.add(prod_id)
      all_products.append(item)
      page_added += 1

      if max_products > 0 and len(all_products) >= max_products:
        break

    print(f"  Offset {offset}: added {page_added} items ({len(all_products)} total so far)...")
    if max_products > 0 and len(all_products) >= max_products:
      print(f"Reached max requested products ({max_products}).")
      break
    if len(prods) < limit:
      break
    offset += limit
    time.sleep(0.3)

  return all_products

def main():
  parser = argparse.ArgumentParser(
    description="Query PDS ODE REST API for LRO NAC products by lat/lon or DEM bounds."
  )
  group = parser.add_mutually_exclusive_group(required=True)
  group.add_argument(
    "--lat-lon", nargs=4, type=float, metavar=("MINLAT", "MAXLAT", "WESTLON", "EASTLON"),
    help="Geographic bounding box in degrees (lat [-90, 90], lon [-180, 180] or [0, 360])."
  )
  group.add_argument(
    "--dem", type=str, metavar="DEM.tif",
    help="Reference DEM file to derive geographic bounding box from."
  )

  parser.add_argument("--margin-km", type=float, default=0.0,
                      help="Expand DEM bounding box by this margin in km (default: 0.0).")
  parser.add_argument("--pt", type=str, default="EDRNAC4",
                      help="ODE product type (default: EDRNAC4 for raw EDR; CDRNAC4 for calibrated).")
  parser.add_argument("--min-incidence", type=float, default=None,
                      help="Minimum solar incidence angle in degrees (e.g. 70).")
  parser.add_argument("--max-incidence", type=float, default=None,
                      help="Maximum solar incidence angle in degrees (e.g. 90).")
  parser.add_argument("--min-emission", type=float, default=None,
                      help="Minimum emission angle in degrees.")
  parser.add_argument("--max-emission", type=float, default=None,
                      help="Maximum emission angle in degrees.")
  parser.add_argument("--max-resolution", type=float, default=None,
                      help="Maximum ground resolution in meters/pixel (e.g. 1.5).")
  parser.add_argument("--start-time", type=str, default=None,
                      help="Observation start time (UTC, e.g. 2020-01-01).")
  parser.add_argument("--stop-time", type=str, default=None,
                      help="Observation stop time (UTC, e.g. 2024-01-01).")
  parser.add_argument("--limit", type=int, default=100,
                      help="Query page size (default: 100).")
  parser.add_argument("--max-products", type=int, default=0,
                      help="Maximum products to retrieve (default: 0 for all).")

  parser.add_argument("--output-urls", type=str, default=None,
                      help="Output file for direct .IMG download URLs (feeds into download_all.sh).")
  parser.add_argument("--output-products", type=str, default=None,
                      help="Output file for product IDs (feeds into prepare_usgs_nac.py / lists).")
  parser.add_argument("--output-table", type=str, default=None,
                      help="Output file for detailed metadata table.")

  args = parser.parse_args()

  if args.dem:
    if not os.path.isfile(args.dem):
      sys.exit(f"Error: DEM file does not exist: {args.dem}")
    minlat, maxlat, westlon, eastlon = get_dem_bounds(args.dem, margin_km=args.margin_km)
    print(f"Extracted bounds from DEM {args.dem} (margin {args.margin_km} km):")
    print(f"  Lat: [{minlat:.4f}, {maxlat:.4f}] deg, Lon: [{westlon:.4f}, {eastlon:.4f}] deg")
  else:
    minlat, maxlat, westlon, eastlon = args.lat_lon

  products = query_ode_products(
    minlat=minlat, maxlat=maxlat, westlon=westlon, eastlon=eastlon,
    pt=args.pt,
    min_inc=args.min_incidence, max_inc=args.max_incidence,
    min_em=args.min_emission, max_em=args.max_emission,
    max_res=args.max_resolution,
    start_time=args.start_time, stop_time=args.stop_time,
    limit=args.limit, max_products=args.max_products
  )

  # Sort by product ID
  products.sort(key=lambda x: x["product_id"])

  print(f"\nTotal unique products retrieved: {len(products)}")

  if args.output_urls:
    os.makedirs(os.path.dirname(os.path.abspath(args.output_urls)), exist_ok=True)
    urls = [p["url"] for p in products if p["url"]]
    with open(args.output_urls, "w") as f:
      for u in urls:
        f.write(f"{u}\n")
    print(f"Wrote {len(urls)} download URLs to {args.output_urls}")

  if args.output_products:
    os.makedirs(os.path.dirname(os.path.abspath(args.output_products)), exist_ok=True)
    with open(args.output_products, "w") as f:
      for p in products:
        f.write(f"{p['product_id']}\n")
    print(f"Wrote {len(products)} product IDs to {args.output_products}")

  if args.output_table:
    os.makedirs(os.path.dirname(os.path.abspath(args.output_table)), exist_ok=True)
    with open(args.output_table, "w") as f:
      f.write("# product_id utc_time incidence emission phase resolution_m url\n")
      for p in products:
        f.write(f"{p['product_id']} {p['time']} {p['incidence']} {p['emission']} {p['phase']} {p['resolution']} {p['url']}\n")
    print(f"Wrote metadata table to {args.output_table}")

  if not args.output_urls and not args.output_products and not args.output_table:
    print("\nSample retrieved products (first 10):")
    for p in products[:10]:
      print(f"  {p['product_id']}: inc={p['incidence']} em={p['emission']} gsd={p['resolution']} url={p['url']}")

if __name__ == "__main__":
  main()
