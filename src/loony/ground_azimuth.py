import numpy as np


def ground_azimuth_scalar(glat: float, glon: float, slat: float, slon: float)-> float:
    """
    Computes the ground azimuth between a ground point and another point of interest 
    given scalar latitude/longitude values.

    Parameters:
        glat (float): Latitude of the ground point.
        glon (float): Longitude of the ground point.
        slat (float): Latitude of the subspacecraft or subsolar point.
        slon (float): Longitude of the subspacecraft or subsolar point.
        
    Returns:
        float: Azimuth in degrees.
    """
    # Convert latitudes to radians based on the hemisphere of the ground point.
    if glat < 0.0:
        a = np.deg2rad(90.0 + slat)
        b = np.deg2rad(90.0 + glat)
    else:
        a = np.deg2rad(90.0 - slat)
        b = np.deg2rad(90.0 - glat)
        
    # Normalize longitudes to avoid crossing the 180-degree meridian.
    cslon = slon
    cglon = glon
    diff = abs(cslon - cglon)
    if (cslon > cglon) and (diff > 180.0):
        cslon = cslon - 360.0
    if (cglon > cslon) and (diff > 180.0):
        cglon = cglon - 360.0
        
    # Compute the central angle.
    cos_a = np.cos(a)
    cos_b = np.cos(b)
    sin_a = np.sin(a)
    sin_b = np.sin(b)
    
    C = np.abs(np.deg2rad(cglon - cslon)) # this abs should be kept
    # clipping to -1.0 to 1.0 might not be smart here?
    c = np.arccos(np.clip(cos_a * cos_b + sin_a * sin_b * np.cos(C), -1.0, 1.0))
    
    # Compute the intermediate angle
    with np.errstate(divide='ignore', invalid='ignore'):
        intermediate = (cos_a - cos_b * np.cos(c)) / (sin_b * np.sin(c))
        intermediate = np.nan_to_num(intermediate, posinf=0.0, neginf=0.0)
    intermediate = np.clip(intermediate, -1.0, 1.0)  # Ensure it is within valid range
    A = np.rad2deg(np.arccos(intermediate))
    
    # Determine the quadrant based on the relative positions.
    if slat > glat:
        if cslon > cglon:
            quad = 1
        else:
            quad = 2
    elif slat < glat:
        if cslon > cglon:
            quad = 4
        else:
            quad = 3
    else:  # slat == glat
        if cslon > cglon:
            quad = 1
        else:
            quad = 2
    quad_1_or_4 = (quad == 1) | (quad == 4)
    quad_2_or_3 = (quad == 2) | (quad == 3)
            
    # Determine if the ground point is in the northern or southern hemisphere.
    if glat >= 0.0:
        northern_hemisphere = True
    else:
        northern_hemisphere = False
        
    # Calculate the azimuth based on quadrant and hemisphere.
    if northern_hemisphere:
        if quad_1_or_4:
            azimuth = A
        elif quad_2_or_3:
            azimuth = 360.0 - A
    else:
        if quad_1_or_4:
            azimuth = 180.0 - A
        elif quad_2_or_3:
            azimuth = 180.0 + A
            
    return azimuth


def ground_azimuth_numpy(glat, glon, slat, slon):
    """
    Computes the ground azimuth between the ground point and another point of interest.

    implemented based on logic in https://github.com/DOI-USGS/ISIS3/blob/3aa6d786147dfcddc3775f1537c84304d886a92f/isis/src/base/objs/Camera/Camera.cpp#L2267
    
    Parameters:
        glat (ndarray): Latitude of the ground point (array-like).
        glon (ndarray): Longitude of the ground point (array-like).
        slat (ndarray): Latitude of the subspacecraft or subsolar point (array-like).
        slon (ndarray): Longitude of the subspacecraft or subsolar point (array-like).
        
    Returns:
        ndarray: Azimuth in degrees.
    """
    # Convert latitudes to radians
    a = np.deg2rad(90.0 - slat)
    b = np.deg2rad(90.0 - glat) 
    # use new values in where when condition is true
    a = np.where(glat < 0.0, np.deg2rad(90.0 + slat), a)
    b = np.where(glat < 0.0, np.deg2rad(90.0 + glat), b)

    # Normalize longitudes to avoid crossing the 180-degree meridian
    cslon = slon.copy()
    cglon = glon.copy()
    diff = np.abs(cslon - cglon) # TODO double check this logic
    cslon = np.where((cslon > cglon) & (diff > 180.0), cslon - 360.0, cslon)
    cglon = np.where((cglon > cslon) & (diff > 180.0), cglon - 360.0, cglon)

    # Compute the central angle
    cos_a = np.cos(a)
    cos_b = np.cos(b)
    sin_a = np.sin(a)
    sin_b = np.sin(b)

    C = np.abs(np.deg2rad(cglon - cslon)) # this abs should be kept
    # clipping to -1.0 to 1.0 might not be smart here?
    c = np.arccos(np.clip(cos_a * cos_b + sin_a * sin_b * np.cos(C), -1.0, 1.0))
    
    # Compute the intermediate angle
    with np.errstate(divide='ignore', invalid='ignore'):
        intermediate = (cos_a - cos_b * np.cos(c)) / (sin_b * np.sin(c))
        intermediate = np.nan_to_num(intermediate, posinf=0.0, neginf=0.0)
    intermediate = np.clip(intermediate, -1.0, 1.0)  # Ensure it is within valid range
    A = np.rad2deg(np.arccos(intermediate))

    # Determine quadrants
    quad = np.zeros_like(glat, dtype=int)
    quad = np.where((slat > glat) & (cslon > cglon), 1, quad)
    quad = np.where((slat > glat) & (cslon < cglon), 2, quad)
    quad = np.where((slat < glat) & (cslon > cglon), 4, quad)
    quad = np.where((slat < glat) & (cslon < cglon), 3, quad)
    quad = np.where((slat == glat) & (cslon > cglon), 1, quad)
    quad = np.where((slat == glat) & (cslon < cglon), 2, quad)
    quad_1_or_4 = (quad == 1) | (quad == 4)
    quad_2_or_3 = (quad == 2) | (quad == 3)
    northern_hemisphere = glat >= 0.0
    southern_hemisphere = ~northern_hemisphere

    # Calculate azimuth
    azimuth = np.zeros_like(glat)
    azimuth = np.where(northern_hemisphere & quad_1_or_4, A, azimuth)
    azimuth = np.where(northern_hemisphere & quad_2_or_3, 360.0 - A, azimuth)
    azimuth = np.where(southern_hemisphere & quad_1_or_4, 180.0 - A, azimuth)
    azimuth = np.where(southern_hemisphere & quad_2_or_3, 180.0 + A, azimuth)

    return azimuth
