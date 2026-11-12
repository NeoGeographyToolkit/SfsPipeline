#!/bin/bash

# Hillshade DEMs and find correlation

leftDem=$1; shift
rightDem=$1; shift
currDir=$1; shift
stereoDir=$1; shift
maxSearch=$1; shift   # optional 5th arg: corr search half-window in px (default 25)
[ -z "$maxSearch" ] && maxSearch=25
cd $currDir

# Correlation algorithm is overridable for sensitivity checks (env). Default asp_mgm
# with subpixel-mode 9 (blend). For asp_bm pass STEREO_ALGO=asp_bm SUBPIX=2 (bm has no
# mode 9). The DEM hillshades and everything else are identical, so this isolates the
# algorithm's effect on the dh/dv pattern.
algo=${STEREO_ALGO:-asp_mgm}
subpix=${SUBPIX:-9}

# Setup stereoDir name if not provided
if [ "$stereoDir" = "" ]; then
  stereoDir=$(basename $leftDem)_$(basename $rightDem)
  stereoDir=$(echo $stereoDir | perl -p -e "s#\.tif##g")
fi

echo leftDem=$leftDem
echo rightDem=$rightDem
echo currDir=$currDir
echo stereoDir=$stereoDir

# Set up the environment (ASPROOT, ISISROOT, ISISDATA from your .bashrc)
binDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$binDir/sfs_env.sh" || exit 1

# Set up the output file
mkdir -p $stereoDir
out=${stereoDir}/output_corr.txt
rm -fv $out
echo Writing the output to: $out

# Set up the nodes file
if [ "$PBS_NODEFILE" = "" ]; then
    # To run locally
    PBS_NODEFILE=$(uname -n).txt
    echo $(uname -n) > $PBS_NODEFILE
fi
echo Head node: $(uname -n) >> $out
echo Machines: $(cat ${PBS_NODEFILE}) >> $out
# Ensure some separation in the output file
echo " " >> $out
echo " " >> $out

# Hillshade the DEMs with a grazing sun to bring out relief contrast.
# HS_ELEV: sun elevation in degrees (default 15, grazing). A grazing sun shows the finest
#   relief and spreads the shade across the full 0-255 range, which the 8-bit subpixel
#   optimizer reads; a high sun washes the relief out and gives fewer valid matches.
# HS_AZIMUTH: sun azimuth. A single fixed azimuth (ASP hillshade's own default is 300)
#   blacks out whatever slope faces away from it, and a black region carries no texture, so
#   the correlator finds no disparity exactly there. The good azimuth is site-specific.
#   Default "auto": hillshade the reference DEM at several azimuths on a downsampled copy and
#   keep the best-lit one (highest mean brightness), applied to BOTH DEMs. Pass a number to pin it.
# SKIP_HILLSHADE=1 correlates the two inputs DIRECTLY, without hillshading. Use this when the
#   inputs are already textured images (mapprojected orthoimages or max-lit mosaics), not DEMs.
hsElev=${HS_ELEV:-15}
hsAz=${HS_AZIMUTH:-auto}

pick_azimuth() { # $1 = DEM to probe; echoes the best-lit azimuth at hsElev
  probeDem=$1
  small=${stereoDir}/az_probe.tif
  gdal_translate -q -outsize 1000 0 "$probeDem" "$small" >> $out 2>&1
  best=300; bestMean=-1
  for az in 0 45 90 135 180 225 270 315; do
    shade=${stereoDir}/az_probe_a${az}.tif
    gdaldem hillshade -az $az -alt $hsElev -compute_edges "$small" "$shade" >> $out 2>&1
    mean=$(gdalinfo -stats "$shade" 2>/dev/null | perl -ne 'print $1 if /STATISTICS_MEAN=([0-9.]+)/')
    echo "  probe azimuth $az mean brightness $mean" >> $out 2>&1
    if [ -n "$mean" ] && awk "BEGIN{exit !($mean > $bestMean)}"; then bestMean=$mean; best=$az; fi
  done
  echo $best
}

if [ -n "$SKIP_HILLSHADE" ]; then
    leftHill=$leftDem
    rightHill=$rightDem
    echo "SKIP_HILLSHADE set: correlating inputs directly, no hillshade" >> $out 2>&1
else
    if [ "$hsAz" = "auto" ]; then
        hsAz=$(pick_azimuth "$leftDem")
        echo "Auto-selected hillshade azimuth: $hsAz (elevation $hsElev)" | tee -a $out
    else
        echo "Hillshade azimuth $hsAz (elevation $hsElev)" | tee -a $out
    fi
    leftHill=${leftDem%.tif}_hill.tif
    rightHill=${rightDem%.tif}_hill.tif
    # Skip if done already
    if [ ! -f "$leftHill" ]; then
        echo Creating left hillshade: $leftHill
        hillshade -e $hsElev -a $hsAz $leftDem -o $leftHill >> $out 2>&1
    else
        echo Left hillshade $leftHill exists already, skipping >> $out 2>&1
    fi
    if [ ! -f "$rightHill" ]; then
        echo Creating right hillshade: $rightHill
        hillshade -e $hsElev -a $hsAz $rightDem -o $rightHill >> $out 2>&1
    else
        echo Right hillshade $rightHill exists already, skipping >> $out 2>&1
    fi
fi

# Build image pyramids for the hillshades
stereo_gui                     \
  --create-image-pyramids-only \
  $leftHill $rightHill         \
  >> $out 2>&1

# Run asp_mgm with a large kernel size to overcome noise. It is assumed that
# both input DEMs have the same extent, size, and resolution. Use a corr search
# window somewhat bigger than the expected shift.
s=$maxSearch
parallel_stereo                      \
  --correlator-mode                  \
  --stereo-algorithm $algo           \
  --corr-kernel 9 9                  \
  --ip-per-image 40000               \
  --subpixel-mode $subpix            \
  --corr-search -$s -$s $s $s        \
  --processes 8                      \
  --nodes-list $PBS_NODEFILE         \
  $leftHill $rightHill               \
  --num-matches-from-disparity 40000 \
  $stereoDir/run >> $out 2>&1

# Look at disparity bands
for b in 1 2 3; do 
  gdal_translate                 \
  -co compress=lzw -co TILED=yes \
  -co INTERLEAVE=BAND            \
  -co BLOCKXSIZE=256             \
  -co BLOCKYSIZE=256             \
  -co BIGTIFF=YES                \
  -b $b ${stereoDir}/run-F.tif   \
  ${stereoDir}/run-F_b${b}.tif >> $out 2>&1
done

# Make the invalid disparity no-data
t=1e+6
for b in 1 2; do 
  image_calc -c "(var_0 + $t)*var_1 - $t" \
  --output-nodata-value -$t               \
  --cache-size-mb 3000                    \
  ${stereoDir}/run-F_b${b}.tif            \
  ${stereoDir}/run-F_b3.tif               \
  -o ${stereoDir}/run-F_b${b}_nodata.tif  \
  >> $out 2>&1
done

# Build low-res pyramids
stereo_gui                         \
  --create-image-pyramids-only     \
  ${stereoDir}/run-F_b1_nodata.tif \
  ${stereoDir}/run-F_b2_nodata.tif \
  >> $out 2>&1
  
# # View colorized disparity with masked no-data
echo sgm -10 10 --grid-cols 1 ${stereoDir}/run-F_b1_nodata.tif ${stereoDir}/run-F_b2_nodata.tif 

# OPTIONAL pc_align - OFF by default. For a dh/dv sensitivity readout we only need the
# correlator disparity (run-F_b1/b2_nodata.tif); pc_align is unnecessary and, on a sparse
# disparity, fails noisily (missing align-trans_source.tif). Set DO_PC_ALIGN=1 to also
# align and emit an aligned DEM.
if [ "${DO_PC_ALIGN:-0}" = "1" ]; then
matchFile=$(ls $stereoDir/run-disp*.match) # there should be only one
echo matchFile=$matchFile
pc_align                                     \
  --max-displacement -1                      \
  --num-iterations 0                         \
  --max-num-reference-points 1000000         \
  --match-file $matchFile                    \
  --initial-transform-from-hillshading rigid \
  --initial-transform-ransac-params 1000 3   \
  --save-transformed-source-points           \
  $leftDem $rightDem                         \
  -o $stereoDir/align                        \
  >> $out 2>&1
point2dem --tr 1.0                           \
  $stereoDir/align-trans_source.tif          \
  >> $out 2>&1
  
# Hillshade
f=$stereoDir/align-trans_source.tif
# Replace .tif by -DEM.tif
f=${f%.tif}-DEM.tif
g=${f%.tif}_hill.tif
hillshade -e $hsElev -a $hsAz $f -o $g >> $out 2>&1

# Build image pyramids for the hillshade
stereo_gui --create-image-pyramids-only \
  $leftHill $rightHill $g               \
  >> $out 2>&1
fi
