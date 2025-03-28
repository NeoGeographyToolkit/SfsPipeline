#!/usr/bin/env python
"""Summarizes images that overlap a region.  Writes out a .csv file of
photometric information, and displays plots."""

# Copyright 2025, Andrew Annex, Ross A. Beyer (rbeyer@rossbeyer.net)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
import textwrap as tw

import fiona
import duckdb
import geopandas as gp
import pyproj
import shapely
import numpy as np

from matplotlib import pyplot as plt
import matplotlib
from pyproj.crs import ProjectedCRS
from pyproj.crs.coordinate_operation import StereographicConversion

from .utils import get_embedded_provenance

# setup pyproj CRSs and transforms
moon_crs_ge = pyproj.CRS.from_user_input('IAU_2015:30100')
moon_crs_np = pyproj.CRS.from_user_input('IAU_2015:30130')
moon_crs_sp = pyproj.CRS.from_user_input('IAU_2015:30135')


def make_stereographic_moon_projection(lon, lat):
    conversion = StereographicConversion(lat, lon)
    proj_crs = ProjectedCRS(conversion, geodetic_crs=moon_crs_ge)
    return proj_crs

def calculate_initial_compass_bearing(deg_lon_A:float, deg_lat_A:float, deg_lon_B:float, deg_lat_B:float)-> float:
    """
    Calculates the bearing between two points.

    The formulae used is the following:
        θ = atan2(sin(Δlong).cos(lat2),
                  cos(lat1).sin(lat2) − sin(lat1).cos(lat2).cos(Δlong))

    :Parameters:

    :Returns:
      The bearing in degrees from 0-360, zero is north, 90 is East, etc.

    :Returns Type:
      float

    """
    # This function is in the public domain, and available at
    # https://gist.github.com/jeromer/2005586
    # modified to work with numpy arrays by A Annex
    lat1 = np.radians(deg_lat_A)
    lat2 = np.radians(deg_lat_B)
    diffLong = np.radians(deg_lon_B - deg_lon_A)
    x = np.sin(diffLong) * np.cos(lat2)
    y = np.cos(lat1) * np.sin(lat2) - (np.sin(lat1) * np.cos(lat2) * np.cos(diffLong))
    initial_bearing = np.atan2(x, y)
    # Now we have the initial bearing but math.atan2 return values
    # from -180° to + 180° which is not what we want for a compass bearing
    # The solution is to normalize the initial bearing as shown below
    initial_bearing = np.degrees(initial_bearing)
    compass_bearing = (initial_bearing + 360) % 360
    return compass_bearing

def _perform_geo_selection_sql(con, wkt_geometry: str):
    # Step 1: Create a temp table with the query geometry.
    con.execute(f"""
    CREATE TEMPORARY TABLE temp_query_geom AS
    SELECT ST_GeomFromText('{wkt_geometry}') AS geom;
    """)
    # Step 2: Create a temp table with rows that intersect the query geometry
    # SUB_SOLAR_GROUND_AZIMUTH is precomputed solar_bearing
    con.execute("""
    CREATE TEMPORARY TABLE temp_intersection AS
    SELECT 
        a.*,
        ST_Area(ST_Intersection(a.geometry, q.geom)) / ST_Area(q.geom) AS fraction_area,
    FROM 
        df_src AS a
    CROSS JOIN 
        temp_query_geom AS q
    WHERE 
        ST_Intersects(a.geometry, q.geom) AND a.INCIDENCE_ANGLE < 95 AND RESOLUTION::float <= 5.0 AND EMISSION_ANGLE::float <= 20.0;
    """)
    # Final step: Query the final results sorted by SUB_SOLAR_GROUND_AZIMUTH, ST_Hilbert(geometry), INCIDENCE_ANGLE and fraction_area.
    # TODO this doesn't go quite as far as I'd want to order the results such that more likely than not nearby rows overlap
    # but it seems to do enough such 
    con.execute("""
    CREATE TEMPORARY TABLE numbered_ordered AS 
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY SUB_SOLAR_GROUND_AZIMUTH,INCIDENCE_ANGLE,ST_Hilbert(ST_Centroid(geometry)),fraction_area) AS orderid,
    FROM temp_intersection;
    CREATE TEMPORARY TABLE temp_final AS 
    SELECT 
        * EXCLUDE geometry, 
        ST_AsText(geometry) as geometry,
        CONCAT('https://wms.lroc.asu.edu/lroc/view_lroc/LRO-L-LROC-2-EDR-V1.0/',PRODUCT_ID) as WMS,
        -- determine if the previous geometry intersects the current row
        COALESCE(
            ST_Intersects(geometry, LAG(geometry) OVER (ORDER BY orderid)),
            false
        ) AS intersects_prior,
    FROM numbered_ordered
    WHERE
        fraction_area > .0025 -- exclude images that don't contribute enough to the coverage as they won't bundle adjust well
    ORDER BY orderid;
    """)
    pass


def perform_geo_selection_duckdb(df_src_path: str, wkt_geometry: str)-> gp.GeoDataFrame:
    # Connect to DuckDB
    with duckdb.connect(config = {'threads': 4}) as con:
        con.sql('SET enable_progress_bar = true;')
        con.sql('SET memory_limit = "4GB";')
        con.install_extension("spatial")
        con.load_extension("spatial")
        # register functions
        con.create_function('calculate_initial_compass_bearing', calculate_initial_compass_bearing)
        # load the database into duckdb
        con.sql(f"CREATE TEMP TABLE df_src AS (SELECT * FROM '{df_src_path}');")
        print(f'Loaded DB: {df_src_path}')
        # create a spatial index R-tree
        con.sql("CREATE INDEX my_idx ON df_src USING RTREE (geometry)")
        print('Created Spatial Index')
        # perform the actual work
        _perform_geo_selection_sql(con, wkt_geometry)
        # convert back to geodataframe
        result_df = con.execute("SELECT * from temp_final").df()
        # print summary of overlaps
        # get info about consecutive intersections, TODO not sure how right this is but at first glance seems okay
        streak_df= con.sql("""
        WITH numbered AS (
          SELECT 
            orderid,
            intersects_prior,
            row_number() OVER (PARTITION BY intersects_prior ORDER BY orderid) AS rn_bool
          FROM temp_final
        ),
        grouped AS (
          SELECT 
            intersects_prior,
            orderid - rn_bool AS grp,       -- Constant for each streak.
            COUNT(*) AS streak_length   -- Length of the streak.
          FROM numbered
          GROUP BY intersects_prior, orderid - rn_bool
        )
        SELECT 
          intersects_prior,
          streak_length,
          COUNT(*) AS streak_count  -- Number of streaks with that length.
        FROM grouped
        GROUP BY intersects_prior, streak_length
        ORDER BY intersects_prior, streak_length;
        """).df()
    print('Streaks for true and false to help understand bundle adjust "window" width:')
    print(streak_df)
    print(f'Overlap prior: {result_df['intersects_prior'].sum()}, out of {len(result_df)}')
    return result_df


def plot_footprints(df: gp.GeoDataFrame, query: gp.GeoDataFrame, title: str, provenance: str = None, use_stereographic=False, to_crs = None):
    if use_stereographic:
        # reproject the centroid to the geographic crs then grab it's lon lat
        centroid = query.centroid.to_crs(moon_crs_ge).iloc[0]
        crs = make_stereographic_moon_projection(centroid.x, centroid.y)
    else:
        crs = to_crs or query.crs
    ax=df.to_crs(crs).plot(alpha=0.2, cmap='Set1')
    if query is not None:
        query.to_crs(crs).plot(ax=ax, edgecolor='black', facecolor='None')
    # Text labels
    ax.set_title(f"{title} LROC Coverage", va='bottom')
    # updated the dpi
    fig = ax.get_figure()
    fig.set_dpi(150)
    # more text stuff
    return ax

def plot_illumination_coverage(df_results: gp.GeoDataFrame, query: gp.GeoDataFrame, title: str, provenance: str = None):
    fig = plt.figure(dpi=150)
    ax_legend = plt.subplot(122)
    ax = plt.subplot(121, projection='polar')
    cmap = matplotlib.colormaps['plasma_r']
    # define the bins
    bins = np.arange(np.floor(min(df_results['INCIDENCE_ANGLE'])),np.ceil(max(df_results['INCIDENCE_ANGLE'])))
    if len(bins) == 1:
        # we had too little data for the bins so split it
        bins = np.linspace(np.floor(min(df_results['INCIDENCE_ANGLE'])),np.ceil(max(df_results['INCIDENCE_ANGLE'])), num=10)
    norm = matplotlib.colors.BoundaryNorm(bins, len(bins))
    # get data to bin assignments
    bin_indices = np.digitize(df_results['INCIDENCE_ANGLE'], bins)
    # get the colors from the cmap based off the bin
    hex_colors = [matplotlib.colors.to_hex(cmap(norm(bin)/len(bins)), keep_alpha=True) for bin in bins]
    # accumulate legend stuff
    legend_content, legend_labels = [], []
    # iterate over bins and plot
    for i in np.arange(1, len(bins))[::-1]:
        bin_range = (bins[i-1], bins[i])
        label = f"{bin_range[0]} <= i < {bin_range[1]}"
        data_indices = bin_indices == i
        # now plot
        stem = ax.stem(
            np.radians(df_results['SUB_SOLAR_GROUND_AZIMUTH'].iloc[data_indices]), 
            df_results['fraction_area'].iloc[data_indices],
            markerfmt=" ",
            basefmt=" ",
            linefmt=hex_colors[i-1],
        )
        # accumulate
        legend_content.append(stem)
        legend_labels.append(label)
    # apply colors
    ax.set_theta_zero_location("N")
    ax.set_rmax(min(1.0, df_results['fraction_area'].max()))
    ax.set_rlabel_position(180)  # Move radial labels
    # ax.grid(True)
    ax.set_thetagrids(np.arange(0, 360, 45), ['N', '', 'W', '', 'S', '', 'E', ''])
    # plot the legend
    ax_legend.axis('off')
    ax_legend.legend(
        legend_content, 
        legend_labels, 
        loc='center', 
        title="Incidence Angle, i",
        fontsize=10)
    ax_legend.set_title(f"{title} LROC Coverage", va='bottom')
    # more text
    if query is not None:
        plt.figtext(
            0.5, 0.01,
            f"""The area analyzed is {query.geometry.iloc[0].wkt}""",
            ha="center",
            fontsize="xx-small"
        )
    plt.figtext(0.01, 0.05, provenance, fontsize="small")
    plt.figtext(0.01, 0.85, tw.fill(
        f"Each line represents 1 of {df_results.shape[0]} LROC images.",
        width=30
    ))
    plt.figtext(0.71, 0.75, tw.fill(
        tw.dedent(
            f"""\
            Line heading indicates the direction from the center of the area to
            the Sun for each image."""
        ),
        width=25
    ))
    plt.figtext(0.72, 0.1, tw.fill(
        tw.dedent(
            f"""\
            The length of the line indicates the fraction of the area the
            image covers."""
        ),
        width=25
    ))

def arg_parser():
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog="In general, you either need to specify --title & --polygon."
    )
    parser.add_argument(
        "-d", "--db_path",
        help="Path to a geoparquet database file containing the database"
    )
    parser.add_argument(
        "-g", "--gpkg",
        nargs="?",
        const="sfs_cover.gpkg",
        help="If given, signifies that a GeoPackage file with the images "
             "that cross the ROI should also be written out."
    )
    parser.add_argument(
        "-i", "--incidence",
        help="For incidence angle coloring in the plot, should be a string "
             "that contains colon-separated integers, like "
             "start:stop:step.  Frequently 82:92:2 for polar work. "
             "If not provided, the incidence angle coloring will scale to the "
             "range of incidence angles."
    )
    parser.add_argument(
        "-m", "--map",
        action="store_true",
        help="Will display a map of overlapping image footprints."
    )
    parser.add_argument(
        "-n", "--name",
        help="The name to use to select a row from the *locations* file."
    )
    parser.add_argument(
        "-o", "--output",
        default="sfs_cover.csv",
        help="Name of the CSV file to write information out to. "
             "Default: %(default)s"
    )
    parser.add_argument(
        "-p", "--polygon",
        help="The WKT representation of a POLYGON of the area which to "
             "inspect.  Would override the 'geom' column if --locations "
             "were specified."
    )
    parser.add_argument(
        "-c", "--polygon_crs",
        default="IAU_2015:30135",
        help="The CRS for the WKT Polygon Provided"
             "Default: %(default)s"
    )
    parser.add_argument(
        "--provenance",
        help="Either a path or a string.  If a string, it is used verbatim. "
             "If a path, it should be the path to a CUMINDEX.TAB file that "
             "supplied the information in the --db_path."
    )
    parser.add_argument(
        "--restrict",
        help="The filename of a geospatial file against which the observations "
             "found are compared and only those that are in both are plotted "
             "and output."
    )
    parser.add_argument(
        "-t", "--title",
        help="The title for the plot.  Would override the 'title' column if "
             "--locations were specified."
    )
    return parser

def main():
    parser = arg_parser()
    args = parser.parse_args()
    # parse query polygon and title
    try:
        title = args.title
        wkt_polygon = args.polygon
        wkt_polygon_crs = args.polygon_crs
        # convert wkt_polygon into a shapely geometry
        polygon = shapely.from_wkt(wkt_polygon)
        # convert the wkt_polygon_crs into a pyproj crs
        polygon_crs = pyproj.CRS.from_user_input(wkt_polygon_crs)
        # construct a query geodataframe 
        df_query = gp.GeoDataFrame(crs=polygon_crs, geometry=[polygon])
         # Load database of LROC index, assuming it's geoparquet
        df = gp.read_parquet(args.db_path)
        # get embedded provenance info
        embedded_provenance = get_embedded_provenance(args.db_path)
        # perform query for downselection and prepare output geodataframe
        # TODO refactor below to avoid use of pandas at all, see find_stereo_pairs.py
        df_results = perform_geo_selection_duckdb(args.db_path, wkt_polygon)
        # convert back to geodataframe
        df_results['geometry'] = gp.GeoSeries.from_wkt(df_results['geometry'])
        df_results = gp.GeoDataFrame(df_results, crs=df.crs)
        ## Begin Reports
        print(f"Found {len(df_results)} total LROC NAC observations (L&R) for provided footprint.")
        ## Begin output
        # write out CSV file TODO: replace with duckdb line
        df_results.to_csv(
            args.output,
            index=False,
            columns=(
                "PRODUCT_ID", "INCIDENCE_ANGLE", "fraction_area", "SUB_SOLAR_GROUND_AZIMUTH",
                "RESOLUTION"
            )
        )
        # write out gpkg if requested TODO: replace with duckdb line
        if args.gpkg:
            df_results.to_file(args.gpkg, driver="GPKG")
        with fiona.open(args.gpkg, "a") as dst: #TODO: replace with duckdb line
            dst.update_tag_item('PROVENANCE', embedded_provenance or "None")
        # plot results after writing out to disk
        plot_footprints(df_results, df_query, title, provenance=embedded_provenance or "None", use_stereographic=True)
        plt.savefig(f'map_{title}.png', dpi=150)
        plt.show()
        plot_illumination_coverage(df_results, df_query, title, provenance=embedded_provenance or "None")
        plt.savefig(f'illumination_{title}.png', dpi=150)
        plt.show()
    except shapely.errors.WKTReadingError as err:
        parser.error(str(err))
    except argparse.ArgumentError as err:
        parser.error(str(err))


if __name__ == '__main__':
    main()