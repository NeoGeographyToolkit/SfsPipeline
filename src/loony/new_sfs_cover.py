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
from pathlib import Path

import geopandas as gp
import pyproj
import shapely
import numpy as np

from matplotlib import pyplot as plt
import matplotlib
from pyproj.crs import ProjectedCRS
from pyproj.crs.coordinate_operation import StereographicConversion

# setup pyproj CRSs and transforms
moon_crs_ge = pyproj.CRS.from_user_input('IAU_2015:30100')
moon_crs_np = pyproj.CRS.from_user_input('IAU_2015:30130')
moon_crs_sp = pyproj.CRS.from_user_input('IAU_2015:30135')


def get_provenance(df: gp.GeoDataFrame):
    """Get the max volume/orbit/most recent date in the dataframe"""
    most_recent = df.loc[df['ORBIT_NUMBER'].idxmax(),:]
    return f"As of PDS Volume {most_recent['VOLUME_ID']},\norbit {most_recent['ORBIT_NUMBER']}, {most_recent['START_TIME']}"


def make_stereographic_moon_projection(lon, lat):
    conversion = StereographicConversion(lat, lon)
    proj_crs = ProjectedCRS(conversion, geodetic_crs=moon_crs_ge)
    return proj_crs

def calculate_initial_compass_bearing(deg_lon_A, deg_lat_A, deg_lon_B, deg_lat_B):
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

def perform_geo_selection(df_all: gp.GeoDataFrame, df_query: gp.GeoDataFrame)-> gp.GeoDataFrame:
    # get geometry
    geom = df_query.geometry.iloc[0]
    # TODO ensure the geom and df are in same crs
    indexes = df_all.sindex.query(geom, predicate='intersects')
    df_selected = df_all.iloc[indexes]
    # filter out high incidence angles
    df_selected = df_selected[df_selected['INCIDENCE_ANGLE'] < 95]
    # update center longitudes to be -180 to 180 by trusting the reprojection of the geometry
    _gt_180 = df_selected['CENTER_LONGITUDE'] > 180.0
    df_selected[_gt_180]['CENTER_LONGITUDE'] = df_selected[_gt_180]['CENTER_LONGITUDE'] - 360
    # update the longitude of the sub solar point to be -180 to 180
    _gt_180 = df_selected['SUB_SOLAR_LONGITUDE'] > 180.0
    df_selected[_gt_180]['SUB_SOLAR_LONGITUDE'] = df_selected[_gt_180]['SUB_SOLAR_LONGITUDE'] - 360
    # add fraction column, if df and geom are in polar CRS this should be roughly right
    # but you can always reproject to a new stereographic projection outside of this code first
    df_selected['fraction_area'] = df_selected.intersection(geom).area / geom.area
    # add the solar bearing column
    df_selected['solar_bearing'] = calculate_initial_compass_bearing(
        df_selected['CENTER_LONGITUDE'],
        df_selected['CENTER_LATITUDE'],
        df_selected['SUB_SOLAR_LONGITUDE'],
        df_selected['SUB_SOLAR_LATITUDE'],
    )

    # perform a final sort
    df_sorted = df_selected.sort_values(by=["INCIDENCE_ANGLE", "fraction_area"])
    return df_sorted

def plot_footprints(df: gp.GeoDataFrame, query: gp.GeoDataFrame, title: str, provenance: str = None, use_stereographic=False):
    if use_stereographic:
        # reproject the centroid to the geographic crs then grab it's lon lat
        centroid = query.centroid.to_crs(moon_crs_ge).iloc[0]
        crs = make_stereographic_moon_projection(centroid.x, centroid.y)
    else:
        crs = query.crs
    ax=df.to_crs(crs).plot(alpha=0.2, cmap='Set1')
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
            np.radians(df_results['solar_bearing'].iloc[data_indices]), 
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
    ax.set_rmax(1.0)
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
    except shapely.errors.WKTReadingError as err:
        parser.error(str(err))
    except argparse.ArgumentError as err:
        parser.error(str(err))
    except Exception as err:
        parser.error(str(err))
    # Load database of LROC index, assuming it's geoparquet
    df = gp.read_parquet(args.db_path)
    # perform query for downselection and prepare output geodataframe
    df_results = perform_geo_selection(df, df_query)
    # get provenance for results based on the database used
    provenance = get_provenance(df)
    ## Begin Reports
    print(f"Found {len(df_results)} total LROC NAC observations (L&R) for provided footprint.")
    ## Begin output
    # write out CSV file
    df_results.to_csv(
        args.output,
        index=False,
        columns=(
            "PRODUCT_ID", "INCIDENCE_ANGLE", "fraction_area", "solar_bearing",
            "RESOLUTION"
        )
    )
    # write out gpkg if requested
    if args.gpkg:
        df_results.to_file(args.gpkg, driver="GPKG")
    # plot results after writing out to disk
    # TODO just output these both as pngs and call it a day
    plot_footprints(df_results, df_query, title, provenance=provenance, use_stereographic=True)
    plt.savefig(f'map_{title}.png', dpi=150)
    plt.show()
    plot_illumination_coverage(df_results, df_query, title, provenance=provenance)
    plt.savefig(f'illumination_{title}.png', dpi=150)
    plt.show()

if __name__ == '__main__':
    main()