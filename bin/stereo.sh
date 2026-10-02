#!/usr/bin/env bash

# Must have 3 arguments. Print usage on failure.
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <i> <j> <out>"
    exit 1
fi

i=$1; shift
j=$1; shift
outd=$1; shift

export outDir=${outd}/${i}__${j}
export dem=Site07_final_adj_1mpp_surf.tif
export proj='+proj=stere +lat_0=-90 +lon_0=0 +k=1 +x_0=0 +y_0=0 +R=1737400 +units=m +no_defs'
export projpath=mapproj0
export cubpath=LROC_Images
export bapref=ba0/run
export PATH="${ASPROOT:+$ASPROOT/bin:}${PATH}"
export nodes=nodes.list

export out=${outDir}/output.txt
echo Will write the output to $out
mkdir -p $outDir

parallel_stereo \
	${projpath}/${i}.ce.proj.tif \
	${projpath}/${j}.ce.proj.tif \
	${cubpath}/${i}.ce.json \
	${cubpath}/${j}.ce.json \
	--bundle-adjust-prefix ${bapref} \
	--subpixel-mode 9 \
	--stereo-algorithm asp_mgm \
	${outDir}/run \
	${dem} >> ${out}

point2dem --errorimage --tr 1 --t_srs "$proj" ${outDir}/run-PC.tif >> $out
