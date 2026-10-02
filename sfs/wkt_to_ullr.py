from shapely import from_wkt
import fire

def ullr_from_geom(geom):
    bounds = geom.bounds
    # return ulx, uly, lrx, lry
    return bounds[0], bounds[3], bounds[2], bounds[1]

def run(wkt: str, as_str=True)-> str:
    geom = from_wkt(wkt)
    # get the extent 
    bounds = ullr_from_geom(geom)
    # return ulx, uly, lrx, lry
    if as_str:
        return f'{bounds[0]} {bounds[1]} {bounds[2]} {bounds[3]}'
    else:
        return bounds[0], bounds[1], bounds[2], bounds[3]
        
def main():
    fire.Fire(run)

if __name__ == '__main__':
    main()