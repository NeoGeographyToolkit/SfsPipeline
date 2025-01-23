#!/usr/bin/bash
#PBS -j oe
#PBS -k od
#PBS -q long
#PBS -l select=15:ncpus=20:model=ivy,walltime=50:00:00
#PBS -m ae
#PBS -N DGKM_bundle_adjust5
#PBS -o ba5_log
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
export inpref=ba0/run
export out=ba1_init_trans/run
export nodes=nodes.list
export init_trans=mosaic/align-inverse-transform.txt

# Run bundle adjustment

echo $ISISROOT
echo $ISISDATA

bundle_adjust                           	\
  --image-list ${images}	\
  --camera-list ${cameras}		\
  --input-adjustments-prefix ${inpref} \
  --initial-transform ${init_trans} \
  --apply-initial-transform-only \
  -o ${out} 

