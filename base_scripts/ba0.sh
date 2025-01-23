#!/usr/bin/bash
#PBS -j oe
#PBS -k od
#PBS -q long
#PBS -l select=15:ncpus=20:model=ivy,walltime=50:00:00
#PBS -m ae
#PBS -N ba0
#PBS -o ba0_log
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

export images=cubs_sorted_culled_1.list
export cameras=cams_sorted_culled_1.list
export projected=proj_sorted_culled_1.list
export dem=Site07_final_adj_1mpp_surf.tif
export out=ba0/run
export nodes=nodes.list

# Run bundle adjustment

echo $ISISROOT
echo $ISISDATA

parallel_bundle_adjust                           	\
  --image-list ${images}	\
  --camera-list ${cameras}		\
  --mapproj-dem ${dem}                       \
  --nodata-value 0.001                          \
  --ip-per-image 20000                          \
  --overlap-limit 50                             \
  --num-iterations 50                           \
  --matches-per-tile 100 \
  --num-passes 2                                 \
  --min-matches 10                                \
  --max-pairwise-matches 1000                    \
  --camera-weight 0                              \
  --robust-threshold 0.5                           \
  --tri-weight 0.1                             \
  --tri-robust-threshold 0.25                    \
  --min-triangulation-angle 0.1                  \
  --remove-outliers-params "75.0 3.0 100 100"    \
  --save-intermediate-cameras                    \
  --match-first-to-last                          \
  --nodes-list ${nodes}		         \
  -o ${out} 


