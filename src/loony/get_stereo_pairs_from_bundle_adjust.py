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

def main(
        ba_prefix, 
        verify_out_json: str, 
        component_index: int = 0, 
        min_match_count = 1000, 
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
    adjusted=list(Path('./baD/baD-').parent.glob('*adjusted_state.json'))
    adjusted_df = pd.DataFrame({'image': [str(_).replace(ba_prefix+'-', '').split('.')[0] for _ in adjusted]})
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
    vm = matches.filter('p25 > 0').filter(f'p25 <= {max_mapproj_error}').set_alias('vm')
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
    vs = convergences.filter(f'num_matches > {min_match_count}').filter(f'p25 > {min_convergence_angle}').filter(f'p25 < {max_convergence_angle}').set_alias('vs')
    # get the matches from `vs` where:
    # 1) both left and right are in `good_cam_images_df`
    # 2) both left and right are in `vr`
    # 3) optionally also both in `vm`
    val_pairs = duckdb.sql("""
        SELECT DISTINCT
            LEAST(pt.left, pt.right) AS left,
            GREATEST(pt.left, pt.right) AS right,
            vr1.median as l_median,
            vr2.median as r_median,
            vm.p25 as match_p25,
            vm.p95 as match_p95,
            pt.p25 as angle_25,
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
    if just_info:
        print(val_pairs)
        if plot and db:
            import matplotlib.pyplot as plt
            from loony.new_sfs_cover import plot_footprints, plot_illumination_coverage
            import geopandas as gp
            gdf = gp.read_file(db)
            # todo plot the anticipate stereo coverage by intersecting the footprints of the pairs and 

        return 0
    # determine if to use map proj tifs that were bundle adjusted or not
    if use_ba_mapproj_tifs:
        map_ba_suffix = ba_prefix.split('/')[0]
        if len(map_ba_suffix) != 3:
            print(f'error in ba suffix: {map_ba_suffix} expected format, not 3 chars')
            return 1
    else:
        map_ba_suffix = 'noba'
    # get the data into pandas
    df = duckdb.sql(f"SELECT replace(val_pairs.left, '.cub', '.map.{map_ba_suffix}.tif') as left, replace(val_pairs.right, '.cub', '.map.{map_ba_suffix}.tif') as right FROM val_pairs;").fetchdf()
    # Print DataFrame to CSV to stdout
    df.to_csv(sys.stdout, index=False, header=False, sep=' ')  


if __name__ == "__main__":
    fire.Fire(main)
