#!/bin/zsh
eval "$(micromamba shell hook --shell zsh)"
micromamba activate
micromamba activate SfsPipeline
export PYTHONHOME=$CONDA_PREFIX
