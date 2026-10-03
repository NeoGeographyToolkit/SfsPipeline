#!/bin/zsh
# Activate the SfsPipeline conda environment with whichever frontend is present
# (micromamba, mamba, or conda). ASP bin is NOT added to PATH here.
if command -v micromamba >/dev/null 2>&1; then
  eval "$(micromamba shell hook --shell zsh)"
  micromamba activate SfsPipeline
elif command -v mamba >/dev/null 2>&1; then
  eval "$(mamba shell hook --shell zsh)"
  mamba activate SfsPipeline
elif command -v conda >/dev/null 2>&1; then
  eval "$(conda shell.zsh hook)"
  conda activate SfsPipeline
else
  echo "init_sfs.sh: no micromamba, mamba, or conda found on PATH" >&2
  return 1 2>/dev/null || exit 1
fi
export PYTHONHOME=$CONDA_PREFIX
