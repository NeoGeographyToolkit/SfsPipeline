#!/bin/bash

# Serve a folder of COGs (and JSON) over HTTP with rclone, read-only, for remote
# QA / viewing in QGIS. De-pbs'd from serve_folder.pbs. rclone comes from the
# SfsPipeline conda environment (activate it first, e.g. source init_sfs.sh).
#
# Args:
#   currDir   directory to serve, pass as $(pwd)
# Env:
#   PORT   HTTP port (default 8080)

if [ "$#" -lt 1 ]; then echo "Usage: $0 currDir"; exit 1; fi
currDir=$1
cd "$currDir" || exit 1

port=${PORT:-8080}
echo "serving $currDir over http on port $port (read-only)"
rclone serve http .            \
    --addr ":$port"            \
    --read-only                \
    --copy-links               \
    --no-modtime               \
    --disable-http-keep-alives \
    --buffer-size 64Mi         \
    --transfers 16             \
    --vfs-cache-mode off       \
    --include "*.tif"          \
    --include "*.json"         \
    --stats 120s               \
    --log-level INFO
