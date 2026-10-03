#!/usr/bin/env python


# https://duckdb.org/docs/api/python/function
import abc
import argparse
import numpy as np
import numpy.core.multiarray
import duckdb
import math
from shapely import wkt
from shapely import Polygon
import geopandas as gpd

import fiona
from sfs.utils import get_embedded_provenance


def quality_ideal(value: float, ideal: float, low: float, high: float) -> float:
    """
    The value of *ideal* would be a perfect value of *value*, but
    if *value* is between *low* and *high* it is acceptable.  *ideal*
    must be between *low* and *high*, otherwise a ValueError is raised.
    
    A quality value of one indicates that *value* is *ideal*.
    Quality values between zero and one indicate that *value*
    is between *low* and *high* (the closer to *ideal*, the higher
    the quality score).  Values less than zero are beyond the
    acceptable range of *low* and *high*.
    """
    if not (low <= ideal <= high):
            raise ValueError(
                f"The ideal value ({ideal}) is not between low ({low}) and "
                f"high ({high})."
            )
    if value == ideal:
        return 1.0
    if value < ideal:
        return (value - low) / (ideal - low)
    else:
        return (value - high) / (ideal - high)


def quality_bounded(value: float, ideal_low, ideal_high, low: float, high: float) -> float:
    """
    If *ideal* is a two-tuple, then this indicates that all values
    between and including those values are "ideal" values.  Again,
    these two values must be between *low* and *high*

    Return a quality value based on *value*.
    A quality value of one indicates that *value* is *ideal*.
    Quality values between zero and one indicate that *value*
    is between *low* and *high* (the closer to *ideal*, the higher
    the quality score).  Values less than zero are beyond the
    acceptable range of *low* and *high*.
    """
    if not (low <= ideal_low <= ideal_high <= high):
        raise ValueError(
            f"The ideal values ({ideal_low}, {ideal_high}) is are not between low "
            f"({low}) and high ({high})."
        )
    if ideal_low <= value <= ideal_high:
        return 1
    if value < ideal_low:
        return (value - low) / (ideal_low - low)
    else:
        return (value - high) / (ideal_high - high)


def incidence_quality(incidence_angle: float) -> float:
    """Returns a quality score based on the value of *incidence_angle*,
    which is expected to be in decimal degrees, zero being normal to
    the surface.

    Becker et al. (2015) indicates:
    - Limits: Between 40° and 65° depending on smoothness
        (shadows to be avoided).
    - Recommended: Nominally 50°
    """
    return quality_ideal(incidence_angle, 50, 40, 65)


def emission_quality(emission_angle: float) -> float:
    """Returns a quality score based on the value of *emission_angle*,
    which is expected to be in decimal degrees, zero being normal to
    the surface.

    Becker et al. (2015) indicates:
    - Limits: Between 0° and the complement of the maximum slope
      (conservatively 45°, greater for smoother terrains) for optical images.
      Greater than the slope (≥15° even for smooth surfaces) for radar.
    - Recommended: No recommendation
    """
    return quality_ideal(emission_angle, 22.5, 0, 45)


def phase_quality(phase_angle: float) -> float:
    """Returns a quality score based on the value of *phase_angle*,
    which is expected to be in decimal degrees, zero being normal to
    the surface.

    Becker et al. (2015) indicates:
    - Limits: Between 5° and 120°.
    - Recommended: ≥ 30°
    """
    return quality_ideal(phase_angle, 60, 5, 120)


def gsd_quality(gsd1: float, gsd2: float) -> float:
    """Returns a quality score based on the two ground
    sample distances, *gsd1* and *gsd2*.

    Image pairs with GSD ratios larger than 2.5 can be used but are
    not optimal, as details only seen in the smaller scale image
    will be lost. If required, images with ratios greater than ~2.5
    should be resampled to the GSD of the lower scale image
    (Becker at al., 2015).
    """
    ratio = max(gsd1, gsd2) / min(gsd1, gsd2)
    return quality_ideal(ratio, 1, 1, 2.5)


def stereo_strength_quality(parallax_height_ratio: float) -> float:
    """Returns a quality score based on the Parallax/Height Ratio (*dp*).

    Becker et al. (2015) indicates:
    - Limits: Between 0.1 (5°) and 1 (~45°).
    - Recommended: 0.4 (20°) to 0.6 (30°).
    """
    return quality_bounded(parallax_height_ratio, 0.4, 0.6, 0.1, 1)


def illumination_quality(shadow_tip_distance: float) -> float:
    """Returns a quality score based on the Shadow-Tip Distance (*dsh*).

    Becker et al. (2015) indicates:
    - Limits: 0 to 2.58.
    - Recommended: 0
    """
    return quality_ideal(shadow_tip_distance, 0, 0, 2.58)


def delta_solar_az_quality(az1: float, az2: float) -> float:
    """Returns a quality score based on the two solar azimuth values,
    in degrees.

    In practice, Shadow-Tip Distance alone does not guarantee similar
    illumination.  The absolute difference in solar azimuth angle
    between stereo pairs can be optionally constrained.

    Becker et al. (2015) indicates:
    - Limits: 0° to 100°.
    - Recommended: ≤ 20°
    """
    az_diff = abs(az1 - az2)
    return quality_bounded(az_diff, 0, 20, 0, 100)


def stereo_overlap_quality(area_fraction: float) -> float:
    """Returns a quality score based on the stereo area overlap.

    Becker et al. (2015) indicates:
    - Limits: Between 30% and 100%.
    - Recommended: 50% to 100%.
    """
    return quality_bounded(area_fraction, 0.5, 1.0, 0.3, 1)


def parallax(
    emission1: float, 
    gndaz1: float, 
    emission2: float, 
    gndaz2: float
) -> float:
    """Returns the parallax angle between the two look vectors described
       by the emission angles and sub-spacecraft ground azimuth angles.

       Input angles are assumed to be radians, as is the return value."""
    one_dot_two = (
        (math.sin(gndaz1) * math.sin(emission1) * math.sin(gndaz2) * math.sin(emission2)) + \
        (math.cos(gndaz1) * math.sin(emission1) * math.cos(gndaz2) * math.sin(emission2)) + \
        (math.cos(emission1) * math.cos(emission2))
    )
    return math.acos(one_dot_two)


def dp(
    emission1: float,
    gndaz1: float,
    emission2: float,
    gndaz2: float,
)-> float:
    """Returns the Parallax/Height Ratio (dp) as detailed in
    Becker et al.(2015).

    The input angles are assumed to be in radians.  If *radar* is true,
    then cot() is substituted for tan() in the calculations.

    Physically, dp represents the amount of parallax difference
    that would be measured between an object in the two images, for
    unit height.
    """
    px1 = -1 * math.tan(emission1) * math.cos(gndaz1)
    px2 = -1 * math.tan(emission2) * math.cos(gndaz2)
    py1 = math.tan(emission1) * math.sin(gndaz1)
    py2 = math.tan(emission2) * math.sin(gndaz2)
    return math.sqrt((px1 - px2) ** 2 + (py1 - py2) ** 2)


def dsh(
    incidence1: float,
    solar_az1: float,
    incidence2: float, 
    solar_az2: float
) -> float:
    """Returns the Shadow-Tip Distance (dsh) as detailed in
    Becker et al.(2015).

    The input angles are assumed to be in radians.

    This is defined as the distance between the tips of the shadows
    in the two images for a hypothetical vertical post of unit
    height. The "shadow length" describes the shadow of a hypothetical
    pole so it applies whether there are actually shadows in the
    image or not. It's a simple and consistent geometrical way to
    quantify the difference in illumination. This quantity is
    computed analogously to dp.
    """
    shx1 = -1 * math.tan(incidence1) * math.cos(solar_az1)
    shx2 = -1 * math.tan(incidence2) * math.cos(solar_az2)
    shy1 = math.tan(incidence1) * math.sin(solar_az1)
    shy2 = math.tan(incidence2) * math.sin(solar_az2)
    return math.sqrt((shx1 - shx2) ** 2 + (shy1 - shy2) ** 2)


def gsd_ratio(
    resolution1: float, 
    resolution2: float
) -> float:
    _max = max(resolution1, resolution2)
    _min = min(resolution1, resolution2)
    return _max/_min


def angular_separation_acos(deg1: float, deg2: float)-> float:
    # Convert degrees to radians
    a = np.radians(deg1)
    b = np.radians(deg2)
    # Compute separation using arccos of cosine of the difference
    separation_rad = np.arccos(np.cos(a - b))
    # Convert result back to degrees, if desired
    return np.degrees(separation_rad)


def get_min_box(wkt_geometry: str)-> str:
    geom = wkt.loads(wkt_geometry)
    res = geom.minimum_rotated_rectangle
    return res.wkt


def get_height_width(wkt_geometry: str)-> tuple[float, float]:
    geom = wkt.loads(wkt_geometry)
    box = geom.minimum_rotated_rectangle
    x, y = box.exterior.coords.xy
    d1 = np.sqrt((x[1] - x[0])**2 + (y[1] - y[0])**2)
    d2 = np.sqrt((x[2] - x[1])**2 + (y[2] - y[1])**2)
    height = max(d1, d2)
    width = min(d1,d2)
    return height, width 


def get_height(wkt_geometry: str)-> float:
    geom = wkt.loads(wkt_geometry)
    box = geom.minimum_rotated_rectangle
    x, y = box.exterior.coords.xy
    d1 = np.sqrt((x[1] - x[0])**2 + (y[1] - y[0])**2)
    d2 = np.sqrt((x[2] - x[1])**2 + (y[2] - y[1])**2)
    height = max(d1, d2)
    return height


def get_width(wkt_geometry: str)-> float:
    geom = wkt.loads(wkt_geometry)
    box = geom.minimum_rotated_rectangle
    x, y = box.exterior.coords.xy
    d1 = np.sqrt((x[1] - x[0])**2 + (y[1] - y[0])**2)
    d2 = np.sqrt((x[2] - x[1])**2 + (y[2] - y[1])**2)
    width = min(d1,d2)
    return width


def arg_parser():
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog="In general, you either need to specify --title & --polygon."
    )
    parser.add_argument(
        "-d", "--db_path",
        help="Path to a geopandas file created by sfs-cover (don't use the geoparquet files!)"
    )
    parser.add_argument(
        "-p", "--polygon",
        help="The WKT representation of a POLYGON of the area which to "
             "inspect.  Would override the 'geom' column if --locations "
             "were specified."
    )
    parser.add_argument(
        "-g", "--gpkg",
        help="If given, signifies that a GeoPackage file with the images "
             "that cross the ROI should also be written out."
    )
    parser.add_argument(
        "--min_diff_emi",
        type=float, default=6.0,
        help="minimum (inclusive) acceptable difference in emission angle for a stereo pair"
    )
    parser.add_argument(
        "--max_diff_emi",
        type=float, default=30.0,
        help="maximum (inclusive) acceptable difference in emission angle for a stereo pair"
    )
    parser.add_argument(
        "--max_diff_slrgaz",
        type=float, default=30.0,
        help="maximum (inclusive) difference is solar ground azimuth for a stereo pair"
    )
    return parser


def main():
    parser = arg_parser()
    args = parser.parse_args()
    # Connect to DuckDB
    con = duckdb.connect(config = {'threads': 4})
    con.sql('SET enable_progress_bar = true;')
    con.sql('SET memory_limit = "4GB";')
    con.install_extension("spatial")
    con.load_extension("spatial")
    # register functions
    con.create_function("incidence_quality", incidence_quality)
    con.create_function("emission_quality", emission_quality)
    con.create_function("phase_quality", phase_quality)
    con.create_function("gsd_quality", gsd_quality)
    con.create_function("stereo_strength_quality", stereo_strength_quality)
    con.create_function("illumination_quality", illumination_quality)
    con.create_function("delta_solar_az_quality", delta_solar_az_quality)
    con.create_function("stereo_overlap_quality", stereo_overlap_quality)
    #
    con.create_function("parallax", parallax)
    con.create_function("parallax_height_ratio", dp)
    con.create_function("shadow_tip_distance", dsh)
    con.create_function("gsd_ratio", gsd_ratio)
    con.create_function("rect_height", get_height)
    con.create_function("rect_width", get_width)
    con.create_function("angular_separation_acos", angular_separation_acos)
    # fetch the crs of the source database
    crs_info = con.sql(f"SELECT layers[1].geometry_fields[1].crs.auth_name as name, layers[1].geometry_fields[1].crs.auth_code as code FROM st_read_meta('{args.db_path}');").df().iloc[0].to_dict()
    if crs_info['name'] == 'IAU':
        crs_info['name'] = 'IAU_2015'
    # load the database into duckdb
    con.sql(f"CREATE TEMP TABLE df AS SELECT * FROM ST_READ('{args.db_path}');")
    print(f'Loaded DB: {args.db_path}')
    # get embedded provenance info
    embedded_provenance = get_embedded_provenance(args.db_path)
    # create a spatial index R-tree
    con.sql("CREATE INDEX my_idx ON df USING RTREE (geom)")
    print('Created Spatial Index')
    # create the query geometry as a 1 row table to permit additional sub filtering
    con.sql(f"CREATE TEMP TABLE roi AS SELECT ST_MakeValid(ST_GeomFromText('{args.polygon}')) as geom;")
    # compute all the pair-wise intersections for analysis
    print("Performing spatial join (this will be slow for large source databases...)")
    con.sql(f"""
    CREATE TEMP TABLE 
            pairs_raw
    AS SELECT
            L.PRODUCT_ID      as L_PRODUCT_ID,
            L.VOLUME_ID       as L_VOLUME_ID,
            L.ORBIT_NUMBER    as L_ORBIT_NUMBER,
            L.PHASE_ANGLE     as L_PHASE_ANGLE,
            L.EMISSION_ANGLE  as L_EMISSION_ANGLE,
            L.INCIDENCE_ANGLE as L_INCIDENCE_ANGLE,
            L.ROI_SUB_SOLAR_GROUND_AZIMUTH as L_ROI_SUB_SOLAR_GROUND_AZIMUTH,
            L.SUB_SPACECRAFT_GROUND_AZIMUTH as L_SUB_SPACECRAFT_GROUND_AZIMUTH,
            L.RESOLUTION      as L_RESOLUTION,
            ST_AREA(L.geom)   as L_area,
            R.PRODUCT_ID      as R_PRODUCT_ID,
            R.VOLUME_ID       as R_VOLUME_ID,
            R.ORBIT_NUMBER    as R_ORBIT_NUMBER,
            R.PHASE_ANGLE     as R_PHASE_ANGLE,
            R.EMISSION_ANGLE  as R_EMISSION_ANGLE,
            R.INCIDENCE_ANGLE as R_INCIDENCE_ANGLE,
            R.ROI_SUB_SOLAR_GROUND_AZIMUTH as R_ROI_SUB_SOLAR_GROUND_AZIMUTH,
            R.SUB_SPACECRAFT_GROUND_AZIMUTH as R_SUB_SPACECRAFT_GROUND_AZIMUTH,
            R.RESOLUTION      as R_RESOLUTION,
            ST_AREA(R.geom)   as R_area,
            ST_INTERSECTION(L.geom, R.geom) as geom,
            ABS(L.EMISSION_ANGLE - R.EMISSION_ANGLE) as EMISSION_DIFF,
    FROM 
        df L
    JOIN 
        df R 
    ON 
        ST_OVERLAPS(L.geom, R.geom)
    WHERE
        L_PRODUCT_ID != R_PRODUCT_ID  -- Ensures no duplicate pairs and excludes self-matches
    AND
        L_EMISSION_ANGLE < R_EMISSION_ANGLE -- Ensures left is more NADIR than right
    AND 
        EMISSION_DIFF >= {args.min_diff_emi}
    AND
        EMISSION_DIFF <= {args.max_diff_emi};
    """)
    count = con.sql("SELECT COUNT(*) from pairs_raw;").fetchall()
    print(f"Started off with {count[0][0]} pairs before filtering...")
    # con.execute(f"""
    # COPY (SELECT * FROM pairs_raw) TO './prefilter.fgb'         
    # WITH (FORMAT GDAL, DRIVER 'FlatGeobuf', SRS '{crs_info["name"]}:{crs_info["code"]}');
    # """)
    # compute stereo quality metrics for all results
    con.sql("""
    CREATE TEMP TABLE
        stereo_pairs
    AS SELECT
        p.*,
        -- add wms urls for quick viewing
        CONCAT('https://wms.lroc.asu.edu/lroc/view_lroc/LRO-L-LROC-2-EDR-V1.0/',p.L_PRODUCT_ID) as L_VIEW,
        CONCAT('https://wms.lroc.asu.edu/lroc/view_lroc/LRO-L-LROC-2-EDR-V1.0/',p.R_PRODUCT_ID) as R_VIEW,
        ST_INTERSECTION(p.geom, roi.geom) as roi_overlap_geom,
        ABS(p.L_ROI_SUB_SOLAR_GROUND_AZIMUTH - p.R_ROI_SUB_SOLAR_GROUND_AZIMUTH) as SOLAR_AZ_DIFF,
        angular_separation_acos(p.L_ROI_SUB_SOLAR_GROUND_AZIMUTH, p.R_ROI_SUB_SOLAR_GROUND_AZIMUTH) as SOLAR_AZ_ACOS_DIFF,
        (ST_AREA(p.geom) / p.L_AREA) * 100 AS OVERLAP_PERCENTAGE,
        (ST_AREA(ST_INTERSECTION(p.geom, roi.geom)) / ST_AREA(roi.geom)) * 100 AS ROI_OVERLAP_PERCENTAGE,
        parallax(radians(p.L_EMISSION_ANGLE), radians(p.L_SUB_SPACECRAFT_GROUND_AZIMUTH), radians(p.R_EMISSION_ANGLE), radians(p.R_SUB_SPACECRAFT_GROUND_AZIMUTH)) as PARALLAX_ANGLE,
        parallax_height_ratio(radians(p.L_EMISSION_ANGLE), radians(p.L_SUB_SPACECRAFT_GROUND_AZIMUTH), radians(p.R_EMISSION_ANGLE), radians(p.R_SUB_SPACECRAFT_GROUND_AZIMUTH)) as PARALLAX_HEIGHT_RATIO,
        shadow_tip_distance(radians(p.L_INCIDENCE_ANGLE), radians(p.L_ROI_SUB_SOLAR_GROUND_AZIMUTH), radians(p.R_INCIDENCE_ANGLE), radians(p.R_ROI_SUB_SOLAR_GROUND_AZIMUTH)) as SHADOW_TIP_DISTANCE,
        gsd_ratio(p.L_RESOLUTION::DOUBLE, p.R_RESOLUTION::DOUBLE) as GSD_RATIO,
        -- other pair dependent quality metrics here
        incidence_quality(p.L_INCIDENCE_ANGLE::FLOAT) as L_INCIDENCE_QUALITY,
        incidence_quality(p.R_INCIDENCE_ANGLE::FLOAT) as R_INCIDENCE_QUALITY,
        phase_quality(p.L_PHASE_ANGLE::FLOAT) as L_PHASE_QUALITY,
        phase_quality(p.R_PHASE_ANGLE::FLOAT) as R_PHASE_QUALITY,
        emission_quality(p.L_EMISSION_ANGLE::FLOAT) as L_EMISSION_QUALITY,
        emission_quality(p.R_EMISSION_ANGLE::FLOAT) as R_EMISSION_QUALITY,                      
        gsd_quality(p.L_RESOLUTION::FLOAT, p.R_RESOLUTION::FLOAT) as GSD_QUALITY,
        delta_solar_az_quality(p.L_ROI_SUB_SOLAR_GROUND_AZIMUTH::FLOAT, p.R_ROI_SUB_SOLAR_GROUND_AZIMUTH::FLOAT) as DELTA_SOLAR_AZ_QUALITY,
    FROM 
        pairs_raw as p
    JOIN
        roi 
    ON
        ST_OVERLAPS(p.geom, roi.geom)
    WHERE
        GSD_RATIO < 2.25
    AND
        ROI_OVERLAP_PERCENTAGE > .00005  
    AND
        OVERLAP_PERCENTAGE > 25.0
    AND
        ST_XMax(roi_overlap_geom) - ST_XMin(roi_overlap_geom) >= 1000
    AND
        ST_YMax(roi_overlap_geom) - ST_YMin(roi_overlap_geom) >= 1000
    ORDER BY
        ROI_OVERLAP_PERCENTAGE desc,
        OVERLAP_PERCENTAGE desc;        
    """)
    con.sql(f"""
    CREATE TEMP TABLE
        stereo_pairs_filtered
    AS SELECT
        *,
        rect_height(ST_AsText(roi_overlap_geom)) as HEIGHT,
        rect_width(ST_AsText(roi_overlap_geom)) as WIDTH,
        -- quality checks
        illumination_quality(SHADOW_TIP_DISTANCE::FLOAT) as ILLUMINATION_QUALITY,
        stereo_strength_quality(PARALLAX_HEIGHT_RATIO::FLOAT) as STEREO_STRENGTH_QUALITY,
        -- make a drake like quality check to quickly determine if any are negative
        CASE
            WHEN LEAST(L_INCIDENCE_QUALITY, L_PHASE_QUALITY, L_EMISSION_QUALITY, R_INCIDENCE_QUALITY, R_PHASE_QUALITY, R_EMISSION_QUALITY, GSD_QUALITY, DELTA_SOLAR_AZ_QUALITY, ILLUMINATION_QUALITY, STEREO_STRENGTH_QUALITY) < 0 THEN 0 ELSE 1
        END AS QUALITY
    FROM
        stereo_pairs
    WHERE
        HEIGHT / WIDTH <= 5
    AND
        ST_NumPoints(roi_overlap_geom) > 3
    AND
        SOLAR_AZ_ACOS_DIFF < {args.max_diff_slrgaz}
    ORDER BY
        ROI_OVERLAP_PERCENTAGE desc,
        OVERLAP_PERCENTAGE desc;
            """)


    count = con.sql("SELECT COUNT(*) from stereo_pairs_filtered;").fetchall()
    print(f"After filtering left with {count[0][0]} pairs...")
    # write out gpkg file for the moment until 
    con.execute(f"""
    COPY (SELECT * EXCLUDE (roi_overlap_geom) FROM stereo_pairs_filtered) TO '{args.gpkg}'         
    WITH (FORMAT GDAL, DRIVER 'GPKG', SRS '{crs_info["name"]}:{crs_info["code"]}');
    """)
    with fiona.open(args.gpkg, "a") as dst:
        dst.update_tag_item('PROVENANCE', embedded_provenance or "None")
    print(f"Wrote {args.gpkg}\n Done!")
    # Filter out skinny slivers
    con.close()


if __name__ == '__main__':
    main()