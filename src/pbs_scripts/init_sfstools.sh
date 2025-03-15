#!/bin/zsh
eval "$(micromamba shell hook --shell zsh)"
micromamba activate
micromamba activate sfstools
# this is needed to avoid issues with ASP's parallel command 
export PYTHONHOME=$CONDA_PREFIX
