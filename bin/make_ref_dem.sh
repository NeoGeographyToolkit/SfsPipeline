#!/bin/bash

# Build an ASP-ready reference DEM: reproject and regrid a source DEM to a fixed
# target grid and resolution with cubic-spline interpolation and the 256-block
# tiling ASP prefers, then optionally blur to suppress spikes.
#
# For SfS the target extent should be snapped OUTWARD to half-integer edges so
# that, at 1 m/pixel, each ground pixel is centered on an integer grid point.
# sfs_blend requires this (see the terrain bounds section of sfs_usage.rst).
#
# Args:
#   src       source DEM (any projection)
#   out       output regridded DEM (.tif)
#   te        target extent, ONE quoted string: "xmin ymin xmax ymax"
#   tr        target resolution in meters (applied as -tr tr tr)
#   currDir   work dir to cd into
#   proj      optional target proj4/wkt; if given, passed as -t_srs (needs PROJ data)
#   blurSigma optional; if > 0, also writes <out>_blur.tif blurred by that sigma.
#             Blur is OFF unless you pass this. A blur smears fine terrain and adds
#             its own bias, so use the honest <out> as the height constraint, and a
#             blurred DEM (if any) only as a mapprojection drape surface.
#
# Anchor-DEM pad (jitter_solve): to build the padded --anchor-dem that pins
# borderline/edge frames, run this with the SAME src (genuine source LOLA, e.g.
# the Barker LDEM), same tr and proj as the domain DEM, but a 'te' extended by the
# pad beyond the domain (e.g. +4000 m = +4 km each side at 1 m/px; 10-40 km for
# long tracks). Feed the result to jitter_gcp.sh / jitter_solve.sh via ANCHOR_DEM;
# keep heights-from-dem and mapproj-dem on the domain DEM. The pad must be real
# source terrain, never fabricated fill.
#
# No PBS logic here; the caller (project notes) sets any qsub. Build on a compute
# node (devel), not the head node.

if [ "$#" -lt 5 ]; then
  echo "Usage: $0 src out '<xmin ymin xmax ymax>' tr currDir [proj] [blurSigma]"
  exit 1
fi
src=$1; out=$2; te=$3; tr=$4; currDir=$5; proj=$6; blurSigma=$7
cd "$currDir"

# GDAL and dem_mosaic from the ASP build (ASPROOT; set it in init_asp.sh or
# your shell rc, else it defaults to ~/projects/BinaryBuilder/StereoPipeline).
export ASPROOT=${ASPROOT:-$HOME/projects/BinaryBuilder/StereoPipeline}
export PATH=$ASPROOT/bin:$PATH
export GDAL_DATA=$ASPROOT/share/gdal PROJ_DATA=$ASPROOT/share/proj PROJ_LIB=$ASPROOT/share/proj
export GDAL_NUM_THREADS=1
umask 022 # make files readable by others
ulimit -c 0 # no core dumps

log=output_$(basename "$out" .tif).txt
exec >> "$log" 2>&1
echo "===== make_ref_dem start: $(date) ====="
echo "src=$src out=$out te=[$te] tr=$tr proj=[$proj] blurSigma=[$blurSigma]"

opts=(-overwrite -r cubicspline -tr "$tr" "$tr" -te $te
      -co COMPRESSION=LZW -co TILED=yes -co INTERLEAVE=BAND
      -co BLOCKXSIZE=256 -co BLOCKYSIZE=256 -co BIGTIFF=yes)
[ -n "$proj" ] && opts+=(-t_srs "$proj")
gdalwarp "${opts[@]}" "$src" "$out"
echo "regrid rc=$?"
gdalinfo -stats "$out" | grep -iE "Size is|Origin|Pixel Size|Minimum=|Maximum=|Mean=|VALID_PERCENT"

if [ -n "$blurSigma" ] && [ "$blurSigma" != "0" ]; then
  blur="${out%.tif}_blur.tif"
  echo "blurring to $blur (sigma $blurSigma)"
  dem_mosaic --dem-blur-sigma "$blurSigma" "$out" -o "$blur" --threads 1
  gdalinfo -stats "$blur" | grep -iE "Size is|Origin|Minimum=|Maximum=|Mean=|VALID_PERCENT"
fi
echo "===== make_ref_dem done: $(date) ====="
