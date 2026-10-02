from pathlib import Path

def get_embedded_provenance(dbpath: str | Path)-> str | None:
    """Try to load PROVENANCE Tag from database file, else None"""
    import fiona
    with fiona.open(dbpath) as src:
        tags = src.tags()
        if "PROVENANCE" in tags:
            return tags['PROVENANCE']
        else:
            return None
        

def filename_to_pid(filename:str)-> str:
    p = Path(filename)
    n = p.name
    if '.' in n:
        return n.split('.')[0]
    else:
        return str(n)
