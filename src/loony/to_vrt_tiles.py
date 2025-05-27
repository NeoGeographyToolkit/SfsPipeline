import fire
import shapely
import affine
import geopandas as gp
import rasterio as rio
from rasterio import shutil as rio_shutil
from dataclasses import dataclass, asdict
import numpy as np
import json

from pathlib import Path

@dataclass
class Tile:
    minx: float
    miny: float
    maxx: float
    maxy: float
    i: int = 0
    j: int = 0

    def as_projwin(self):
        return self.minx, self.miny, self.maxx, self.maxy

    def as_ullr(self):
        return self.minx, self.maxy, self.maxx, self.miny
    
    def as_geometry(self)-> shapely.Polygon:
        return shapely.box(*self.as_projwin())
    
    def width(self):
        # todo round to nearest half meter
        return self.maxx-self.minx

    def height(self):
        # todo round to nearest half meter
        return self.maxy-self.miny
    
    def to_affine(self, res=1.0):
        return affine.Affine(res, 0.0, self.minx, 0.0, -res, self.maxy)  


def _create_tiles_by_width(xmin, ymin, xmax, ymax, width: int = 8_000):
    x0 = np.arange(xmin, xmax, width)
    x0 = x0[x0 <= xmax]
    y0 = np.arange(ymax, ymin, -width)
    y0 = y0[y0 >= ymin]
    # these are the upper left corener start coordinates for each cell
    tiles = []
    for i, l in enumerate(x0):
        for j, t in enumerate(y0):
            r = l + width
            b = t - width
            tiles.append(Tile(float(l), float(b), float(r), float(t), i=i, j=j))
    return tiles


def _create_tiles_by_number_y(xmin, ymin, xmax, ymax, at_most_along_y=8):
    """
    Create a rectangular grid using a specified number of cells
    """
    cells_on_side=at_most_along_y
    cell_size = float(np.ceil((ymax-ymin) / cells_on_side) + 0.5)
    x0 = np.arange(xmin, xmax, cell_size)
    x0 = x0[x0 <= xmax]
    y0 = np.arange(ymax, ymin, -cell_size)
    y0 = y0[y0 >= ymin]
    # these are the upper left corener start coordinates for each cell
    tiles = []
    for i, l in enumerate(x0):
        for j, t in enumerate(y0):
            r = l + cell_size
            b = t - cell_size
            tiles.append(Tile(float(l), float(b), float(r), float(t), i=i, j=j))
    return tiles


def _create_tiles_by_number_x(xmin, ymin, xmax, ymax, at_most_along_x=8):
    """
    Create a rectangular grid using a specified number of cells
    """
    cells_on_side=at_most_along_x
    cell_size = float(np.ceil((xmax-xmin) / cells_on_side) + 0.5)
    x0 = np.arange(xmin, xmax, cell_size)
    x0 = x0[x0 <= xmax]
    y0 = np.arange(ymax, ymin, -cell_size)
    y0 = y0[y0 >= ymin]
    # these are the upper left corener start coordinates for each cell
    tiles = []
    for i, l in enumerate(x0):
        for j, t in enumerate(y0):
            r = l + cell_size
            b = t - cell_size
            tiles.append(Tile(float(l), float(b), float(r), float(t), i=i, j=j))
    return tiles

def _x_with_overlap(xmin, xmax, step_size=8192, overlap=1024):
    if xmin < xmax:
        yield xmin
    current = (xmin + step_size) - overlap
    if current >= xmax:
        return
    yield from _x_with_overlap(current, xmax, step_size=step_size, overlap=overlap)

def _y_with_overlap(ymin, ymax, step_size=8192, overlap=1024):
    if ymin < ymax:
        yield ymax
    current = (ymax - step_size) + overlap
    if current <= ymin:
        return
    yield from _y_with_overlap(ymin, current, step_size=step_size, overlap=overlap)

def _create_tiles_by_width_with_overlap(xmin, ymin, xmax, ymax, width: int=8_000, overlap: int = 256):
    """
    Create a rectangular grid with a specified overlap
    """
    assert overlap < width
    if width/overlap < 4:
        raise RuntimeError('Too much overlap!')
    x0 = np.array(list(_x_with_overlap(xmin, xmax, step_size=width, overlap=overlap)))
    x0 = x0[x0 <= xmax]
    y0 = np.array(list(_y_with_overlap(ymin, ymax, step_size=width, overlap=overlap)))
    y0 = y0[y0 >= ymin]
    # these are the upper left corener start coordinates for each cell
    tiles = []
    for i, l in enumerate(x0):
        for j, t in enumerate(y0):
            r = l + width
            b = t - width
            tiles.append(Tile(float(l), float(b), float(r), float(t), i=i, j=j))
    return tiles


class VrtTiles(object):

    def __init__(self):
        self._crs = None
        self._tiles: list[Tile] = []

    def to_geojson(self):
        for tile in self._tiles:
            feature = dict(shapely.geometry.mapping(tile.as_geometry()))
            feature['properties']={'i': str(tile.i), 'j': str(tile.j)}
            print(json.dumps(feature), flush=True) 

    def to_gpkg(self, out_name):
        features = []
        for tile in self._tiles:
            tile_dict = asdict(tile)
            tile_dict['geometry'] = tile.as_geometry()
            features.append(tile_dict)
        df = gp.GeoDataFrame.from_records(features)
        df = df.set_geometry('geometry')
        df.set_crs(self._crs, inplace=True)
        df.to_file(out_name, driver='GPKG')

    def dem_to_tiles_by_width(self, dem_path: str, width: int = 4_000):
        """
        Given a dem, convert it to tile bounds following the projwin paradigm
        """
        # first read in the raster and get the bounds
        with rio.open(dem_path, 'r') as src:
            self._crs = src.crs
            bounds = src.bounds
        # convert to minx,miny,maxx,maxy
        minx = bounds.left
        miny = bounds.bottom
        maxx = bounds.right
        maxy = bounds.top
        # get tiles
        self._tiles = _create_tiles_by_width(minx, miny, maxx, maxy, width=width)
        # and return the tiles
        return self
    
    def dem_to_tiles_by_width_with_overlap(self, dem_path: str, width: int = 4_000, overlap: int = 768):
        """
        Given a dem, convert it to tile bounds following the projwin paradigm
        """
        # first read in the raster and get the bounds
        with rio.open(dem_path, 'r') as src:
            self._crs = src.crs
            bounds = src.bounds
        # convert to minx,miny,maxx,maxy
        minx = bounds.left
        miny = bounds.bottom
        maxx = bounds.right
        maxy = bounds.top
        # get tiles
        self._tiles = _create_tiles_by_width_with_overlap(minx, miny, maxx, maxy, width=width, overlap=overlap)
        # and return the tiles
        return self

    def dem_to_tiles_by_number_x(self, dem_path: str, along_x: int = 4):
        """
        Given a dem, convert it to tile bounds following the projwin paradigm
        """
        # first read in the raster and get the bounds
        with rio.open(dem_path, 'r') as src:
            self._crs = src.crs
            bounds = src.bounds
        # convert to minx,miny,maxx,maxy
        minx = bounds.left
        miny = bounds.bottom
        maxx = bounds.right
        maxy = bounds.top
        # get tiles
        self.tiles = _create_tiles_by_number_x(minx, miny, maxx, maxy, at_most_along_x=along_x)
        # and return the tiles
        return self

    def dem_to_tiles_by_number_y(self, dem_path: str, along_y: int = 4):
        """
        Given a dem, convert it to tile bounds following the projwin paradigm
        """
        # first read in the raster and get the bounds
        with rio.open(dem_path, 'r') as src:
            self._crs = src.crs
            bounds = src.bounds
        # convert to minx,miny,maxx,maxy
        minx = bounds.left
        miny = bounds.bottom
        maxx = bounds.right
        maxy = bounds.top
        # get tiles
        self._tiles = _create_tiles_by_number_y(minx, miny, maxx, maxy, at_most_along_y=along_y)
        # and return the tiles
        return self
    
    def _to_vrt_tiles(self, dem_path: str, tiles: list[Tile]):
        # get the basename
        basename = Path(dem_path).name.split('.')[0]
        # open the dem again to get access
        with rio.open(dem_path) as src:
            self._crs = src.crs
            # begin to iterate through the tiles
            for tile in tiles:
                # set the path to the tile's vrt
                tile_path = f'{basename}.tile.{tile.i}.{tile.j}.vrt'
                # set the options for the vrt
                vrt_options = dict(
                    crs = self._crs,
                    transform = tile.to_affine(),
                    width = tile.width(),
                    height = tile.height(),
                    resampling = rio.enums.Resampling.cubic,
                )
                # open the warped vrt
                with rio.vrt.WarpedVRT(src, **vrt_options) as vrt:
                    # save the vrt xml file
                    rio_shutil.copy(vrt, tile_path, driver='VRT')

    def dem_to_vrt_tiles_by_width(self, dem_path: str, width: int = 8_192):
        """
        Given a dem, convert it to tiles as vrt files in the current working directory
        """
        # first get the tiles
        self.dem_to_tiles_by_width(dem_path, width=width)
        tiles: list[Tile] = self._tiles
        # now convert to vrt tiles
        self._to_vrt_tiles(dem_path, tiles)
                    
    def dem_to_vrt_tiles_by_width_with_overlap(self, dem_path: str, width: int = 8_192, overlap: int = 768):
        """
        Given a dem, convert it to tiles with specified overlap as vrt files in the current working directory
        """
        # first get the tiles
        self.dem_to_tiles_by_width_with_overlap(dem_path, width=width, overlap=overlap)
        tiles: list[Tile] = self._tiles
        # now convert to vrt tiles
        self._to_vrt_tiles(dem_path, tiles)


if __name__ == '__main__':
    fire.Fire(VrtTiles)