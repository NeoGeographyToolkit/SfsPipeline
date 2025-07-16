import json 
import fire
import geopandas as gp
import rasterio as rio
from pathlib import Path
import numpy as np
import duckdb
import networkx as nx
import networkx.algorithms.connectivity as nxcon

from loony.utils import get_embedded_provenance
from loony.graph_utils import check_connectivity





class InsepctBA(object):

    def __load_residuals(self, ba_prefix):
        self.residuals = duckdb.sql(f"""
            SELECT 
                * 
            FROM read_csv(
                '{ba_prefix}-final_residuals_stats.txt', 
                skip=2,
                header=False,
                names=['image', 'mean', 'median', 'count'])
            WHERE
                count > 0;
            """
        )   

    def __load_pair_matches(self, ba_prefix):
        self.pair_matches = duckdb.sql(f"""
            SELECT 
                 * 
            FROM read_csv(
                 '{ba_prefix}-mapproj_match_offset_pair_stats.txt',
                 skip=2, 
                 sep=' ',
                 names=['left', 'right', 'p25', 'p50', 'p75', 'p85', 'p95', 'num']
            );"""
        )

    def __load_match_offsets(self, ba_prefix):
        # parse in the match offsets file
        self.match_offsets = duckdb.sql(f"""
            SELECT 
                 * 
            FROM read_csv(
                 '{ba_prefix}-mapproj_match_offset_stats.txt',
                 skip=1, 
                 sep=' ',
                 names=['image', 'p25', 'p50', 'p75', 'p85', 'p95', 'count']
            );"""
        )             

    def __init__(self, ba_prefix: str, min_match_count = 400, max_residual_error: float = 1.25):
        # load residuals, match pairs, and map project offsets
        self.__load_residuals(ba_prefix)
        self.__load_pair_matches(ba_prefix)
        self.__load_match_offsets(ba_prefix)
        # get just the images with valid residuals 
        vr = self.residuals.filter(f'median < {max_residual_error}').filter(f'count >= {min_match_count}').set_alias('vr')   
        # get just the pairs with num above min match count
        vm = self.pair_matches.filter(f'num >= {min_match_count}').set_alias('vm')
        # filter the match offsets to only include those images who's p85 is less than max_residual_error
        vo = self.match_offsets.filter(f'count >= {min_match_count}').filter(f'p85 <= {max_residual_error}').set_alias('vo')                                                                                                                                                                                                                                                                                                              
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
        # update val_pairs to only include pairs where both images are also in v0
        self.val_pairs = duckdb.sql(f"""
            SELECT
                               vp.*
            FROM
                               val_pairs as vp
            JOIN
                               vo as vo1 ON vp.LEFT = vo1.image
            JOIN
                               vo as vo2 ON vp.RIGHT = vo2.image;                       
        """).set_alias('val_pairs')
        # get the pair data into a df
        df = duckdb.sql('SELECT * FROM val_pairs;').fetchdf()    
        # make the graph
        self.G = nx.Graph()
        left=df['left'].str.split('/').str[-1].str.split('.').str[0]
        right=df['right'].str.split('/').str[-1].str.split('.').str[0]
        lr=np.vstack((left,right)).T
        self.G.add_edges_from(lr)
        components = list(nx.connected_components(self.G))
        components = sorted(components, key=len, reverse=True)
        self.G = self.G.subgraph(components[0]).copy() 
        # final updates
        self.vr=vr
        self.vm=vm
        self.vo=vo

    def query(self, product_id):
        print('""""""""""""""""""""""""""""""""""')
        print(f'In Graph: {product_id in self.G}')
        print(f'Degree: {self.G.degree(product_id)}')
        print(f'Residuals:')
        print(self.get_residuals(product_id))
        print(f'Match Offsets L:')
        print(self.get_match_offsets(product_id))
        print('""""""""""""""""""""""""""""""""""')
    
    def get_residuals(self, product_id):
        return self.vr.filter(f'"image" LIKE \'%{product_id}%\'')

    def get_pair_matches(self, product_id):
        return self.vm.filter(f'"left" LIKE \'%{product_id}%\'').order('p95')

    def get_pair_matches_left(self, product_id):
        return self.vm.filter(f'"left" LIKE \'%{product_id}%\'').order('p95')
    
    def get_pair_matches_right(self, product_id):
        return self.vm.filter(f'"right" LIKE \'%{product_id}%\'').order('p95')
    
    def get_val_pairs(self, product_id):
        return self.val_pairs.filter(f'"left" LIKE \'%{product_id}%\'').order('p95')

    def get_val_pairs_left(self, product_id):
        return self.val_pairs.filter(f'"left" LIKE \'%{product_id}%\'').order('p95')
    
    def get_val_pairs_right(self, product_id):
        return self.val_pairs.filter(f'"right" LIKE \'%{product_id}%\'').order('p95')

    def get_match_offsets(self, product_id):
        return self.vo.filter(f'"image" LIKE \'%{product_id}%\'')
        
    def neighbors(self, product_id):
        return list(self.G.neighbors(product_id))

    def min_cut(self, product_id_1, product_id_2):
        return nxcon.minimum_st_node_cut(self.G, product_id_1, product_id_2)

    def min_path(self, product_id_1, product_id_2):
        return list(nx.shortest_path(self.G, product_id_1, product_id_2))

    def min_path_length(self, product_id_1, product_id_2):
        return nx.shortest_path_length(self.G, product_id_1, product_id_2)

    def degree(self, *product_id):
        for pid in product_id:
            print(self.G.degree(pid))



# main
def main():
    fire.Fire(InsepctBA)

if __name__ == '__main__':
    main()