import json 
import fire
import geopandas as gp
import pandas as pd
import rasterio as rio
from pathlib import Path

from loony.utils import filename_to_pid

def set_coverage(df, threshold: float = 100.0, verbose: bool = False):
    candidates = df.copy().reset_index(drop=True)
    selected_indices = []
    union_geom = None
    # Continue as long as there are candidate masks
    while not candidates.empty:
        # For each candidate, compute the area that is not already covered by union_geom
        def extra_area(geom):
            if union_geom is None:
                return geom.area
            else:
                # Compute the area that is not yet covered
                return geom.difference(union_geom).area
        # Compute extra area for each candidate
        candidates['extra_area'] = candidates.geometry.apply(extra_area)
        # Select the candidate with the maximum additional area
        best_idx = int(candidates['extra_area'].idxmax())
        best_extra = candidates.loc[best_idx, 'extra_area']
        # # If the best candidate adds less than the threshold, stop as it's diminishing returns
        if best_extra < threshold:
            break
        # Record the selected candidate (its index relative to the candidates dataframe)
        selected_indices.append(best_idx)
        # Update the union of selected areas
        best_geom = candidates.loc[best_idx, 'geometry']
        if union_geom is None:
            union_geom = best_geom
        else:
            union_geom = union_geom.union(best_geom)
        # Remove the selected candidate from the candidates dataframe
        candidates = candidates.drop(index=best_idx)
        if verbose:
            print(f"Iteration {len(selected_indices)}, Delta {best_extra}, Remaining {len(candidates)}")
    # we are done, return the selection
    return df.iloc[selected_indices].reset_index(drop=True)


def run(
        gdb_path,
        column: str = "ROI_SUB_SOLAR_GROUND_AZIMUTH", 
        min_v: float = 0.0, 
        max_v: float = 361.0, 
        ret_column: str = "PRODUCT_ID",
        threshold: float = 100.0, 
        verify_out_json: str = None,
        component_index: int = 0,
        dem_path: str | None = None,
        de_densify: bool = False,
        productid_non_grata_file: str | None = None,
        verbose: bool = False
    ):
    """
    Perform a vector based implementation of image_subset
    using the shadow masks and optionally filtered by
    SSGA and bundle adjust verification components

    returns a list of product_ids that can be used
    to build other lists outside of this script
    """
    # load the geodatabase file with geopandas
    df: gp.GeoDataFrame = gp.read_file(gdb_path)
    # if the dem is provided, subset the df to only include intersecting images
    if dem_path:
        with rio.open(dem_path, 'r') as src:
            bounds = src.bounds
        # use the bounds to filter the df for those that intersect
        df = df.cx[bounds.left:bounds.right, bounds.bottom:bounds.top]
    # if the connected components are provided, ensure the selections are compatible with it
    if verify_out_json:
        # load the components
        with open(verify_out_json) as src:
            components = json.load(src)
        # now make a table with the IDs in the largest component
        component_pids = components['components'][component_index]
        # now adjust the pids
        component_pids = [Path(_).name.replace('.ech.cub', '') for _ in component_pids]
        # now update the df to only include those 
        df = df[df['PRODUCT_ID'].isin(component_pids)]
    if productid_non_grata_file:
        # we will load the nongrata list to remove and productids we don't want to carry forward
        non_grata = pd.read_csv(productid_non_grata_file, header=None, sep=' ')[0] #get a series
        # get just the product ids without any extensions I may have included
        non_grata_pids = non_grata.apply(filename_to_pid).to_list()
        # TODO ensure left and right are excluded? nahh...
        # update df to exclude these pids
        df = df[~df['PRODUCT_ID'].isin(non_grata_pids)]
    # attempt to filter the input df by that provided column and min/max value range
    if column in df.columns:
        # only do it inclusive on left side to treat max_v as < max_v
        selection = df[column].between(min_v, max_v, inclusive='left')
        # downselect the df
        df = df[selection]
    else:
        raise RuntimeError(f'Column {column} not in possible columns: {df.columns} for file {gdb_path}')
    if de_densify:
        # now perform the down select
        df = set_coverage(df, threshold=threshold, verbose=verbose)
    # now represent the content to the user probably best done via csv, using the ret_column
    for out in df[ret_column].tolist():
        print(out, flush=True)

# main
def main():
    fire.Fire(run)

if __name__ == '__main__':
    main()