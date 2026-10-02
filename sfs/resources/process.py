import sh
import fire
import sys
import os

# Get the directory of the current file
current_dir = os.path.dirname(os.path.abspath(__file__))

def run():
    print('Gathering Provenance...')
    # gather provenance info
    provenance = sh.Command('provenance')().rstrip()
    # print out info
    print(f"Provenance: {provenance}")
    # preprocess the index file into a flatgeobuf file we make in duckdb (which can't write geoparquet well yet)
    print("preprocessing the cumlative index to the flatgeobuf file in /tmp")
    sh.time("prep-index", _out=sys.stdout, _err=sys.stderr)
    # convert the FlatGeoBuf file created from duckdb to parquet so we can remove it and save space
    print("creating the parquet files...")
    sh.time("ogr2ogr", "-progress", "-f", "parquet", "/tmp/lroc_cumulative.parquet", "/tmp/lroc_cumulative_index_all.fgb", "-lco", "ROW_GROUP_SIZE=131072", "-lco", "COMPRESSION=ZSTD", "-lco", "SORT_BY_BBOX=YES", "-mo", f'PROVENANCE={provenance}', _out=sys.stdout, _err=sys.stderr)
    print('created global parquet file at /tmp/lroc_cumulative.parquet')
    sh.time("ogr2ogr", "-f", "parquet", "/tmp/lroc_cumulative_north_polar.parquet", f"{current_dir}/lroc_cumulative_north_polar.xml", "-lco", "ROW_GROUP_SIZE=8192", "-lco", "COMPRESSION=ZSTD", "-lco", "SORT_BY_BBOX=YES", "-mo", f'PROVENANCE={provenance}', _out=sys.stdout, _err=sys.stderr)
    print('created north polar parquet file at /tmp/lroc_cumulative_north_polar.parquet')
    sh.time("ogr2ogr",  "-f", "parquet", "/tmp/lroc_cumulative_south_polar.parquet", f"{current_dir}/lroc_cumulative_south_polar.xml", "-lco", "ROW_GROUP_SIZE=8192", "-lco", "COMPRESSION=ZSTD", "-lco", "SORT_BY_BBOX=YES", "-mo", f'PROVENANCE={provenance}', _out=sys.stdout, _err=sys.stderr)
    print('created south polar parquet file at /tmp/lroc_cumulative_south_polar.parquet')
    print("Done! Parquet Files are located in /tmp/ for your use.")

def main():
    fire.Fire(run)

if __name__ == "__main__":
    main()