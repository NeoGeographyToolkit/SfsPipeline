#!/bin/bash
# Activate the SfsPipeline conda environment, then add the ASP and ISIS bin
# dirs to PATH.
if command -v conda >/dev/null 2>&1; then
  eval "$(conda shell.bash hook)"
  conda activate SfsPipeline
else
  echo "init_asp.sh: conda not found on PATH" >&2
  return 1 2>/dev/null || exit 1
fi
[ -n "$ASPROOT" ] && export PATH=$PATH:$ASPROOT/bin
[ -n "$ISISROOT" ] && export PATH=$PATH:$ISISROOT/bin
