#!/bin/zsh
eval "$(micromamba shell hook --shell zsh)"
export ISISDATA=$HOME/nobackup/ISISDATA/
export ISISROOT=$HOME/sw/micromamba/envs/isis
export ASPROOT=$HOME/sw/tools/asp
micromamba activate
# TODO replace this with sfstools and rename this script to init_asp.sh
micromamba activate asap
export PATH=$PATH:$ASPROOT/bin:$ISISROOT/bin
