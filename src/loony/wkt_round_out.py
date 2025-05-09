import math
from shapely import from_wkt
import fire


def round_out_bounds(minx, miny, maxx, maxy):
    # round down for min, up for max
    minx = math.floor(minx) - 0.5
    miny = math.floor(miny) - 0.5
    maxx = math.ceil(maxx) + 0.5
    maxy = math.ceil(maxy) + 0.5
    return minx, miny, maxx, maxy


def run(wkt: str, as_str=True)-> str:
    geom = from_wkt(wkt)
    # get the extent 
    minx, miny, maxx, maxy = geom.bounds
    minx, miny, maxx, maxy = round_out_bounds(minx, miny, maxx, maxy)
    # return minx, miny, maxx, maxy
    if as_str:
        return f'{minx} {miny} {maxx} {maxy}'
    else:
        return minx, miny, maxx, maxy
        

def main():
    fire.Fire(run)

if __name__ == '__main__':
    main()