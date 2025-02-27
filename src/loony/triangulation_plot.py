#!/usr/bin/env python3
import argparse
import math
import os

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
from matplotlib.colors import LightSource
import rasterio
from rasterio.enums import Resampling
# Shade from the northwest, with the sun 45 degrees from horizontal
ls = LightSource(azdeg=315, altdeg=45)

def do_hillshade(img, ve=1.0):
    # todo given that I decimate the data I need to get a sense of what the new resolution is for accurate virtical exaggeration
    return ls.hillshade(img, vert_exag=ve)

def read_and_downsample(filepath, pixel_height:int = 250):
    """
    Reads the first band of a GeoTIFF file and downsamples it so that the largest
    dimension does not exceed desired height
    """
    with rasterio.open(filepath) as ds:
        new_width = int(round(ds.width * pixel_height / ds.height))
        # Use rasterio's built-in resampling.
        data = ds.read(1, masked=True, out_shape=(pixel_height, new_width), resampling=Resampling.bilinear)
    return data

def _plot_on_axes(axes, images, titles, start_index, global_scale, global_min, global_max, cmap, hillshade):
    """
    Helper function to plot images on a list of axes.
    
    Iterates over the axes, plots each image (if available) with a colorbar and title.
    """
    for idx, ax in enumerate(axes):
        img_index = start_index + idx
        if img_index < len(images):
            img = images[img_index]
            if global_scale or hillshade:
                im = ax.imshow(img, cmap=cmap, vmin=global_min, vmax=global_max)
            else:
                im = ax.imshow(img, cmap=cmap)
            ax.set_title(titles[img_index], fontsize=8)
            ax.axis('off')
            plt.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
        else:
            ax.axis('off')

def plot_images(filepaths, global_scale=False, page_mode=False, cmap='viridis',
                interactive_cols=4, cell_size=2.0, max_dim=250, hillshade=False, prefix='page'):
    """
    Reads provided GeoTIFF files and plots them in a grid.
    
    Interactive mode displays the images in a single figure with a fixed number of columns
    (either 4 with 2x2 inch cells or 3 with 2.5x2.5 inch cells, based on the layout flag).
    
    Page mode splits the images across 8.5"x11" pages; here the grid is computed from the 
    cell size so that the same layout is used.
    """
    images = []
    titles = []
    for fp in filepaths:
        data = read_and_downsample(fp, pixel_height=max_dim)
        if hillshade:
            data = do_hillshade(data)
        images.append(data)
        titles.append(os.path.relpath(fp))
    
    # Compute global vmin/vmax if a singular color scale is desired.
    global_min, global_max = None, None
    if hillshade:
        global_min, global_max = 0, 1
    elif global_scale:
        global_min = min(np.nanmin(img) for img in images)
        global_max = max(np.nanmax(img) for img in images)

    if page_mode:
        # Page mode: Use fixed 8.5"x11" pages.
        page_width, page_height = 8.5, 11
        ncols = int(page_width // cell_size)
        nrows = int(page_height // cell_size)
        images_per_page = ncols * nrows
        total_pages = math.ceil(len(images) / images_per_page)
        for page in range(total_pages):
            fig = plt.figure(figsize=(page_width, page_height))
            gs = gridspec.GridSpec(nrows, ncols, figure=fig)
            # Create a flat list of axes from the gridspec.
            axes = [fig.add_subplot(gs[i]) for i in range(nrows * ncols)]
            _plot_on_axes(axes, images, titles, start_index=page * images_per_page,
                          global_scale=global_scale, global_min=global_min, global_max=global_max, cmap=cmap, hillshade=hillshade)
            plt.tight_layout()
            out_file = f'{prefix}_{page+1}.png'
            plt.savefig(out_file)
            plt.close(fig)
            print(f"Saved {out_file}")
    else:
        # Interactive mode.
        ncols = interactive_cols
        nrows = math.ceil(len(images) / ncols)
        fig, axes = plt.subplots(nrows, ncols, figsize=(ncols * cell_size, nrows * cell_size))
        axes = np.atleast_1d(axes).flatten()
        _plot_on_axes(axes, images, titles, start_index=0,
                      global_scale=global_scale, global_min=global_min, global_max=global_max, cmap=cmap, hillshade=hillshade)
        plt.tight_layout()
        plt.show()


def main():
    parser = argparse.ArgumentParser(
        description="Display GeoTIFF files in a grid with matplotlib."
    )
    parser.add_argument("files", nargs="+", help="GeoTIFF files to display.")
    parser.add_argument(
        "--global-scale",
        action="store_true",
        help="Use a singular color scale across all images."
    )
    parser.add_argument(
        "--page-mode",
        action="store_false",
        help="Save output as 8.5x11 inch pages (PNG files) instead of displaying in one window."
    )
    parser.add_argument(
        "--hillshade",
        action="store_true",
        help="If true assume the inputs are DEMs and apply hillshading to them"
    )
    parser.add_argument(
        "--alt-layout",
        action="store_true",
        help="Use alternate layout: 3 columns with 2.5x2.5 inch cells instead of the default 4 columns with 2x2 inch cells."
    )
    parser.add_argument(
        "--cmap",
        type=str,
        default='viridis',
        help='Matplotlib colormap name to se'
    )
    parser.add_argument(
        '--out-prefix',
        type=str,
        default='page',
        help='Output file name prefix to save page(s) as if not interactive'
    )
    parser.add_argument(
        "--max-dim",
        type=int,
        default=250,
        help="Maximum pixel dimension for downsampled images (default: 250)."
    )
    args = parser.parse_args()

    # Determine layout based on the switch flag.
    if args.alt_layout:
        interactive_cols = 3
        cell_size = 2.5
    else:
        interactive_cols = 4
        cell_size = 2.0

    plot_images(
        filepaths=args.files,
        global_scale=args.global_scale,
        page_mode=args.page_mode,
        interactive_cols=interactive_cols,
        cell_size=cell_size,
        cmap='gray' if args.hillshade else args.cmap,
        max_dim=args.max_dim,
        hillshade=args.hillshade,
        prefix=args.out
    )

if __name__ == '__main__':
    main()
