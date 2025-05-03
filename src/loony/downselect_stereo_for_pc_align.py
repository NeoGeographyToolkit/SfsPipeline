import pandas as pd
import fire
import re

pattern_pair = r'(M\d+(?:RE|LE)__M\d+(?:RE|LE))'
pattern_full = r'\./[^/]+_M\d+(?:RE|LE)__M\d+(?:RE|LE)'

def main(
        dem_diffs_jsonld, 
        inter_error_jsonld, 
        max_mean_error: float = 1.0,
        max_abs_dem_diff: float = 10.0,
        diff_prefix: str = 'run-diff',
        with_postfix: str = 'run-DEM',
        verbose: bool = False
        ):
    """
    Given the  geodiff-stat json files for a list of dems and stats for intersectionerror tif files
    Get the list of DEMs that have low mean diffs and also low max triangulation error 

    """
    # read in the dem diffs
    d_df = pd.read_json(dem_diffs_jsonld, orient='records', lines=True)
    if verbose:
        print('d_df len: ', len(d_df))
    # filter the dems
    d_df = d_df.loc[d_df['STATISTICS_MEAN'].abs() <= max_abs_dem_diff]
    if verbose:
        print('d_df len after filtering: ', len(d_df))
    # read in the intersection errors
    i_df = pd.read_json(inter_error_jsonld, orient='records', lines=True)
    if verbose:
        print('i_df len: ', len(i_df))
    # filter the intersections
    i_df = i_df.loc[i_df['STATISTICS_MEAN'] <= max_mean_error]
    if verbose:
        print('i_df len after filtering: ', len(i_df))
    # get the set intersection, this is also kinda terrible
    i_df_files = set([re.search(pattern_pair, fname).group(0) for fname in i_df['file'] if re.search(pattern_pair, fname)])
    d_df_files = set([re.search(pattern_pair, fname).group(0) for fname in d_df['file'] if re.search(pattern_pair, fname)])
    if verbose:
        print('len i_df: ', len(i_df_files))
        print('len d_df: ', len(d_df_files))
    good_files = d_df_files.intersection(i_df_files)
    if verbose:
        print('good files len: ', len(good_files))
    # oh wow this is terrible but it does work
    good_dems = sorted([dem for dem in d_df['file'] if any([_ in dem for _ in good_files])])
    if verbose:
        print('good dems len: ', len(good_dems))
    # now down select the dem df again
    d_df = d_df.loc[d_df['file'].isin(good_dems)]
    # now report just the file names
    for _ in d_df['file']:
        print(_.replace(diff_prefix, with_postfix), flush=True)



if __name__ == "__main__":
    fire.Fire(main)