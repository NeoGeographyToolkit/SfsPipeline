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


def check_connectivity(pairs):
    """
    construct the newtorkx graph and determine if there is connectivity or not
    """
    # make the graph
    G = nx.Graph()
    # add the edges
    G.add_edges_from(pairs)
    ## perform checks
    # get the weakly connected components
    components = list(nx.connected_components(G))
    components = sorted(components, key=len, reverse=True)
    # get the size of each
    components_sizes = list(map(len, components))
    # if you have more than one component, the bundle adjustment network
    # is incomplete (islands of data)
    # This is probably a bad thing, but it doesn't mean that within each 
    # island (component), the data isn't good, it just means that there is no
    # guarentee it is co-aligned to the other components
    # likely the best path forward is to take the largest of these and use that only
    # or to treat each connected component as a isolated part and independently do stereo
    # and pc_align for each
    #
    return {
        'is_connected': nx.is_connected(G),
        'num_components': len(components_sizes),
        'component_sizes': components_sizes,
        'components': [list(_) for _ in components]
    }



def main(ba_prefix: str, min_match_count = 1, max_residual_error: float = 1.25, plot: bool = False, db: str | None = None):
    # parse in the match pairs file #TODO use https://duckdb.org/docs/stable/sql/query_syntax/prepared_statements.html
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
    vm = matches.filter('p25 > 0').set_alias('vm')
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
    # get just the images with residuals 
    vr = residuals.filter(f'median < {max_residual_error}').filter(f'count > {min_match_count}').set_alias('vr')
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
    # get the data into numpy
    df = duckdb.sql('SELECT * FROM val_pairs;').fetchnumpy()
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
        # plot each component
        for i, c in enumerate(res['components']):
            # get product_ids from component
            product_ids = [Path(_).name.split('.')[0] for _ in c]
            indexes = [_ in product_ids for _ in gdf['PRODUCT_ID']]
            # plot the footprints
            plot_footprints(gdf.iloc[indexes], None, title=f'Component {i}', to_crs=gdf.crs)
            plt.savefig(f'map_{i}.png', dpi=150)
            #plt.show()
            # plot the illumination
            plot_illumination_coverage(gdf.iloc[indexes], None, title=f'Component {i}')
            plt.savefig(f'illum_{i}.png', dpi=150)
            #plt.show()
            plt.close('all') 

    # dump to stdout the json
    return json.dumps(res)


if __name__ == "__main__":
    fire.Fire(main)
