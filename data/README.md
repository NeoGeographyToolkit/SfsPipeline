# USGS-registered Lunar South Pole LRO NAC image list

`updated_SPole_2023_ImageGCPAdd_root.lis` is the list of Lunar South Pole LRO NAC
images for which the USGS provides improved, well-registered camera geometry. It
holds 18323 NAC root product ids, one per line (for example `M103039846LE`), both
the LROC left (`LE`) and right (`RE`) frames.

These are the south-polar NAC images (acquired July 2009 to August 2013) that USGS
Astrogeology bundle-adjusted and controlled to Lunar Orbiter Laser Altimeter (LOLA)
data, achieving about 0.48 pixel positional RMS. Rather than redistributing the
images, USGS ships the improved pointing (CK) and spacecraft position (SPK) SPICE
kernels that place those observations in the registered frame.

## How it is used

For a south-polar Shape-from-Shading site, intersect this list with the set of NAC
images covering the site (see `bin/query_lro.py`) to find the registered subset,
then build registered CSM cameras by running `spiceinit` with the USGS polar kernels
and regenerating the camera model: `bin/batch_prepare_lro.sh ... --usgs-polar` for a
fresh ingest, or `bin/redo_spiceinit_usgs.sh` to re-register cubs already prepared
with standard kernels (no re-fetch). The registered cameras are then held fixed as
anchors in the first bundle adjustment. The full workflow is described in the Ames
Stereo Pipeline documentation, "Incorporation of well-registered images":
https://stereopipeline.readthedocs.io/en/latest/sfs_usage.html#usgs-reg

## SPICE kernels

The matching USGS polar SPICE kernels (CK `.bc` and SPK `.bsp`, organized by camera
LE/RE and acquisition year) are the `usgs_polar_ck.mk` / `usgs_polar_spk.mk`
meta-kernels referenced by the ingest scripts. They can be downloaded from the USGS
data release (south pole item):
https://www.sciencebase.gov/catalog/item/688a51d7d4be02367c9c1271

## Citation

USGS data release:

Weller, L.A., Richie, J.O., Lee, E.M., Archinal, B.B., Bland, M.T., Bennett, K.,
Edmundson, K., Nefian, A.V., and Laura, J., 2025, Improved camera pointing and
spacecraft ephemeris data for Lunar Reconnaissance Orbiter Camera (LROC) Narrow
Angle Camera (NAC) images of the lunar poles: U.S. Geological Survey data release,
https://doi.org/10.5066/P1OASYRV

The underlying USGS controlled polar mosaic effort is described in:

Lee, E.M., Weller, L.A., Richie, J.O., Redding, B.L., Shinaman, J.R., Edmundson, K.,
Archinal, B.A., Hare, T.M., Fergason, R.L., and the Astrogeology Science Center
programming team, 2012, Controlled Polar Mosaics of the Moon for LMMP by USGS: 43rd
Lunar and Planetary Science Conference, abstract 2507,
https://www.lpi.usra.edu/meetings/lpsc2012/pdf/2507.pdf
