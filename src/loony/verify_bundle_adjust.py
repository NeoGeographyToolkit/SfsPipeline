#!/usr/bin/env python3

# https://stereopipeline.readthedocs.io/en/latest/sfs_usage.html#validation-of-bundle-adjustment

# we need a few checks
# 1) after removing the Nan images and the images with over 1-2 meter median reprojection error in ba/run-final_residuals_stats.txt
#    do we still have a hamiltonian path through all the image pairs such that each image is visited at least once.
#    use the match_offset_pair_stats.txt file to get the pairs that had successful matches (overlap list not sufficient)
# 2)
import json
import duckdb
import fire
import networkx as nx
import numpy as np

from loony.graph_utils import check_connectivity


def run(ba_prefix: str, min_match_count = 1, max_residual_error: float = 1.25, use_match_offsets: bool = False, plot: bool = False, db: str | None = None, verbose: bool = False):
    # parse in the match pairs file #TODO use https://duckdb.org/docs/stable/sql/query_syntax/prepared_statements.html
    pair_matches = duckdb.sql(f"""
        SELECT 
             * 
        FROM read_csv(
             '{ba_prefix}-mapproj_match_offset_pair_stats.txt',
             skip=2, 
             sep=' ',
             names=['left', 'right', 'p25', 'p50', 'p75', 'p85', 'p95', 'num']
        );"""
    )
    if verbose:
        print(f'Len {ba_prefix}-mapproj_match_offset_pair_stats.txt: {len(pair_matches)}')
    # get just the pairs with num above 0 for the moment
    vm = pair_matches.filter(f'num >= {min_match_count}').set_alias('vm')
    if verbose:
        print(f'Len {ba_prefix}-mapproj_match_offset_pair_stats.txt after filtering: {len(vm)}')
    # parse in both the residuals 
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
    if verbose:
        print(f'Len {ba_prefix}-final_residuals_stats.txt: {len(residuals)}')                                                                                                                                                                                                                                                                                                                                                                          
    # get just the images with residuals 
    vr = residuals.filter(f'median < {max_residual_error}').filter(f'count >= {min_match_count}').set_alias('vr')
    if verbose:
        print(f'Len {ba_prefix}-final_residuals_stats.txt after filtering: {len(vr)}')         
    # get the matches where both the left and right images are also in the good residuals list
    val_pairs = duckdb.sql("""
        SELECT 
                           pt.* 
        FROM 
                           vm as pt 
        JOIN 
                           vr as vr1 ON pt.left = vr1.image 
        JOIN 
                           vr as vr2 ON pt.right = vr2.image;
    """).set_alias('val_pairs')
    if verbose:
        print(f'Len val_pairs: {len(val_pairs)}') 
    # parse in the match offsets file if requested
    if use_match_offsets:
        match_offsets = duckdb.sql(f"""
            SELECT 
                 * 
            FROM read_csv(
                 '{ba_prefix}-mapproj_match_offset_stats.txt',
                 skip=1, 
                 sep=' ',
                 names=['image', 'p25', 'p50', 'p75', 'p85', 'p95', 'count']
            );"""
        )
        if verbose:
            print(f'Len {ba_prefix}-mapproj_match_offset_stats.txt: {len(match_offsets)}') 
        # filter the match offsets to only include those images who's p85 is less than max_residual_error
        vo = match_offsets.filter(f'count >= {min_match_count}').filter(f'p85 <= {max_residual_error}').set_alias('vo')
        if verbose:
            print(f'Len {ba_prefix}-mapproj_match_offset_stats.txt after filtering: count >= {min_match_count} & p85 <= {max_residual_error}: {len(vo)}') 
        # update val_pairs to only include pairs where both images are also in v0
        val_pairs = duckdb.sql(f"""
            SELECT
                               vp.*
            FROM
                               val_pairs as vp
            JOIN
                               vo as vo1 ON vp.LEFT = vo1.image
            JOIN
                               vo as vo2 ON vp.RIGHT = vo2.image;                       
        """).set_alias('val_pairs')
        if verbose:
            print(f'Updated len val_pairs: {len(val_pairs)}') 
    # get the data into numpy
    df = duckdb.sql('SELECT * FROM val_pairs;').fetchnumpy()    
    if verbose:
        print(f'Final # Pairs: {len(df['left'])}')
    # compute the graph and determine the checks
    res = check_connectivity(np.vstack((df['left'],df['right'])).T)
    # add query params
    res['db'] = db
    res['min_match_count'] = min_match_count
    res['max_residual_error'] = max_residual_error
    if plot and db:
        import matplotlib.pyplot as plt
        from loony.new_sfs_cover import plot_footprints, plot_illumination_coverage
        import geopandas as gp
        from pathlib import Path
        gdf = gp.read_file(db)
        bap = ba_prefix.split("/")[0]
        # plot each component
        for i, c in enumerate(res['components']):
            # get product_ids from component
            product_ids = [Path(_).name.split('.')[0] for _ in c]
            indexes = [_ in product_ids for _ in gdf['PRODUCT_ID']]
            # plot the footprints
            plot_footprints(gdf.iloc[indexes], None, title=f'Component {i} for {bap} MRE {max_residual_error:0.2f}', to_crs=gdf.crs)
            plt.tight_layout()
            plt.savefig(f'{bap}_map_{i}.png', dpi=600)
            #plt.show()
            # plot the illumination
            plot_illumination_coverage(gdf.iloc[indexes], None, title=f'Component {i} for {bap} MRE {max_residual_error:0.2f}')
            plt.savefig(f'{bap}_illum_{i}.png', dpi=150)
            #plt.show()
            plt.close('all') 

    # dump to stdout the json
    return json.dumps(res)


def main():
    fire.Fire(run)

if __name__ == '__main__':
    main()