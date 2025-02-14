# TODO how to resume processing of parallel if I get the time bounds wrong?
# https://www.gnu.org/software/parallel/parallel.html#options either --resume --resume-failed, likely the latter
# log we are about to start (TODO move below to new script)
echo "launching jobs at $(date)"
if [[ -z "$DEBUG" ]]; then 
    # Run GNU Parallel with the temp file if not in debug mode
    if [[ $NUM_NODES -gt 1 ]]; then
        ~/sw/tools/asp/bin/parallel --controlmaster -u -j 1 --sshdelay 0.5 --sshloginfile $PBS_NODEFILE --eta --progress --joblog ~/${1}_job.log  < "$TMPFILE"
    else
        ~/sw/tools/asp/bin/parallel -u -j 2 --eta --progress --line-buffer --joblog ~/${1}_job.log  < "$TMPFILE"
    fi
    # The jobs have actually completed 
    echo "Parallel has finished with all jobs at $(date)"
    # move the joblog file to preserve its state and to avoid re-running it
    mv "$HOME/$(1}_job.log" "$HOME/completed_$(date +"%Y-%m-%d_%H-%M-%S")_${1}_job.log"
else
    # we are in debug mode so just log out the commands that would
    # have been given the parallel
    cat "$TMPFILE"
fi
# we are now done!
echo "Job finished at $(date)"