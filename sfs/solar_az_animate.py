import numpy as np
import geopandas as gp
import matplotlib.pyplot as plt
import matplotlib.animation as animation
from matplotlib.patches import Polygon as MplPolygon
from matplotlib.collections import PatchCollection
import shapely
import fire 





# --- 4. Define helper functions for angular difference and opacity ---

def angular_diff(a, b):
    """
    Compute the smallest difference between two angles (in degrees), accounting for wrap-around.
    """
    diff = abs(a - b) % 360
    return diff if diff <= 180 else 360 - diff


def compute_alpha(polygon_angle, center_angle, visible_range=5, taper_range=2, max_opacity=0.7):
    """
    Determine the opacity for a polygon given its angle and a current center angle.

    Parameters:
      polygon_angle: the polygon's attribute angle (degrees)
      center_angle: the current animation center angle (degrees)
      visible_range: the full angular width (in degrees) where polygons are fully opaque.
                     (For example, 5 means polygons with angle within center ±2.5° are at alpha=1.)
      taper_range: additional angular range on either side over which opacity falls from 1 to 0.

    Returns:
      A float alpha value between 0 and 1.
    """
    # Compute the minimum angular difference
    diff = angular_diff(polygon_angle, center_angle)
    half_visible = visible_range / 2.0

    if diff <= half_visible:
        return max_opacity
    elif diff <= half_visible + taper_range:
        # Linearly taper from 1.0 to 0.0
        return min(0.005, max_opacity * (1 - (diff - half_visible) / taper_range))
    else:
        return 0.005


def to_polygon(geoms):
    for geom in geoms:
        # Handle both Polygon and MultiPolygon geometries:
        patch = MplPolygon(list(geom.exterior.coords), closed=True)
        yield patch



def run(db_path, wkt_roi, az_step_size: float = 10.0):
    # load the db
    df = gp.read_file(db_path)
    # get ROI wkt geometry
    # convert wkt_polygon into a shapely geometry
    polygon = shapely.from_wkt(wkt_roi)
    # construct a query geodataframe 
    df_query = gp.GeoDataFrame(crs=df.crs, geometry=[polygon])
    # --- 2. Prepare the patches and store each polygon's angle ---
    patches = np.array(list(to_polygon(df['geometry'])))   
    angles = df['ROI_SUB_SOLAR_GROUND_AZIMUTH']
    # --- 3. Set up the figure, axis, and collection ---
    fig, ax = plt.subplots(figsize=(8, 6))
    # Create a PatchCollection. You can adjust the color and edge color.
    # We start with alpha=0 for all patches.
    roi = list(to_polygon(df_query['geometry']))
    roi_collection = PatchCollection(roi, facecolor='None', edgecolor='black', zorder=100)
    ax.add_collection(roi_collection)
    # add patches
    collection = PatchCollection(patches, facecolor="blue", edgecolor="None")
    ax.add_collection(collection)
    # Set the axis limits to fit your data. One way is to use geopandas’ total bounds.
    xmin, ymin, xmax, ymax = df.total_bounds
    ax.set_xlim(xmin, xmax)
    ax.set_ylim(ymin, ymax)
    # --- 5. Create the animation update function ---
    def animate(frame):
        """
        For each frame, update the alpha of each polygon based on how close its
        angle is to the current center angle.
        """
        # Use the frame value as the center angle (modulo 360 for safety)
        center_angle = frame % 360
        # If no individual facecolors exist, create an array for each patch.
        facecolors = collection.get_facecolors()
        if len(facecolors) != len(patches):
            # This copies the single default color to an array with one row per patch.
            facecolors = np.tile(collection.get_facecolor()[0], (len(patches), 1))
        new_facecolors = []
        for i, poly_angle in enumerate(angles):
            alpha_val = compute_alpha(poly_angle, center_angle,
                                      visible_range=az_step_size,   # adjust this as needed
                                      taper_range=2)     # adjust taper width as needed
            # Copy the color and update its alpha (index 3)
            color = facecolors[i].copy()
            color[3] = alpha_val
            new_facecolors.append(color)
        #print(center_angle, new_facecolors[0])
        # Update the collection with the new facecolors.
        #print(new_facecolors)
        collection.set_facecolor(new_facecolors)
        # compute number of included/not images
        _np_new_face_alpha = np.array(new_facecolors)[:,3]
        _inc = sum(_np_new_face_alpha > 0.005)
        _not = sum(_np_new_face_alpha <= 0.005)
        # Optionally, update a title to show the current center angle.
        title_obj = ax.title  # Get the current title Text object.
        title_obj.set_text(f"{_inc}/{_not} Highlighting angles near {center_angle:.1f}° ± {az_step_size/2:.1f}°")
    
        # Return the collection (for blitting).
        return (collection, title_obj)
    # --- 6. Create and run the animation ---
    # We use a range of center angles from 0 to 360.
    # Here we generate 180 frames; you can adjust the number of frames and the interval.
    frames = np.linspace(0, 360, 181, endpoint=True)
    ani = animation.FuncAnimation(fig, animate, frames=frames, interval=75, blit=False)
    plt.show()



def main():
    fire.Fire(run)

if __name__ == '__main__':
    main()