#!/usr/bin/env python


# https://duckdb.org/docs/api/python/function
import json
import os
import argparse
import numpy as np
import duckdb

from sfs.utils import get_embedded_provenance
from sfs.graph_utils import check_connectivity

def angular_separation_acos(deg1: float, deg2: float)-> float:
    # Convert degrees to radians
    a = np.radians(deg1)
    b = np.radians(deg2)
    # Compute separation using arccos of cosine of the difference
    separation_rad = np.arccos(np.cos(a - b))
    # Convert result back to degrees, if desired
    return np.degrees(separation_rad)

def arg_parser():
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog=""
    )
    parser.add_argument(
        "-d", "--db_path",
        help="Path to a geoparquet database file containing the database"
    )
    parser.add_argument(
        '-v', '--verbose',
        type=bool, default=False,
        help='set to enable print statements',
    )
    parser.add_argument(
        '--check_connectivity',
        action='store_true',
        help='If true use networkx to determine the graph connectivity of the results assume all pairs successfully produce matches (a high assumption)'
    )
    parser.add_argument(
        "--max_diff_slrgaz",
        type=float, default=2.0,
        help="maximum (inclusive) difference is solar ground azimuth for a stereo pair",
    )
    parser.add_argument(
        "--image_filename_postfix",
        type=str, default='.cal.echo.cub',
        help='file extension for image ids to append (default matches the '
             'pipeline .cal.echo.cub naming)'
    )
    parser.add_argument(
        "--image_dir",
        type=str, default='CWD',
        help='default file path to prepend to image ids, set to CWD to call os.cwd()'
    )
    return parser


def main():
    parser = arg_parser()
    args = parser.parse_args()
    # Connect to DuckDB
    with duckdb.connect(config = {'threads': 4}) as con:
        con.sql('SET enable_progress_bar = false;')
        con.sql('SET memory_limit = "4GB";')
        con.install_extension("spatial")
        con.load_extension("spatial")
        # register functions
        con.create_function("angular_separation_acos", angular_separation_acos)
        # fetch the crs of the source database
        crs_info = con.sql(f"SELECT layers[1].geometry_fields[1].crs.auth_name as name, layers[1].geometry_fields[1].crs.auth_code as code FROM st_read_meta('{args.db_path}');").df().iloc[0].to_dict()
        if crs_info['name'] == 'IAU':
            crs_info['name'] = 'IAU_2015'
        # load the database into duckdb
        con.sql(f"CREATE TEMP TABLE df AS SELECT * FROM ST_READ('{args.db_path}');")
        if args.verbose:
            print(f'Loaded DB: {args.db_path}')
        # grab all ids for later use
        original_ids = set(_[0] for _ in con.sql('SELECT PRODUCT_ID from df').fetchall())
        # create a spatial index R-tree
        con.sql("CREATE INDEX my_idx ON df USING RTREE (geom)")
        if args.verbose:
            print('Created Spatial Index')
        # compute all the pair-wise intersections for analysis
        if args.verbose:
            print("Performing spatial join (this will be slow for large source databases...)")
        # TODO add new mode which does not limit the solar az acos diff but grabs the lowest N per image
        con.sql(f"""
            CREATE TEMP TABLE 
                    pairs_raw
            AS SELECT
                    L.PRODUCT_ID      as L_PRODUCT_ID,
                    L.ROI_SUB_SOLAR_GROUND_AZIMUTH as L_ROI_SUB_SOLAR_GROUND_AZIMUTH,
                    R.PRODUCT_ID      as R_PRODUCT_ID,
                    R.ROI_SUB_SOLAR_GROUND_AZIMUTH as R_ROI_SUB_SOLAR_GROUND_AZIMUTH,
                    angular_separation_acos(L.ROI_SUB_SOLAR_GROUND_AZIMUTH::FLOAT, R.ROI_SUB_SOLAR_GROUND_AZIMUTH::FLOAT) as SOLAR_AZ_ACOS_DIFF,
            FROM 
                df L
            JOIN 
                df R 
            ON 
                ST_INTERSECTS(L.geom, R.geom)
            WHERE
                L_PRODUCT_ID < R_PRODUCT_ID  -- Ensures no duplicate pairs and excludes self-matches or repeats
            AND
                SOLAR_AZ_ACOS_DIFF < {args.max_diff_slrgaz}
            AND
                LEFT(L_PRODUCT_ID, LENGTH(L_PRODUCT_ID) - 2) != LEFT(R_PRODUCT_ID, LENGTH(R_PRODUCT_ID) - 2) -- Ensure left and right images for an observation aren't matched to themselves as the overlap is too small for ASP
            ORDER BY
                L_ROI_SUB_SOLAR_GROUND_AZIMUTH ASC,
                SOLAR_AZ_ACOS_DIFF ASC;
        """)
        # get left ids
        u_left_ids = set(_[0] for _ in con.sql('SELECT DISTINCT L_PRODUCT_ID from pairs_raw').fetchall())
        # get right ids
        u_right_ids = set(_[0] for _ in con.sql('SELECT DISTINCT R_PRODUCT_ID from pairs_raw').fetchall())
        # get union
        ids_used = u_left_ids.union(u_right_ids)
        # test if any original ids are missing
        missed_ids = original_ids - ids_used
        if len(missed_ids) > 0:
            if args.verbose:
                print(f'missed {len(missed_ids)} images in the intersections, if a lot considering raising max_diff_slrgaz', flush=True)
                print(missed_ids, flush=True)
                print('', flush=True)
        # get the prefix for the image id paths
        path_prefix = args.image_dir
        if path_prefix == 'CWD':
            path_prefix = os.getcwd()+'/IMAGES/'
        # if we check the connectivity we just want it's output not the actual list of pairs
        if args.check_connectivity:
            # grab the full list of product ids
            pairs = con.sql(f"""
                SELECT 
                    CONCAT('{path_prefix}', L_PRODUCT_ID, '{args.image_filename_postfix}') as L,
                    CONCAT('{path_prefix}', R_PRODUCT_ID, '{args.image_filename_postfix}') as R
                FROM 
                    pairs_raw;
            """).fetchnumpy()
            # compute the graph and determine the checks
            res = check_connectivity(np.vstack(( pairs['L'], pairs['R'] )).T)
            # todo add plotting from verify bundle adjust
            print(json.dumps(res), flush=True)
        else:
            # get the final output for stdout
            pair_output = con.sql(f"SELECT CONCAT('{path_prefix}', L_PRODUCT_ID, '{args.image_filename_postfix} ', '{path_prefix}', R_PRODUCT_ID, '{args.image_filename_postfix}') as lines FROM pairs_raw;").fetchnumpy()
            for row in pair_output['lines']:
                print(row, flush=True)


    # close the
    con.close()


if __name__ == '__main__':
    main()