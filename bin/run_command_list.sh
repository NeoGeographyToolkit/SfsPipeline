#!/bin/bash

# Run an arbitrary command list across the nodes of a PBS job with GNU parallel.
# A worker: qsub it with N nodes and it reads $PBS_NODEFILE and fans the commands
# out (JOBS_PER_NODE each, default 16), with memfree / retries / resume guards.
# De-pbs'd from the original run_command_list.pbs; the user supplies the qsub.
#
# Args:
#   cmdFile   text file, one shell command per line
#   currDir   work dir to cd into, pass as $(pwd)
# Env:
#   JOBS_PER_NODE   parallel jobs per node (default 16)

if [ "$#" -lt 2 ]; then echo "Usage: $0 cmdFile currDir"; exit 1; fi
cmdFile=$1; currDir=$2
cd "$currDir" || exit 1

export ASPROOT=${ASPROOT:-$HOME/projects/BinaryBuilder/StereoPipeline}
export ISISROOT=${ISISROOT:-$HOME/miniconda3/envs/asp_deps}
export ISISDATA=${ISISDATA:-$HOME/projects/isis3data}
export ALESPICEROOT=${ALESPICEROOT:-$ISISDATA}
export PATH=$ASPROOT/bin:$ISISROOT/bin:$PATH
umask 022
ulimit -c 0

jobsPerNode=${JOBS_PER_NODE:-16}
if [[ -z "$PBS_NODEFILE" || ! -f "$PBS_NODEFILE" ]]; then
  NUM_NODES=1
else
  NUM_NODES=$(sort -u "$PBS_NODEFILE" | wc -l)
  nodeFile=$(mktemp "$currDir/parallel_nodes.XXXXXX")
  trap 'rm -f "$nodeFile"' EXIT
  localHost=$(hostname -s)
  echo "${jobsPerNode}/${localHost}" > "$nodeFile"
  sort -u "$PBS_NODEFILE" | grep -v "^$localHost\$" | while read NODE; do
    echo "${jobsPerNode}/${NODE}" >> "$nodeFile"
  done
fi

mkdir -p logs jobs
log=logs/run_command_list_$(basename "$cmdFile").txt
jobLog=$(mktemp jobs/run_command_list_jobs.XXXXXX)
echo "fanning out $cmdFile over $NUM_NODES node(s); log $log"

if [[ "$NUM_NODES" -gt 1 ]]; then
  parallel -u -a "$cmdFile" --workdir "$currDir" --memfree 10G --retries 10 \
    --resume-failed --keep-order --joblog "$jobLog" --sshdelay 0.05         \
    --controlmaster --sshloginfile "$nodeFile" &> "$log"
else
  parallel -u -a "$cmdFile" --workdir "$currDir" --memfree 10G --retries 10 \
    --resume-failed --keep-order --joblog "$jobLog" &> "$log"
fi
mv "$jobLog" "jobs/completed_${jobLog##*/}"
echo "done"
