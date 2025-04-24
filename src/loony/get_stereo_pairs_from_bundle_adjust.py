#!/usr/bin/env python3


# supposed to run after verify bundle adjust
# given the results from verify bundle adjust, the largest component,
# determine the stereo pairs belonging to that collection from the convergence angles file
# remove any pairs for which either image in the pair has high residuals 
# and verify adjusted cameras are available for each image so that stereo can be run 
# with some confidence it will run
# output each remaining pair to stdout for use in pair list files for PBS scripts and such


# essentially improve and make the following SQL work:
#duckdb -csv -c "INSTALL json; LOAD json; WITH comp AS (SELECT UNNEST(components[1]) as product_ids FROM read_json_auto('./test_delta/bundle_adjust_components.json')), 
# final_resid AS (SELECT \"# Image\" as product_ids FROM read_csv('./baD/baD-final_residuals_stats.txt', skip=1, header=True) WHERE median < 1.5 AND isfinite(median)) 
# SELECT replace(column0,'.cub', '.map.noba.tif'), replace(column1, '.cub', '.map.noba.tif') FROM read_csv('./baD/baD-convergence_angles.txt', skip=2, header=False, sep=' ') 
# JOIN final_resid AS fr0 ON fr0.product_ids = column0 
# JOIN final_resid AS fr1 ON fr1.product_ids = column1 
# JOIN comp AS c0 ON c0.product_ids = column0 
# JOIN comp AS c1 ON c1.product_ids = column1  
# WHERE 
# column2 > 10 AND 
# column5 > 1000 
# ORDER BY column5 DESC;" | sed 's/,/ /g' | tail -n +2 > ./test_delta/CAMERA_PAIR_LIST.txt
import sys
import json
from pathlib import Path
import duckdb
import fire
import pandas as pd

def run(
        ba_prefix, 
        verify_out_json: str, 
        component_index: int = 0, 
        min_match_count = 100, 
        max_residual_error: float = 1.25, 
        max_mapproj_error: float = 2.5,
        min_convergence_angle: float = 10.0,
        max_convergence_angle: float = 22.0,
        use_ba_mapproj_tifs: bool = False,
        just_info: bool = False,
        plot: bool = False,
        db: str | None = None
    ):
    # load the component json file
    with open(verify_out_json) as verify_out:
        components = json.load(verify_out)
    # now make a table with the IDs in the largest component
    component_images = components['components'][component_index] # todo replace .ech.cub?
    connected_images_df = pd.DataFrame({'image': component_images})
    # load the adjusted camera models (replacing the adjusted_state.json with .cub)
    adjusted=list(Path(f'./{ba_prefix}-').parent.glob('*adjusted_state.json'))
    adjusted_df = pd.DataFrame({'image': [str(_).replace(ba_prefix+'-', '').split('.')[0] for _ in adjusted]})
    # load the spatial library just in case
    duckdb.sql('LOAD SPATIAL;')
    # filter the connected_images_df for those with adjusted cameras (should be all)
    good_cam_images_df = duckdb.sql('SELECT t1.image FROM connected_images_df t1 JOIN adjusted_df t2 ON strpos(t1.image, t2.image) > 0;').fetchdf()
    # parse in the match pairs file #TODO use https://duckdb.org/docs/stable/sql/query_syntax/prepared_statements.html
    # TODO use this?
    matches = duckdb.sql(f"""
        SELECT 
             * 
        FROM read_csv(
             '{ba_prefix}-mapproj_match_offset_pair_stats.txt',
             skip=2, 
             sep=' ',
             names=['left', 'right', 'p25', 'p50', 'p75', 'p85', 'p95', 'num']
        );"""
    )
    # get just the pairs with p25 above 0 for the moment 
    # .filter(f'p25 <= {max_mapproj_error}') avoid using the mapproj error at all for now, just so long as it's not 0
    vm = matches.filter('p25 > 0').set_alias('vm')
    # load in the residuals 
    residuals = duckdb.sql(f"""
        SELECT 
            * 
        FROM read_csv(
            '{ba_prefix}-final_residuals_stats.txt', 
            skip=2,
            header=False,
            names=['image', 'mean', 'median', 'count']
        );"""
    )
    # get just the images with residuals 
    vr = residuals.filter('isfinite(median)').filter(f'median < {max_residual_error}').filter(f'count > {min_match_count}').set_alias('vr')     
    # load in the convergence angles file
    convergences = duckdb.sql(f"""
        SELECT 
            *
        FROM 
            read_csv(
                '{ba_prefix}-convergence_angles.txt',
                skip=2, 
                header=False, 
                sep=' ',
                names=['left', 'right', 'p25', 'p50', 'p75', 'num_matches']
            ) 
    """)
    # get just the valid stereo pairs
    # TODO log here and elsewhere the counts before and after filtering to make it clear when things are being filtered out
    vs = convergences.filter(f'num_matches > {min_match_count}').filter(f'p75 >= {min_convergence_angle}').filter(f'p25 < {max_convergence_angle}').set_alias('vs')
    # get the matches from `vs` where:
    # 1) both left and right are in `good_cam_images_df`
    # 2) both left and right are in `vr`
    # 3) optionally also both in `vm`
    val_pairs = duckdb.sql("""
        SELECT DISTINCT
            LEAST(pt.left, pt.right) AS left,
            GREATEST(pt.left, pt.right) AS right,
            split_part(parse_filename(pt.left, true),'.',1) as LPID,
            split_part(parse_filename(pt.right, true),'.',1) as RPID,
            vr1.median as l_median,
            vr2.median as r_median,
            vm.p25 as match_p25,
            vm.p95 as match_p95,
            pt.p25 as angle_25,
            pt.p50 as angle_50,
            pt.p75 as angle_75,
            pt.num_matches as num_matches
        FROM 
            vs as pt
        JOIN
            good_cam_images_df as ci1 ON pt.left = ci1.image
        JOIN
            good_cam_images_df as ci2 ON pt.right = ci2.image
        JOIN 
            vm ON pt.left = vm.left AND pt.right = vm.right           
        JOIN 
            vr as vr1 ON pt.left = vr1.image 
        JOIN 
            vr as vr2 ON pt.right = vr2.image
        ORDER BY
            l_median ASC                
        ;
    """).set_alias('val_pairs')
    # TODO Implement the same de-densification algorithm from lit_select, or something similar, to pick 
    # the minimum set of stereo products that cover the most spatial area based on their intersected geometry and 
    # have higher convergence angles over lower ones to remove lots of redundant/worse stereo products
    if db:
        from pyproj import CRS
        # load the database for geometry data
        crs_info = duckdb.sql(f"SELECT layers[1].geometry_fields[1].crs.auth_name as name, layers[1].geometry_fields[1].crs.auth_code as code FROM st_read_meta('{db}');").df().iloc[0].to_dict()
        if crs_info['name'] == 'IAU':
            crs_info['name'] = 'IAU_2015'
        crs = CRS.from_user_input(f'{crs_info["name"]}:{crs_info["code"]}')
        gdf = duckdb.sql(f'SELECT * FROM "{db}"')
        # first compute the geometries into a new table
        val_pairs_geom = duckdb.sql("""
            SELECT 
                * EXCLUDE (geom),
                ST_MakeValid(
                    ST_CollectionExtract(
                        ST_Intersection(ci1.geom, ci2.geom),
                        3
                    )               
                ) as geometry
            FROM
                val_pairs as vp
            JOIN
                gdf as ci1 on vp.LPID = ci1.PRODUCT_ID
            JOIN
                gdf as ci2 on vp.RPID = ci2.PRODUCT_ID;
        """)
    #     # 1. add a id column and compute the area column 
    #     with_id_and_area = duckdb.sql("""
    #         SELECT
    #           ROW_NUMBER() OVER ()  AS id,    -- <-- new id column
    #           *,
    #           ST_AREA(geometry)     AS stereo_area
    #         FROM val_pairs_geom;              -- or replace with your sub-query
    #     """)
    #     # 2. Find every intersecting pair (p1, p2) and compute intersection area
    #     intersecting_stereos = duckdb.sql("""
    #         SELECT
    #           p1.id   AS id1,
    #           p2.id   AS id2,
    #           p1.angle_75 AS converg1,
    #           p2.angle_75 AS converg2,
    #           p1.stereo_area AS stereo_area1,
    #           p2.stereo_area AS stereo_area2,
    #           ST_AREA(ST_INTERSECTION(p1.geometry, p2.geometry)) AS inter_stereo_area
    #         FROM with_id_and_area p1
    #         JOIN with_id_and_area p2
    #           ON ST_INTERSECTS(p1.geometry, p2.geometry)
    #          AND p1.id <> p2.id
    #     """)
    #     # 3. From those pairs, keep only “competitors” that are strictly better:
    #     #    (higher attr) OR (same attr AND larger area),
    #     #    AND that either fully cover p1 or overlap it by more than :threshold
    #     competitors = duckdb.sql("""
    #         SELECT DISTINCT
    #             id1
    #         FROM 
    #             intersecting_stereos
    #         WHERE
    #             -- strictly better: higher attr OR tie on attr but larger area
    #             (converg2 > converg1 OR (converg2 = converg1 AND stereo_area2 > stereo_area1))
    #         AND 
    #             (inter_stereo_area / stereo_area1) > 100
    #     """)
    #    # 4. Compute each polygon’s *unique* area = area minus union of all others
    #     unique_area = duckdb.sql("""
    #         SELECT
    #           p1.id,
    #           ST_AREA(
    #             ST_DIFFERENCE(
    #               p1.geom,
    #               -- union up only those that actually intersect p1
    #               COALESCE((
    #                 SELECT ST_UNION(p2.geom)
    #                 FROM intersecting_stereos p2
    #                 WHERE p2.id <> p1.id
    #                   AND ST_INTERSECTS(p1.geom, p2.geom)
    #               ), p1.geom)   -- if no intersects, union = p1 itself
    #             )
    #           ) AS uniq_area
    #         FROM intersecting_stereos p1;
    #     """)


    if just_info:
        print(val_pairs)
        if plot and db is not None:
            import matplotlib.pyplot as plt
            from loony.new_sfs_cover import plot_footprints, plot_illumination_coverage
            import geopandas as gp
            # todo plot the anticipate stereo coverage by intersecting the footprints of the pairs and 
            # now join
            stereo_gdf = duckdb.sql("""
                SELECT 
                    sp.* EXCLUDE(geometry),
                    ST_AsText(sp.geometry) as geometry_wkt,
                    ST_AREA(sp.geometry) as area
                FROM 
                    val_pairs_geom as sp
                ORDER BY
                    area;
            """).to_df()
            # now plot..
            stereo_gdf['geometry'] = gp.GeoSeries.from_wkt(stereo_gdf['geometry_wkt'], crs=crs)
            stereo_gdf = gp.GeoDataFrame(stereo_gdf)
            plot_footprints(stereo_gdf, None, title=f'Stereo Fooprints #{len(stereo_gdf)}', to_crs=crs)
            plt.tight_layout()
            plt.savefig(f'stereo_pair_map.png', dpi=600)
            plt.close('all')
            return 
    # determine if to use map proj tifs that were bundle adjusted or not
    if use_ba_mapproj_tifs:
        map_ba_suffix = ba_prefix.split('/')[0]
        if len(map_ba_suffix) != 3:
            print(f'error in ba suffix: {map_ba_suffix} expected format, not 3 chars')
            return 1
    else:
        map_ba_suffix = 'noba'
    if not just_info:
        # get the data into pandas
        df = duckdb.sql(f"SELECT replace(val_pairs.left, '.cub', '.map.{map_ba_suffix}.tif') as left, replace(val_pairs.right, '.cub', '.map.{map_ba_suffix}.tif') as right FROM val_pairs;").fetchdf()
        # Print DataFrame to CSV to stdout
        df.to_csv(sys.stdout, index=False, header=False, sep=' ')  


def main():
    fire.Fire(run)

if __name__ == '__main__':
    main()