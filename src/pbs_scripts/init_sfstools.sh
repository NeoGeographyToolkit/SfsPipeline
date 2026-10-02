#!/bin/zsh
eval "$(micromamba shell hook --shell zsh)"
micromamba activate
micromamba activate sfstools
export PYTHONHOME=$CONDA_PREFIX
