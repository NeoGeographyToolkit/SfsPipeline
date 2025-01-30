#!/usr/bin/env bash

# gather provenance info
prov=$(python ../src/loony/get_curret_provenance.py)
echo "Provenance: ${prov}"

# preprocess the index file into a flatgeobuf file we make in duckdb (which can't write geoparquet well yet)
echo "preprocessing the cumlative index to the flatgeobuf file in /tmp"
time python ../src/loony/process_lroc_cumulative_index.py

# convert the FlatGeoBuf file created from duckdb to parquet so we can remove it and save space
echo "creating the parquet files..."
time ogr2ogr -f parquet lroc_cumulative.parquet /tmp/lroc_cumulative_index_all.fgb -lco ROW_GROUP_SIZE=131072 -lco COMPRESSION=ZSTD -lco SORT_BY_BBOX=YES -mo "PRVOENANCE=${prov}"
time ogr2ogr -f parquet lroc_cumulative_north_polar.parquet lroc_cumulative_north_polar.xml -lco ROW_GROUP_SIZE=8192 -lco COMPRESSION=ZSTD -lco SORT_BY_BBOX=YES -mo "PRVOENANCE=${prov}"
time ogr2ogr -f parquet lroc_cumulative_south_polar.parquet lroc_cumulative_south_polar.xml -lco ROW_GROUP_SIZE=8192 -lco COMPRESSION=ZSTD -lco SORT_BY_BBOX=YES -mo "PRVOENANCE=${prov}"
