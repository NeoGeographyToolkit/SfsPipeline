from pathlib import Path
import fiona

def get_embedded_provenance(dbpath: str | Path)-> str | None:
    """Try to load PROVENANCE Tag from database file, else None"""
    with fiona.open(dbpath) as src:
        tags = src.tags()
        if "PROVENANCE" in tags:
            return tags['PROVENANCE']
        else:
            return None