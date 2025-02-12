
# log we are about to start (TODO move below to new script)
echo "launching jobs"
if [[ -z "$DEBUG" ]]; then 
    # Run GNU Parallel with the temp file if not in debug mode
    if [[ $NUM_NODES -gt 1 ]]; then
        parallel --joblog pbs_mapproj_basic_job.log --sshloginfile $PBS_NODEFILE  < "$TMPFILE"
    else
        parallel --joblog pbs_mapproj_basic_job.log  < "$TMPFILE"
    fi
else
    # we are in debug mode so just log out the commands that would
    # have been given the parallel
    cat "$TMPFILE"
fi
# we are now done!
echo "Job finished at $(date)"