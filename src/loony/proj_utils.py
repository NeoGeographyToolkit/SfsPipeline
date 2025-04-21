from pyproj import CRS, Transformer
from pyproj.crs import ProjectedCRS
from pyproj.crs.coordinate_operation import StereographicConversion

# setup pyproj CRSs and transforms
moon_crs_ge = CRS.from_user_input('IAU_2015:30100')
moon_crs_np = CRS.from_user_input('IAU_2015:30130')
moon_crs_sp = CRS.from_user_input('IAU_2015:30135')

def make_stereographic_moon_projection(lon, lat, name: str = 'undefined'):
    """
    Make a new lunar stereographic projection for a given center longitude and latitude
    """
    conversion = StereographicConversion(lat, lon)
    proj_crs = ProjectedCRS(conversion, name=name, geodetic_crs=moon_crs_ge)
    return proj_crs