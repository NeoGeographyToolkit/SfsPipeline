#!/usr/bin/env python3

# Filter a GCP file to keep only image entries that exist in a given image list.
# Each GCP line: id lat lon height sx sy sz [img px py sx sy] [img px py sx sy] ...
# For each 5-field image group, keep it only if the image is in the set.
# Drop the line if no image groups survive.
# Usage: python filter_gcp.py <input.gcp> <image_list.txt> <output.gcp>

import sys, os

if len(sys.argv) < 4:
    print("Usage: %s <input.gcp> <image_list.txt> <output.gcp>" % sys.argv[0])
    sys.exit(1)

in_gcp = sys.argv[1]
image_list = sys.argv[2]
out_gcp = sys.argv[3]

# Build set of image basenames from the image list
img_set = set()
with open(image_list) as f:
    for line in f:
        line = line.strip()
        if line:
            # Store just the filename without directory
            img_set.add(os.path.basename(line))

print("Loaded %d images from %s" % (len(img_set), image_list))

total = 0
kept = 0
dropped = 0
with open(in_gcp) as fin, open(out_gcp, 'w') as fout:
    for line in fin:
        # Pass through comment lines
        if line.startswith('#'):
            fout.write(line)
            continue

        total += 1
        fields = line.strip().split()
        if len(fields) < 7:
            continue

        # First 7 fields: id lat lon height sx sy sz
        header = fields[:7]

        # Remaining fields in groups of 5: img px py sx sy
        rest = fields[7:]
        if len(rest) % 5 != 0:
            # Malformed line, skip
            dropped += 1
            continue

        # Filter image groups
        new_groups = []
        for i in range(0, len(rest), 5):
            img = rest[i]
            img_base = os.path.basename(img)
            if img_base in img_set:
                new_groups.extend(rest[i:i+5])

        if len(new_groups) == 0:
            dropped += 1
            continue

        kept += 1
        fout.write(' '.join(header + new_groups) + '\n')

print("Total GCP lines: %d" % total)
print("Kept: %d" % kept)
print("Dropped: %d" % dropped)
