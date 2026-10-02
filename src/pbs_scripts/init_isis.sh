#!/bin/zsh
eval "$(micromamba shell hook --shell zsh)"
micromamba activate
micromamba activate isis
export PYTHONHOME=$CONDA_PREFIX
export PATH=$PATH:$ISISROOT/bin
