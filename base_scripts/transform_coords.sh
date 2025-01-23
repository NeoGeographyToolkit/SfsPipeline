#!/usr/bin/env bash
#
#gdaltransform
#
#
#Polygon is in polar stereographic

# Proj string for long_lat
# '+proj=longlat +a=1737400 +b=1737400'
#
# Proj string for polar sterographic
# '+proj=stere +lat_0=-90 +lon_0=0 +R=1737400 +units=m'
#

ASP=/Work/Artemis_Lunar_Landing_Sites/ASP
export PATH=${ASP}/bin:${PATH}
rm transform_cmd.sh

#echo "'+proj=stere +lat_0=-90 +lon_0=0 +R=1737400 +units=m'" > polar_stereographic.prj
#echo "'+proj=longlat +a=1737400 +b=1737400'" > long_lat.prj
p_s="'+proj=stere +lat_0=-90 +lon_0=0 +R=1737400 +units=m'"
l_l="'+proj=longlat +a=1737400 +b=1737400'"
#POLYGON="82000 120000, 94000 120000, 94000 112000, 82000 112000, 82000 120000"
#POLYGON="-118348 -55716, -113057 -55716, -113057 -61007, -118348 -61007, -118348 -55716"
POLYGON="84900 120000, 94000 120000, 94000 113400, 84900 113400, 84900 120000"


POLYGON=${POLYGON//, /,}
POLYGON=${POLYGON// /_}

for p in ${POLYGON//,/ }; do
	p=${p//_/ }

	#echo "gdaltransform -s_srs polar_stereographic.prj  -t_srs long_lat.prj ${p}"
	#gdaltransform -s_srs polar_stereographic.prj  -t_srs long_lat.prj ${p}
	
	echo "echo ${p} | ${ASP}/bin/gdaltransform -s_srs ${p_s} -t_srs ${l_l} | ../python_for_moses/180to360.py" >> transform_cmd.sh
done

longlat=`. transform_cmd.sh`
echo $longlat
longlat=${longlat// 0/,}
echo $longlat
longlat=${longlat::-1}
longlat=`echo ${longlat} | tr '\r\n' ' '`
echo $longlat

echo "POLYGON((${longlat}))" >> poly.wkt
