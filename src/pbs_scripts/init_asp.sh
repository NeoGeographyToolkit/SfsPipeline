#!/bin/zsh
eval "$(micromamba shell hook --shell zsh)"
micromamba activate
micromamba activate SfsPipeline
export PATH=$PATH:$ASPROOT/bin:$ISISROOT/bin
