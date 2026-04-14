#!/usr/bin/env bash
# source bashrc
[ -f ~/.bashrc ] && source ~/.bashrc
# Log the PBS_NODEFILE if available
if [ -n "$PBS_NODEFILE" ]; then
    echo "Running on PBS node: $(uname -a)"
fi
##############################################
# source asp environment
source init_isis.sh
# echo out ISISDATA and ISISROOT
echo ISIS data is "$ISISDATA" 
echo ISIS root is "$ISISROOT"
# echo out PATH
echo PATH is "$PATH"
echo PYTHONPATH is "$PYTHONPATH"
################################################
# Must have at least 1 argument. Print usage on failure.
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <i>"
    exit 1
fi
in_img=$1
echo IN IMG is "$in_img"
# get the raw cub name
raw_cub="${in_img%.IMG}.raw.cub"
# get the cal cub name
cal_cub="${in_img%.IMG}.cal.cub"
# get the final cub name
ech_cub="${in_img%.IMG}.ech.cub"
# convert the IMG to a CUB
lronac2isis from="$in_img" to="$raw_cub"
# run spiceinit with smithed kernels, fallback to recon otherwise
spiceinit from="$raw_cub" spksmithed=true spkrecon=true extra=/nobackupp27/aannex/DATA/usgs_polar_only.mk web=false
#spiceinit from="$raw_cub" spk=/nobackupnfs1/oalexan1/projects/isis3data/lro_south/usgs_polar_spk.mk ck=/nobackupnfs1/oalexan1/projects/isis3data/lro_south/usgs_polar_ck.mk web=false
# if [[ "$#" -eq 2 ]]; then
#    echo "USING SP KERNELS"
#    # we want to use meta kernels for the south pole
#    #spiceinit from="$raw_cub"  extra=/nobackupp27/aannex/DATA/usgs_polar_only.mk web=false
#    #spiceinit from="$raw_cub" spk=/nobackupp27/aannex/DATA/usgs_polar_only_spk.mk ck=/nobackupp27/aannex/DATA/usgs_polar_only_ck.mk web=false
#    #spiceinit from="$raw_cub" spk=/nobackupp27/aannex/DATA/usgs_polar_spk.mk ck=/nobackupp27/aannex/DATA/usgs_polar_ck.mk web=false
#    #spiceinit from="$raw_cub" spk=/nobackupnfs1/oalexan1/projects/isis3data/lro_south/usgs_polar_spk.mk ck=/nobackupnfs1/oalexan1/projects/isis3data/lro_south/usgs_polar_ck.mk web=false
# fi  
# run lro nac calibration
lronaccal from="$raw_cub" to="$cal_cub"
# cleanup raw cub
rm "$raw_cub"
# run echo correction
lronacecho from="$cal_cub" to="$ech_cub"
# cleanup cal cub
rm "$cal_cub"
# use isd_generate to generate CSM camera model using only spiceinit info from ISIS
isd_generate -i "$ech_cub"
# done!

