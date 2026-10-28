#!/bin/bash
# Central environment for the SfsPipeline bash workers. Each worker sources this
# once instead of repeating the same block.
#
# This file holds NO machine-specific paths. Set ASPROOT, ISISROOT, and ISISDATA
# per machine in your .bashrc (see README step 6). They differ between a laptop
# and an HPC, which is what per-machine shell config is for. This file validates
# that they are set and exist, derives the relative vars, puts the ASP and ISIS
# tools on PATH, and points GDAL/PROJ at the ASP bundle's data.
#
# It does NOT set LD_LIBRARY_PATH: every ASP tool is a bin/ wrapper that sets
# LD_LIBRARY_PATH, CSM_PLUGIN_PATH, and GDAL/PROJ itself before exec'ing the real
# binary, so a worker that calls ASP tools through bin/ needs none of that set by
# hand. GDAL/PROJ below is only for a bare gdal/gdalwarp call from the bundle.
#
# A worker sources it as:
#   binDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$binDir/sfs_env.sh" || exit 1
# The "|| exit 1" is what aborts the worker when a required var is missing: a
# sourced file's "return 1" propagates as the source command's exit status.

# Require a per-machine var to be set and to point at an existing directory. No
# silent fallback to a personal layout: a missing or wrong path is a clear error
# here, not a mystery failure deep in a tool later.
sfs_require() {
  local name=$1
  local val=${!name:-}
  if [ -z "$val" ]; then
    echo "sfs_env.sh: $name is not set. Set ASPROOT, ISISROOT, and ISISDATA in" \
         "your .bashrc (see README step 6)." >&2
    return 1
  fi
  if [ ! -d "$val" ]; then
    echo "sfs_env.sh: $name=$val does not exist. Fix it in your .bashrc" \
         "(see README step 6)." >&2
    return 1
  fi
}

sfs_require ASPROOT  || return 1
sfs_require ISISROOT || return 1
sfs_require ISISDATA || return 1

# Derived, so safe to default (defined relative to the vars above).
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}

# ASP and ISIS tools on PATH. libexec holds ASP helper binaries that some tools
# spawn by name; bin precedes it so the wrappers always win.
export PATH=$ASPROOT/bin:$ASPROOT/libexec:$ISISROOT/bin:$PATH

# GDAL/PROJ data from the ASP bundle, for a bare gdal/gdalwarp call (ASP tool
# wrappers re-point these themselves, so this only matters outside a wrapper).
if [ -d "$ASPROOT/share/proj" ]; then
  export GDAL_DATA=$ASPROOT/share/gdal
  export PROJ_DATA=$ASPROOT/share/proj
  export PROJ_LIB=$ASPROOT/share/proj
fi

# Standard worker hygiene.
umask 022    # outputs readable by others
ulimit -c 0  # no core dumps (a core dump to Lustre can wedge a PBS node)
