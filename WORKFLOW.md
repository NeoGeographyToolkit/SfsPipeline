# Workflow 

Dr. Andrew M. Annex
10/10/2025


### 1. Overview

The key to successful SFS processing is successfully bundle adjusting the images such that there is no ghosting, and that you've gathered as many images as humanly possible.

**Nothing Else Matters**

If you have any ghosting, it is very difficult to eliminate it unless it is exceedingly obvious which image is responsible. If multiple images contribute to ghosting in the same area, you don't know which to trust and you end up in a bad place to be.

For any SFS processing, all requisit time and effort and compute resources should be done to ensure you have as perfect a set of images as possible. Don't ever assume it is "good enough" or think you can save yourself later. 

If possible ensure your bundle adjustment is just below the computational limits for the ceres solver. Anything less is a waste of effort. When in doubt, always increase the number of interest points, the number of images you allow each image to be compared to, the number of points used from each pair. 

The reason this is good is that the compute required for this is not going to be greater than the shape from shading processing, and if you leave any performance on the table you will regret it later.


#### High Level Workflow Description

The workflow I developed is highly similar to the large scale sfs tutorial developed for SFS of lunar terrain from the ASP docs. 
However, because of the lack of stereo coverage, I skipped the stereo processing section in favor of doing a better/more complete job of bundle adjustment using more images and more interest point matches with smithed spice kernels.

Secondly and more critically perhaps, a "preview" pass of SFS is run using fewer images to produce a preliminary DEM that can be hill shade aligned to the LOLA. This may only work if the ROI is large enough to have meaningful texture to match to LOLA products. 

At that point the cameras can be translated in the same manner as the stereo-alignment method, re-bundle adjusted to the terrain, and a final sfs product can be computed using a higher prior dem weight constraint.


#### Overview of how to perform the workflow

The workflow for SFS is not a single script that runs due to the amount of flexibility needed to deal with issues as they arrise. 
So there is no "one" workflow or single command to run. Instead the workflow is a series of steps that must be manually executed
in the terminal, mostly on the NAS super computer system using the PFE nodes to run small scripts and processing steps and launch larger jobs that do the actual work. The main readme explains some of the particulars for how these scripts work, while this document is more focused on their actual use within a workflow. 


### 2.Guide to Processing

Below I will explain all the necessary processing steps I used for Mons Mouton/1414a. There should be no expectation that these steps will work exactly for any other location, and I will leave out some steps as being too trivial to explain. The steps won't be enough to make the products I made reproducible, simply because I was learning how to do it all as I went, and I didn't always take the best notes especially in places where I promoted certain proceedures and one-off bash calls into bash functions. 

This guide also doesn't explain installation or how to update things for your setup or file system paths or username. Read the install for that. So yeah, don't expect to drop the below into a terminal and have it work. It should however get you started.




## 1. Running SFS cover to get NAC images 

```bash
sfs-cover --db_path /tmp/lroc_cumulative_south_polar.parquet -p "POLYGON((...))" -t roi --gpkg ./roi.gpkg
```

## 2. Running first map projection to prepare for Bundle Adjustment

```bash
export SUBMIT=true
export DEM="/path/to/dem.tif"
export INPUT_DIR="/path/to/cub/file/folder/"
mapproj_noba.pbs
```



## 3. Running first Bundle Adjustment Pass



## 4. Map projection of first BA Pass


## 5. 2nd Pass BA using Terrain Refinement


## 6. First pass SFS for hill shade alignment

## 7. Hillshade alignment and new Bundle Adjust


## 8. Second Pass SFS for final products


