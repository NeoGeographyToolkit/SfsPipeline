#!/bin/bash
# Activate the SfsPipeline conda environment. ASP bin is NOT added to PATH here.
if command -v conda >/dev/null 2>&1; then
  eval "$(conda shell.bash hook)"
  conda activate SfsPipeline
else
  echo "init_sfs.sh: conda not found on PATH" >&2
  return 1 2>/dev/null || exit 1
fi
export PYTHONHOME=$CONDA_PREFIX
