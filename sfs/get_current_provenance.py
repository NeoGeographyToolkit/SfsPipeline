import datetime
import hashlib
import json
import os
from pathlib import Path
import fire

def compute_md5(path: Path) -> str:
  h = hashlib.md5()
  with open(path, "rb") as f:
    for chunk in iter(lambda: f.read(65536), b""):
      h.update(chunk)
  return h.hexdigest()

def run(tab_path: str = "CUMINDEX.TAB"):
  p = Path(tab_path).expanduser()
  md5_str = compute_md5(p) if p.is_file() else ""
  provenance_info = {
    "date": str(datetime.datetime.now()),
    "md5sum": md5_str
  }
  provenance_info_json = json.dumps(provenance_info, separators=(',', ':'))
  print(provenance_info_json, flush=True)

def main():
  fire.Fire(run)

if __name__ == '__main__':
  main()
