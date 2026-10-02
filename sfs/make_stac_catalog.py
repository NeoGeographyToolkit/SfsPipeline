from pathlib import Path

import fire
import pystac.asset
import pystac
from pystac.extensions.view import ViewExtension
from pystac.extensions.projection import ProjectionExtension
import shapely 
from shapely.geometry import GeometryCollection, Polygon, MultiPolygon
import geopandas as gp
from pystac.media_type import MediaType
import numpy as np

properties = [
    'EMISSION_ANGLE',
    'INCIDENCE_ANGLE',
    'PHASE_ANGLE',
    'ROI_SUB_SOLAR_GROUND_AZIMUTH',
    'NORTH_AZIMUTH',
    'ORBIT_NUMBER',
    'RESOLUTION',
    'SOLAR_DISTANCE',
    'SOLAR_LONGITUDE',
    'SUB_SOLAR_AZIMUTH',
    'SUB_SOLAR_GROUND_AZIMUTH',
    'SUB_SOLAR_LATITUDE',
    'SUB_SOLAR_LONGITUDE',
    'SUB_SPACECRAFT_GROUND_AZIMUTH',
    'SUB_SPACECRAFT_LATITUDE',
    'SUB_SPACECRAFT_LONGITUDE',
    'TARGET_CENTER_DISTANCE',
    'VOLUME_ID',
    'WMS',
    'fraction_area'
]

def normalize_geometry(geom):
    if isinstance(geom, GeometryCollection):
        polys = []
        for part in geom.geoms:
            if isinstance(part, Polygon):
                polys.append(part)
            elif isinstance(part, MultiPolygon):
                # if there are nested MultiPolygons, unpack them too
                polys.extend(part.geoms)
        geom = MultiPolygon(polys)
    return geom


def row_to_item(row, cog_folder, url_prefix, tif_postfix, crs_json, crs_wkt):
    # ensure there is a TIF associated with this row and get the path to it
    asset_paths = list(Path(cog_folder).glob(f'{row.PRODUCT_ID}*{tif_postfix}'))
    if len(asset_paths) != 1:
        print(f'Error: had {len(asset_paths)} assets for {row.PRODUCT_ID}: {asset_paths}')
        return None
    # we should only have one asset_path now
    asset_path = f'{url_prefix}/{asset_paths[0].name}' 
    # make the asset # TODO generate thumbnails
    asset = pystac.Asset(
        href=asset_path,
        title=f'{asset_paths[0].name}',
        media_type=MediaType.COG
    )
    # make the item
    bbox = row.geometry.bounds
    # normalize the geometry
    geometry = normalize_geometry(row.geometry)
    # make sure it's not none/empty/invalid
    if geometry is None or geometry.is_empty or not geometry.is_valid:
        print(f"Bad geom for {row.PRODUCT_ID}: {geometry}")
        return None
    # convert to dict
    geometry = shapely.geometry.mapping(geometry)
    # ensure both the bbox and geometry are valid
    if bbox is None or geometry is None:
        print(f"Bad geom for {row.PRODUCT_ID}: b:{bbox} g:{geometry}")
        return None
    # should only be valid geometries past this point
    item = pystac.Item(
        id=row.PRODUCT_ID,
        bbox=bbox,
        geometry=geometry,
        datetime=row.START_TIME.to_pydatetime(),
        properties={p: row[p] for p in properties}
    )
    # common metadata
    item.common_metadata.gsd = row['RESOLUTION']
    item.common_metadata.platform = 'LRO'
    item.common_metadata.instruments = ['LRONAC']
    # add the asset to the item
    item.add_asset(
        key="image",
        asset=asset
    )
    # add the projection extension information
    proj_ext = ProjectionExtension.ext(item, add_if_missing=True)
    proj_ext.epsg = None
    proj_ext.code = "IAU_2015:30135" # TODO grab from CRS info 
    proj_ext.projjson = crs_json
    proj_ext.wkt2 = crs_wkt
    # add the view extension information
    view_ext = ViewExtension.ext(item, add_if_missing=True)
    # STAC’s “incidence” is sensor‑to‑normal; in ISIS that is called emission (INC in ISIS is Sun‑to‑normal)
    view_ext.incidence_angle = row['EMISSION_ANGLE']
    # we will override this field instead of using the SubSpacecraftGroundAzimuth
    view_ext.azimuth = row['SUB_SPACECRAFT_GROUND_AZIMUTH']
    # we will override this field instead of using the azimuth parameter
    view_ext.sun_azimuth = row['ROI_SUB_SOLAR_GROUND_AZIMUTH']
    # sun elevation is compliment to incidence angle
    view_ext.sun_elevation = 90.0 - row['INCIDENCE_ANGLE']
    # return the item
    return item


def split_into_small_collections(df, size: int = 20):
    # number of splits
    num = int(np.ceil(len(df)/size))
    # use array split
    df_splits = np.array_split(df, num)
    # and return 
    return df_splits


def split_to_collections(df, catalog, out_name, cog_folder, url_prefix, tif_postfix, size: int = 20):
    # perform the spliut
    for index_s, df_s in enumerate(split_into_small_collections(df, size=size)):
        print(f'running sub collection {index_s}')
        # get the spatial_extent
        spatial_extent = pystac.SpatialExtent(bboxes=[list(df_s.total_bounds)])
        # get the temporal extent
        temporal_extent = pystac.TemporalExtent(intervals=[df_s['START_TIME'].min(), df_s['START_TIME'].max()])
        # construct the Extent
        collection_extent = pystac.Extent(
            spatial=spatial_extent,
            temporal=temporal_extent
        )
        # get the terms we will use to name and label the collection
        min_rssga = float(df_s.ROI_SUB_SOLAR_GROUND_AZIMUTH.min())
        max_rssga = float(df_s.ROI_SUB_SOLAR_GROUND_AZIMUTH.max())
        # construct the catalog
        collection = pystac.Collection(
            id=f"{out_name}_{min_rssga:0>6.0f}_to_{max_rssga:0>6.0f}",
            title=f"{out_name}_{min_rssga:0>6.0f}_to_{max_rssga:0>6.0f}",
            description=f"Collection of COGs from {min_rssga:0.4f} to {max_rssga:0.4f} RSSGA",
            extent=collection_extent,
            stac_extensions=[
                "https://stac-extensions.github.io/projection/v2.0.0/schema.json", 
                "https://stac-extensions.github.io/view/v1.0.0/schema.json"
            ]
        )
        # get the wkt crs
        crs_wkt = df_s.crs.to_wkt()
        # get the json crs
        crs_json = df_s.crs.to_json_dict()
        # construct the Items and Assets for each entry in the df
        for index, row in df_s.iterrows():
            # make the item
            item = row_to_item(row, cog_folder, url_prefix, tif_postfix, crs_json, crs_wkt)
            # add the item to the catalog if it's not None
            if item:
                collection.add_item(item)
        # add the collection to the catalog
        catalog.add_child(collection)
        # pass
        pass



def run(path_to_db: str, out_name: str, cog_folder: str = None, tif_postfix: str = "lerc.cog.tif", url_prefix: str = "http://localhost:8080"):
    """
    Create a STAC catalog to a collection of tifs and an associated geodatabase file
    
    https://github.com/stac-utils/pystac/blob/main/docs/tutorials/how-to-create-stac-catalogs.ipynb
    """
    # load the db as a geodataframe
    df = gp.read_file(path_to_db)
    # sort by RSSGA inplace
    df.sort_values(by='ROI_SUB_SOLAR_GROUND_AZIMUTH', inplace=True)
    # get the cog folder, will be CWD if None
    if cog_folder is None:
        cog_folder = str(Path.cwd())
    # construct the Catalog object
    catalog = pystac.Catalog(
        id=f"{out_name}",
        title=f"COGS in {cog_folder}",
        description=f"STAC Catalog for TIFs ending with {tif_postfix} in folder {cog_folder}",
        # extra_fields
    )
    # split the data into sub collections
    split_to_collections(df, catalog, out_name, cog_folder, url_prefix, tif_postfix, size=20)
    # Okay theoretically it's all done at this point so save it out (will need to debug a bit here)
    catalog.normalize_hrefs(str(Path.cwd() / 'stac'))
    print(catalog.get_self_href())
    #print(catalog.validate_all())
    catalog.save(
        catalog_type=pystac.CatalogType.SELF_CONTAINED
    )
    # 



if __name__ == '__main__':
    fire.Fire(run)