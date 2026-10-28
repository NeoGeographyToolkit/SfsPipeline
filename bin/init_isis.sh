#!/bin/bash
# Activate the ISIS conda environment, then add the ISIS bin dir to PATH.
if command -v conda >/dev/null 2>&1; then
  eval "$(conda shell.bash hook)"
  conda activate isis
else
  echo "init_isis.sh: conda not found on PATH" >&2
  return 1 2>/dev/null || exit 1
fi
export PYTHONHOME=$CONDA_PREFIX
[ -n "$ISISROOT" ] && export PATH=$PATH:$ISISROOT/bin
