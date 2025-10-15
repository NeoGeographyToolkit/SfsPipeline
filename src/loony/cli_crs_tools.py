from pathlib import Path
import rasterio as rio
from shapely import from_wkt, centroid
import fire
from pyproj import Transformer
from .proj_utils import make_stereographic_moon_projection, moon_crs_ge, moon_crs_np, moon_crs_sp

class CRS_CLI(object):

    @staticmethod
    def lon_lat_to_wkt_stereographic(lon: float, lat: float, name: str | None = None)-> str:
        """
        get the wkt2 representation of the new stereographic projection with the provided longitude and latitude center
        """
        crs = make_stereographic_moon_projection(lon, lat, name=name)
        return crs.to_wkt()

    @staticmethod
    def raster_to_wkt_stereographic(path_to_raster: str | Path, name: str | None = None)-> str:
        """
        get a new stereographic projection for a provided raster

        allow a custom name to be provided 
        """
        with rio.open(path_to_raster, 'r') as src:
            # get the center long lat
            lon, lat = src.lnglat()
        # convert to wkt
        wkt = CRS_CLI.lon_lat_to_wkt_stereographic(lon, lat, name=name)
        # and return to user
        return wkt

    @staticmethod
    def geom_to_wkt_stereographic(wkt_geom: str, geom_crs: str = 'IAU_2015:30100', name: str | None = None)-> str:
        """
        given a WKT geometry, get the new stereographic projection using the geometry's centroid for the projection
        """
        # get the shapely geometry
        geom = from_wkt(wkt_geom)
        # get the center in native coordinates
        center = centroid(geom)
        cen_x, cen_y = center.x, center.y
        # determine transform to create
        transform = Transformer.from_crs(geom_crs, moon_crs_ge, always_xy=True)
        # convert to geographic longitude and latitude
        lon, lat = transform.transform(cen_x, cen_y)
        # convert to wkt
        wkt = CRS_CLI.lon_lat_to_wkt_stereographic(lon, lat, name=name)
        # and return to user
        return wkt






def main():
    fire.Fire(CRS_CLI)

if __name__ == '__main__':
    main()