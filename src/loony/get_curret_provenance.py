import sh
import datetime
import os
from pathlib import Path
import json
import socket


if __name__ == '__main__':
    provenance_info = {
        "date": str(datetime.datetime.now()),
        "user": os.getlogin(),
        "hostname": socket.gethostname(),
        "md5sum": sh.md5sum(Path('~/CUMINDEX.TAB').expanduser()).split(' ')[0]
    }
    provenance_info_json = json.dumps(provenance_info, separators=(',', ':'))
    print(provenance_info_json, flush=True)
