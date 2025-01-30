import sh
import fire


def run():
    # gather provenance info
    provenance = sh.Command('get-current-provenance')()
    # print out info
    sh.echo(f"Provenance: {provenance}")
    # preprocess the index file into a flatgeobuf file we make in duckdb (which can't write geoparquet well yet)
    sh.echo("preprocessing the cumlative index to the flatgeobuf file in /tmp")
    sh.time("preprocess-cumulative-index")
    # convert the FlatGeoBuf file created from duckdb to parquet so we can remove it and save space
    sh.echo("creating the parquet files...")
    sh.time("ogr2ogr", "-f", "parquet", "lroc_cumulative.parquet", "/tmp/lroc_cumulative_index_all.fgb", "-lco", "ROW_GROUP_SIZE=131072", "-lco", "COMPRESSION=ZSTD", "-lco", "SORT_BY_BBOX=YES", "-mo", f'"PRVOENANCE={provenance}"')
    sh.time("ogr2ogr", "-f", "parquet", "lroc_cumulative_north_polar.parquet", "lroc_cumulative_north_polar.xml", "-lco", "ROW_GROUP_SIZE=8192", "-lco", "COMPRESSION=ZSTD", "-lco", "SORT_BY_BBOX=YES", "-mo", f'"PRVOENANCE={provenance}"')
    sh.time("ogr2ogr", "-f", "parquet", "lroc_cumulative_south_polar.parquet", "lroc_cumulative_south_polar.xml", "-lco", "ROW_GROUP_SIZE=8192", "-lco", "COMPRESSION=ZSTD", "-lco", "SORT_BY_BBOX=YES", "-mo", f'"PRVOENANCE={provenance}"')

def main():
    fire.Fire(run)

if __name__ == "__main__":
    main()