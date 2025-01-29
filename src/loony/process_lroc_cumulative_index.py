from pathlib import Path

import duckdb
import pvl
from pdr.parselabel.pds3 import parse_pvl
import polars as pl
from ground_azimuth import ground_azimuth_numpy as ground_azimuth

# first download CUMINDEX.LBL to your home dir
# next download CUMINDEX.TAB to your home dir 

## load label and parse manually with pvl
lbl = pvl.load(Path('~/CUMINDEX.LBL').expanduser())
index = lbl['INDEX_TABLE']
columns = [_ for _ in index if _[0] == 'COLUMN']
# get the names as that's really all we need, duckdb parses the data well enough for datatypes at the moment
# but we can always go back here and do more work with the label
names = [c[1]['NAME'] for c in columns]

print("Read metadata from cumulative label")
# Connect to DuckDB
con = duckdb.connect(config = {'threads': 4})
con.install_extension("spatial")
con.load_extension("spatial")

# Load the CSV without a header
con.execute("""
    CREATE TEMP TABLE 
        raw 
    AS SELECT 
        * 
    FROM 
        read_csv_auto('~/CUMINDEX.TAB', sep=',', header=false, quote='"')
    WHERE 
        column04
    ILIKE
        '%nac%'
""")

print('Loaded raw table', flush=True)

# Retrieve the schema and identify VARCHAR columns
schema = con.execute("""
    SELECT 
        column_name, 
        data_type 
    FROM 
        information_schema.columns 
    WHERE 
        table_name = 'raw'
""").fetchall()

print('Got schema', flush=True)

# Generate the SELECT query to trim all VARCHAR columns
columns = [
    f"TRIM({col[0]}) AS {name}" if col[1] == "VARCHAR" else f"{col[0]} AS {name}" for col, name in zip(schema, names) if 'wac' not in name.lower()
]
select_query = f"SELECT {', '.join(columns)} FROM raw WHERE TARGET_NAME ILIKE '%moon%'"

# Create a cleaned table with trimmed columns
con.execute(f"CREATE TEMP TABLE cleaned AS {select_query}")

print('Created cleaned table', flush=True)

# Convert 0-360 to -180 to 180 range for all longitudes
longitude_columns = ['LOWER_RIGHT_LONGITUDE', 'UPPER_RIGHT_LONGITUDE', 'UPPER_LEFT_LONGITUDE', 'LOWER_LEFT_LONGITUDE', 'CENTER_LONGITUDE', 'SUB_SPACECRAFT_LONGITUDE', 'SUB_SOLAR_LONGITUDE']

set_clauses = ", ".join(
    f"{col} = CASE WHEN {col} > 180 THEN {col} - 360 ELSE {col} END"
    for col in longitude_columns
)

# Complete UPDATE query
update_query = f"UPDATE cleaned SET {set_clauses};"

con.execute(update_query)

print('Updated Longitudes to correct range')

### compute SubSpacecraft Ground Azimuth and SupSolar Ground Azimuth
# Grab the columns we need from the current database
# TODO I don't like this SELECT here, but this is much less lines of code than making intermediate tables and inserting new columns and such
df = con.execute("""SELECT * FROM cleaned""").pl()
df_cleaned_with_ground_azimuths = df.with_columns(
    pl.Series(
        "SUB_SOLAR_GROUND_AZIMUTH", 
        ground_azimuth(
                df['CENTER_LATITUDE'].to_numpy(), 
                df['CENTER_LONGITUDE'].to_numpy(), 
                df['SUB_SOLAR_LATITUDE'].to_numpy(), 
                df['SUB_SOLAR_LONGITUDE'].to_numpy()
            )
        ),
    pl.Series(
        "SUB_SPACECRAFT_GROUND_AZIMUTH", 
        ground_azimuth(
                df['CENTER_LATITUDE'].to_numpy(), 
                df['CENTER_LONGITUDE'].to_numpy(), 
                df['SUB_SPACECRAFT_LATITUDE'].to_numpy(), 
                df['SUB_SPACECRAFT_LONGITUDE'].to_numpy()
            )
        )
)
print('computed ground azimuth columns and made new table')

# Add the WKT column, construct in CCW order from Lower Right so LR, UR, UL, LL, LR
# optionally use ST_AsHEXWKB to make saving to parquet easier until geoparquet driver included in duckdb
con.execute("""
    CREATE TEMP TABLE 
        lrocnac_all
    AS SELECT 
        PRODUCT_ID, VOLUME_ID, ORBIT_NUMBER, START_TIME, EMISSION_ANGLE, INCIDENCE_ANGLE, PHASE_ANGLE, CENTER_LONGITUDE, CENTER_LATITUDE, NORTH_AZIMUTH, SUB_SOLAR_AZIMUTH, SUB_SOLAR_LATITUDE, SUB_SOLAR_LONGITUDE, SUB_SPACECRAFT_LATITUDE, SUB_SPACECRAFT_LONGITUDE, SOLAR_DISTANCE, SOLAR_LONGITUDE, SUB_SOLAR_GROUND_AZIMUTH, SUB_SPACECRAFT_GROUND_AZIMUTH, SCALED_PIXEL_WIDTH, SCALED_PIXEL_HEIGHT, RESOLUTION, TARGET_CENTER_DISTANCE,
        ST_GeomFromText(
        'POLYGON((' || 
            LOWER_RIGHT_LONGITUDE || ' ' || LOWER_RIGHT_LATITUDE  || ', ' ||
            UPPER_RIGHT_LONGITUDE || ' ' || UPPER_RIGHT_LATITUDE  || ', ' ||
            UPPER_LEFT_LONGITUDE  || ' ' || UPPER_LEFT_LATITUDE   || ', ' ||
            LOWER_LEFT_LONGITUDE  || ' ' || LOWER_LEFT_LATITUDE   || ', ' ||
            LOWER_RIGHT_LONGITUDE || ' ' || LOWER_RIGHT_LATITUDE  || '))'
        ) AS GEOMETRY
    FROM df_cleaned_with_ground_azimuths
""")

print('created lroc spatial table, starting to apply hilbert order', flush=True)


con.execute("""
    CREATE TEMP TABLE
        lrocnac_all_ordered
    AS SELECT 
            * 
    FROM 
            lrocnac_all
    ORDER BY 
            ST_Hilbert(geometry, ST_Extent(ST_MakeEnvelope(-180, -90, 180, 90))) 
""")

print('saving hilbert ordered data to flatgeobuf', flush=True)

# write the table to a geoparquet 
# TODO look at other useful options in https://gdal.org/en/stable/drivers/vector/parquet.html
con.execute("""
    COPY lrocnac_all_ordered TO '/tmp/lroc_cumulative_index_all.fgb'         
    WITH (FORMAT GDAL, DRIVER 'FlatGeobuf', SRS 'IAU_2015:30100');
""")

#print('saving hilbert ordered data to parquet', flush=True)
# todo this is saving out WGS 84, and without a clear way to adjust SRS without using external call
# con.execute("""
#     COPY lrocnac_all_ordered TO '/tmp/lroc_cumulative_index_all.parquet' (FORMAT 'parquet', COMPRESSION 'zstd');
# """)

# Close the connection
con.close()

print('done!')