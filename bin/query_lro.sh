#!/bin/bash
# Query the PDS Geosciences Node ODE REST API for LRO NAC images by lat/lon
# bounding box or DEM extent.
#
# Emits product ID lists (for prepare_usgs_nac.py or fetch_lro_nac.sh) and direct
# .IMG download URLs (for download_all.sh).
#
# Usage:
#   query_lro.sh --lat-lon <minlat> <maxlat> <westlon> <eastlon> [options]
#   query_lro.sh --dem <dem.tif> [options]
#
# Examples:
#   # Query by lat/lon box, save URLs for download_all.sh and IDs for processing:
#   query_lro.sh --lat-lon -84.95 -84.45 20.7 27.0 \
#     --output-urls urls.txt --output-products products.txt
#
#   # Query using reference DEM extent with 1 km margin and low-sun filter:
#   query_lro.sh --dem ref/ref_dem_1mpp.tif --margin-km 1.0 \
#     --min-incidence 70 --max-incidence 90 \
#     --output-urls urls.txt --output-products products.txt

dir=$(dirname "$0")
python3 "$dir/query_lro.py" "$@"
