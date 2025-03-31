#!/usr/bin/env bash

file=$1
sample_size=$2

if [[ ! -f "$file" ]]; then
  echo "Error: File not found: $file"
  exit 1
fi

total_lines=$(wc -l < "$file")

if (( sample_size > total_lines )); then
  echo "Error: Sample size ($sample_size) is larger than number of lines in file ($total_lines)"
  exit 1
fi

shuf "$file" | head -n "$sample_size"
