#!/usr/bin/env bash
# Convert to cube files ready for ASP.

# Use:
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <obsid>"
    exit 1
fi

export ASP=~moses/Work/Artemis/ASP
export ALE=~moses/Work/mambaforge/envs/asp
export ISISROOT=/Work/Anaconda/anaconda3_2022_Oct/envs/isis
export ISISDATA=/Work/ISIS3Data
export LI=~moses/Work/Artemis/Peak_Near_Shackleton/LROC_Images
export servers=nodes.list
export workdir=~moses/Work/Artemis/Peak_Near_Shackleton

export obsid=${1//.IMG/}
echo ${obsid}

echo "img2isis"
if [ ! -f ${LI}/${obsid}.cub ]; then ${ISISROOT}/bin/lronac2isis fr=${LI}/${obsid}.IMG to=${LI}/${obsid}.cub; fi

echo "spiceinit"
# Sometimes we have to use web=true if the local spice data are missing.
#if [ ! -f ${LI}/${obsid}.cal.cub ]; then ${ISISROOT}/bin/spiceinit fr=${LI}/${obsid}.cub shape=ellipsoid web=true; fi
if [ ! -f ${LI}/${obsid}.cal.cub ]; then ${ISISROOT}/bin/spiceinit fr=${LI}/${obsid}.cub shape=ellipsoid; fi

echo "cal"
if [ ! -f ${LI}/${obsid}.cal.cub ]; then ${ISISROOT}/bin/lronaccal fr=${LI}/${obsid}.cub to=${LI}/${obsid}.cal.cub; fi

echo "lronacecho"
${ISISROOT}/bin/lronacecho fr=${LI}/${obsid}.cal.cub to=${LI}/${obsid}.ce.cub

echo "isd_generate"
${ALE}/bin/isd_generate ${LI}/${obsid}.ce.cub
