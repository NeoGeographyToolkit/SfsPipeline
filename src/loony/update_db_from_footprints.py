import json 
import fire
import geopandas as gp
from pathlib import Path
import duckdb


def run(
    db_path: str,
    db_out_path: str,
    footprint_geojson_collection: str
    ):
    """
    Given a geodatabase (presumably gpkg file)
    and either a singular geojson or multiple geojson files
    update the geometries in the geodatabase to those from the geojson file(s)
    based on the location parameter in the geojson and product id in the geodatabase
    
    write the updated geodatabase to a new file
    """
    con = duckdb.connect(config = {'threads': 4})
    con.sql('SET enable_progress_bar = true;')
    con.sql('SET memory_limit = "4GB";')
    con.install_extension("spatial")
    con.load_extension("spatial")
    # load the geojson
    con.sql(f"""
    CREATE TEMP TABLE 
            ov 
    AS SELECT 
            split_part(parse_filename(O.location, true),'.',1) as PRODUCT_ID, 
            geom 
    FROM 
            ST_READ("{footprint_geojson_collection}") O; 
    """)
    # perform the join
    con.sql(
    f"""
    CREATE TEMP TABLE 
        df 
    AS SELECT 
        * 
    FROM 
        ST_READ("{db_path}"); 
    CREATE TEMP TABLE 
        merged 
    AS SELECT 
        * EXCLUDE (geom), 
        ov.geom 
    FROM 
        df 
    JOIN 
        ov 
    ON df.PRODUCT_ID == ov.PRODUCT_ID; 
    COPY 
        merged 
    TO 
        "{db_out_path}" 
    WITH (FORMAT GDAL, DRIVER 'GPKG', SRS 'IAU:30135');
    """
    )


# main
def main():
    fire.Fire(run)

if __name__ == '__main__':
    main()