import fire
import geopandas as gp





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
        verbose: bool = False
    ):
    """
    
    """
    # load the geodatabase file with geopandas
    df: gp.GeoDataFrame = gp.read_file(gdb_path)
    # attempt to filter the input df by that provided column and min/max value range
    if column in df.columns:
        # only do it inclusive on left side to treat max_v as < max_v
        selection = df[column].between(min_v, max_v, inclusive='left')
        # downselect the df
        df = df[selection]
    else:
        raise RuntimeError(f'Column {column} not in possible columns: {df.columns} for file {gdb_path}')
    # now perform the down select
    ds_df = set_coverage(df, threshold=threshold, verbose=verbose)
    # now represent the content to the user probably best done via csv
    

# main
def main():
    fire.Fire(run)

if __name__ == '__main__':
    main()