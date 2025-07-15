#!/usr/bin/env python3
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

def add_vat_to_vrt(vrt_in, attr_txt):
    # parse the VRT
    tree = ET.parse(vrt_in)
    root = tree.getroot()

    # find the first VRTRasterBand
    band = root.find('.//VRTRasterBand')
    if band is None:
        sys.exit("Error: no <VRTRasterBand> found in " + vrt_in)

    # build the GDALRasterAttributeTable element
    vat = ET.Element('GDALRasterAttributeTable')

    # Field 0: Index (integer, usage 0)
    fd0 = ET.SubElement(vat, 'FieldDefn', index='0')
    ET.SubElement(fd0, 'Name').text = 'Index'
    ET.SubElement(fd0, 'Type').text = '0'
    ET.SubElement(fd0, 'Usage').text = '5'

    # Field 1: Raster (string, usage 1)
    fd1 = ET.SubElement(vat, 'FieldDefn', index='1')
    ET.SubElement(fd1, 'Name').text = 'Raster'
    ET.SubElement(fd1, 'Type').text = '2'
    ET.SubElement(fd1, 'Usage').text = '2'

    # add one <Row> per line in the attribute file
    with open(attr_txt, 'r', encoding='utf-8') as f:
        for i, line in enumerate(f):
            val = line.rstrip('\n')
            val = val.split(' ')[0] if ' ' in val else val
            val = Path(val).name
            print(val)
            row = ET.SubElement(vat, 'Row', index=str(i))
            # first column: the integer index
            f1 = ET.SubElement(row, 'F')
            f1.text = str(i)
            # second column: the raster value (string)
            f2 = ET.SubElement(row, 'F')
            f2.text = val

    # find where to insert: just after <ColorInterp>
    insert_pos = None
    for idx, child in enumerate(list(band)):
        if child.tag == 'ColorInterp':
            insert_pos = idx + 1
            break
    if insert_pos is None:
        # fallback: append at end
        insert_pos = len(band)

    band.insert(insert_pos, vat)

    # pretty‑print indent (Python 3.9+)
    try:
        ET.indent(tree, space="  ")
    except AttributeError:
        pass

    # write out with XML declaration
    tree.write(vrt_in, encoding='utf-8', xml_declaration=True)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.vrt> <attributes.txt>")
        sys.exit(1)
    add_vat_to_vrt(sys.argv[1], sys.argv[2])
