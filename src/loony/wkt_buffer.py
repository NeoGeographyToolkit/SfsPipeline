from shapely import from_wkt
import fire


def run(wkt: str, buffer_size:int, as_str=True)-> str:
    geom = from_wkt(wkt)
    # get the extent 
    buffer = geom.buffer(buffer_size, join_style='mitre', cap_style='square')
    # return ulx, uly, lrx, lry
    if as_str:
        return buffer.wkt
    else:
        return buffer
        
def main():
    fire.Fire(run)

if __name__ == '__main__':
    main()