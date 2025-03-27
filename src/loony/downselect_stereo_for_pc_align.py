import pandas as pd
import fire
import re

pattern_pair = r'(M\d+(?:RE|LE)__M\d+(?:RE|LE))'
pattern_full = r'\./[^/]+_M\d+(?:RE|LE)__M\d+(?:RE|LE)'

def main(
        dem_diffs_jsonld, 
        inter_error_jsonld, 
        max_mean_error: float = 1.0,
        max_abs_dem_diff: float = 10.0
        ):
    """
    Given the  geodiff-stat json files for a list of dems and stats for intersectionerror tif files
    Get the list of DEMs that have low mean diffs and also low max triangulation error 

    """
    # read in the dem diffs
    d_df = pd.read_json(dem_diffs_jsonld, orient='records', lines=True)
    # filter the dems
    d_df = d_df.loc[d_df['STATISTICS_MEAN'].abs() <= max_abs_dem_diff]
    # read in the intersection errors
    i_df = pd.read_json(inter_error_jsonld, orient='records', lines=True)
    # filter the intersections
    i_df = i_df.loc[i_df['STATISTICS_MEAN'] <= max_mean_error]
    # get the set intersection, this is also kinda terrible
    i_df_files = set([re.search(pattern_full, fname).group(0) for fname in i_df['file'] if re.search(pattern_full, fname)])
    d_df_files = set([re.search(pattern_full, fname).group(0) for fname in d_df['file'] if re.search(pattern_full, fname)])
    good_files = d_df_files.intersection(i_df_files)
    # oh wow this is terrible but it does work
    good_dems = sorted([dem for dem in d_df['file'] if any([_ in dem for _ in good_files])])
    # now down select the dem df again
    d_df = d_df.loc[d_df['file'].isin(good_dems)]
    # now report just the file names
    for _ in d_df['file']:
        print(_, flush=True)



if __name__ == "__main__":
    fire.Fire(main)