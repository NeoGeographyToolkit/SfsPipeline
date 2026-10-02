import sh
import datetime
from pathlib import Path
import json
import socket
import getpass
import fire

def run():
    provenance_info = {
        "date": str(datetime.datetime.now()),
        "user": getpass.getuser(),
        "hostname": socket.gethostname(),
        "md5sum": sh.md5sum(Path('~/LRO_EDR_CUMINDEX/CUMINDEX.TAB').expanduser()).split(' ')[0]
    }
    provenance_info_json = json.dumps(provenance_info, separators=(',', ':'))
    print(provenance_info_json, flush=True)

def main():
    fire.Fire(run)

if __name__ == '__main__':
    main()