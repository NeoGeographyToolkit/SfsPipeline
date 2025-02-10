from shapely import from_wkt
import fire

def run(wkt: str, as_str=True)-> str:
    geom = from_wkt(wkt)
    # get the extent 
    bounds = geom.bounds
    # return ulx, uly, lrx, lry
    if as_str:
        return f'{bounds[0]} {bounds[3]} {bounds[2]} {bounds[1]}'
    else:
        return bounds[0], bounds[3], bounds[2], bounds[1]
        
def main():
    fire.Fire(run)

if __name__ == '__main__':
    main()