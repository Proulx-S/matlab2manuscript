#!/usr/bin/env python3
"""Strip every <text> element from an SVG, for the pixel-diff tests' own use.

2026-08-29: groupAndTagSvg.m's font-size correction (docs/findings.md) is a REAL, INTENTIONAL visual
change -- it fixes a genuine MATLAB font-size rounding artifact, so comparing a baked (uncorrected)
file against a tagged (corrected) one pixel-for-pixel is no longer expected to be 0-diff for TEXT.
The pixel-diff tests only ever meant to guard against a DOM-restructuring/grouping regression (moving
elements around breaking their rendering), which font-size correction is unrelated to -- stripping
text before rasterizing isolates exactly that, leaving text correctness to test_fontsize_correction.m's
own byte-exact numeric checks instead.
"""
import sys
import xml.etree.ElementTree as ET

NS_SVG = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS_SVG)
ET.register_namespace('xlink', 'http://www.w3.org/1999/xlink')

def strip_text(elem):
    for child in list(elem):
        if child.tag.split('}')[-1] == 'text':
            elem.remove(child)
        else:
            strip_text(child)

def main(infile, outfile):
    tree = ET.parse(infile)
    strip_text(tree.getroot())
    tree.write(outfile, xml_declaration=True, encoding='UTF-8')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
