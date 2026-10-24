#!/bin/bash
# Activate the ISIS conda environment with whichever frontend is present
# (micromamba, mamba, or conda), then add the ISIS bin dir to PATH.
if command -v micromamba >/dev/null 2>&1; then
  eval "$(micromamba shell hook --shell bash)"
  micromamba activate isis
elif command -v mamba >/dev/null 2>&1; then
  eval "$(mamba shell hook --shell bash)"
  mamba activate isis
elif command -v conda >/dev/null 2>&1; then
  eval "$(conda shell.bash hook)"
  conda activate isis
else
  echo "init_isis.sh: no micromamba, mamba, or conda found on PATH" >&2
  return 1 2>/dev/null || exit 1
fi
export PYTHONHOME=$CONDA_PREFIX
[ -n "$ISISROOT" ] && export PATH=$PATH:$ISISROOT/bin
