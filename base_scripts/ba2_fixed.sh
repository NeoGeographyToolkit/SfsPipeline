#!/usr/bin/bash
#PBS -j oe
#PBS -k od
#PBS -q long
#PBS -l select=15:ncpus=20:model=ivy,walltime=50:00:00
#PBS -m ae
#PBS -N PNS_ba2
#PBS -o PNS_ba2.log
#PBS -r y
#PBS -S /bin/bash
#PBS -W group_list=e2305

# Run with qsub <this file>

#echo Working directory is $PBS_O_WORKDIR
#cd $PBS_O_WORKDIR

#echo machine is $(uname -a)
#echo machine file is $PBS_NODEFILE
#echo machines are $(cat $PBS_NODEFILE)
#echo

export ASP=~/Work/ASP/
export ALE=~/Work/mambaforge/envs/asp
export ISISROOT=/Work/anaconda3/envs/isis
export ISISDATA=/Work/ISIS3Data

export images=ba2_cubs_sorted_culled_2.list
export cameras=ba2_cams_sorted_culled_2.list
export ref_dem=Site07_final_adj_1mpp_surf.tif
export fixed_cams=ba1_cubs_sorted_culled_fixed.list
export out=ba2_fixed/run
export inpref=ba1_init_trans/run
export nodes=nodes.list

# Run bundle adjustment

echo $ISISROOT
echo $ISISDATA

parallel_bundle_adjust                           	\
  --image-list ${images}	\
  --camera-list ${cameras}		\
  --input-adjustments-prefix ${inpref} \
  --fixed-image-list ${fixed} \
  --mapproj-dem ${ref_dem}                       \
  --heights-from-dem ${ref_dem} \
  --nodata-value 0.01                          \
  --ip-per-image 20000                          \
  --num-random-passes 1 \
  --overlap-limit 50                             \
  --num-iterations 75                           \
  --num-passes 2                                 \
  --min-matches 10                                \
  --max-pairwise-matches 1000                    \
  --match-first-to-last                          \
  --camera-weight 0                              \
  --robust-threshold 0.5                           \
  --tri-weight 0.1                             \
  --tri-robust-threshold 0.25                    \
  --min-triangulation-angle 0.1                  \
  --remove-outliers-params "75.0 3.0 100 100"    \
  --save-intermediate-cameras                    \
  --nodes-list ${nodes}		         \
  -o ${out} 


