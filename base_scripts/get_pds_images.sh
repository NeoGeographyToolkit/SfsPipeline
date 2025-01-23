#!/usr/bin/env bash
#  Usage

if [ "$#" -ne 1 ]; then 
    echo "Usage: $0 <observation id list>"
    exit 1
fi

mkdir LROC_Images
export cdx=~/Work/Artemis/CUMINDEX.TAB
export idlist=${1}
export servers=nodes.list

# Parallelizing isn't worth it if the network is the bottleneck.

for i in `cat ${idlist}`; do
	img=`grep ${1} ${cdx} | cut -d"," -f2 | cut -d'"' -f2`
	wget http://pds.lroc.asu.edu/data/${img} -P LROC_Images/ 
done

