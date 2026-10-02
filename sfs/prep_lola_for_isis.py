import fire
import sh
from pathlib import Path



def run(lbl_path):
    """
    Follow LROC instructions to prepare a LROC DEM for 
    use in ISIS for use in spiceinit and other stuff
    
    source material
    http://www.lroc.asu.edu/data/support/downloads/LROC_NAC_Processing_Guide.pdf 

    get data from 
    https://imbrium.mit.edu/DATA/LOLA_GDR/POLAR/FLOAT_IMG/

    :param dem_path: path to DEM tif file from PDS or otherwise
    """
    as_cub = Path(lbl_path).with_suffix('.cub')
    # convert to cub
    sh.pds2isis(f"from={lbl_path} to={as_cub}")
    # multiply from km to m
    as_meters = Path(lbl_path).with_suffix('.meters.cub')
    sh.fx(f'f1={as_cub} equation="f1*1000" to={as_meters}')
    # run demprep
    as_demprep = Path(lbl_path).with_suffix('.demprep.cub')
    sh.demprep(f"from={as_meters} to={as_demprep}")



def main():
    fire.Fire(run)

if __name__ == '__main__':
    main()


