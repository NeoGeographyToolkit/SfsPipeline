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

### Visual Guide to Processing

Below I will explain all the necessary processing steps I used for Mons Mouton/1414a. There should be no expectation that these steps will work exactly for any other location, and I will leave out some steps as being too trivial to explain. The steps won't be enough to make the products I made reproducible, simply because I was learning how to do it all as I went, and I didn't always take the best notes especially in places where I promoted certain proceedures and one-off bash calls into bash functions. 

This guide also doesn't explain installation or how to update things for your setup or file system paths or username. Read the install for that. So yeah, don't expect to drop the below into a terminal and have it work. It should however get you started.



## 1. Preparing the ROI WKT and LOLA topography to 1mpp



## 2. Running SFS cover to get NAC images 



## 3. Running first map projection to prepare for Bundle Adjustment



## 4. Running first Bundle Adjustment Pass