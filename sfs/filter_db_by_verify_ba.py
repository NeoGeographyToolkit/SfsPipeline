import json 
import fire
import geopandas as gp
from pathlib import Path


def run(db_path: str, verify_out_json: str, out_db_path: str = None, component_index: int = 0):
    """
    Downselect an input db by PIDs present in the verify bundle adjust output

    writes a new db file (presumably gpkg) that only has product ids present 
    from the verify bundle adjust component selected
    """
    # load the df
    df = gp.read_file(db_path)
    # load the components
    with open(verify_out_json) as src:
        components = json.load(verify_out_json)
    # now make a table with the IDs in the largest component
    component_pids = components['components'][component_index].apply(lambda x: x.replace('.ech.cub', ''))
    # now update the df to only include those 
    df = df[df['PRODUCT_ID'].isin(component_pids)]
    # determine output name
    if not out_db_path:
        db_path = Path(db_path)
        current_name = db_path.name
        out_db_path = db_path.with_stem(f'vba_{current_name}')
    # write the output
    df.to_file(out_db_path)

# main
def main():
    fire.Fire(run)

if __name__ == '__main__':
    main()