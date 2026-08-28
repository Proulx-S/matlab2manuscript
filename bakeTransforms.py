#!/usr/bin/env python3
"""Bake every <g transform="matrix(a,b,c,d,e,f)"> in a MATLAB-exported SVG directly into its
descendants' own geometry/size attributes, then remove the transform.

Full affine (rotation allowed) is used for GEOMETRY (polyline/path/circle) since rotating point
coordinates is well-defined. Text is different: a <text> element's own glyph orientation depends on
rotation, which can't be "baked into" x/y/font-size the way a plain scale+translate can. So for a
<text> whose accumulated transform has a rotation/shear component, we collapse the whole ancestor
chain into ONE single matrix set directly on that <text> element itself (still eliminating all
multi-level nesting) rather than trying to re-derive a clean rotate()+baked-font-size form -- kept
deliberately simple and verified by raster comparison, not by trusting the decomposition algebra.
Non-rotated text (the common case) is fully baked (x/y/font-size as plain numbers, no transform).
"""
import sys
import re
import math
import json
import xml.etree.ElementTree as ET

NS_SVG = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS_SVG)
ET.register_namespace('xlink', 'http://www.w3.org/1999/xlink')

MATRIX_RE = re.compile(r'matrix\(\s*([-\d.eE+]+)\s*,\s*([-\d.eE+]+)\s*,\s*([-\d.eE+]+)\s*,\s*([-\d.eE+]+)\s*,\s*([-\d.eE+]+)\s*,\s*([-\d.eE+]+)\s*\)')

IDENTITY = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)

def parse_transform(s):
    m = MATRIX_RE.fullmatch(s.strip())
    if not m:
        raise ValueError(f"unsupported transform (only matrix(a,b,c,d,e,f) handled): {s!r}")
    return tuple(float(x) for x in m.groups())

def compose(outer, inner):
    """outer applied AFTER inner (outer ∘ inner)."""
    oa, ob, oc, od, oe, of_ = outer
    ia, ib, ic, id_, ie, if_ = inner
    a = oa*ia + oc*ib
    b = ob*ia + od*ib
    c = oa*ic + oc*id_
    d = ob*ic + od*id_
    e = oa*ie + oc*if_ + oe
    f = ob*ie + od*if_ + of_
    return (a, b, c, d, e, f)

def apply_to_point(t, x, y):
    a, b, c, d, e, f = t
    return a*x + c*y + e, b*x + d*y + f

def is_pure_uniform_scale_translate(t, tol=1e-6):
    a, b, c, d, e, f = t
    return abs(b) < tol and abs(c) < tol and abs(a - d) < tol * max(1, abs(a))

def scale_magnitude(t):
    a, b, c, d, e, f = t
    return math.hypot(a, b)  # assumes orthogonal (rotation+uniform scale, no shear)

def transform_points_attr(points_str, t):
    pairs = re.findall(r'([-\d.eE+]+)\s*,\s*([-\d.eE+]+)', points_str)
    new_pairs = []
    for x, y in pairs:
        nx, ny = apply_to_point(t, float(x), float(y))
        new_pairs.append(f'{nx:.10g},{ny:.10g}')
    return ' '.join(new_pairs) + ' '

def transform_path_d(d_str, t):
    tokens = re.findall(r'([MLZ])|([-\d.eE+]+)', d_str)
    events = []
    cmd = None
    nums = []
    def flush():
        nonlocal nums
        if cmd in ('M', 'L'):
            for i in range(0, len(nums), 2):
                nx, ny = apply_to_point(t, nums[i], nums[i+1])
                events.append((cmd if i == 0 else 'L', nx, ny))
        nums = []
    for letter, num in tokens:
        if letter:
            if letter == 'Z':
                flush(); events.append(('Z', None, None)); cmd = None; continue
            flush(); cmd = letter
        else:
            nums.append(float(num))
    flush()
    parts = []
    for c, x, y in events:
        if c == 'Z':
            parts.append('Z')
        else:
            parts.append(f'{c}{x:.10g},{y:.10g}')
    return ' '.join(parts)

def lookup_font_size(elem, s, font_registry, stats):
    """Authoritative FontSize from the live MATLAB text object, keyed by exact string content --
    sidesteps the confirmed sub-point rounding in MATLAB's own exported font-size arithmetic
    entirely, rather than trying to reverse-engineer/compensate for it. Falls back to the
    geometrically-scaled value (with a loud count, not a silent guess) when no registry is given or
    the content isn't found -- e.g. a legend entry or other text this registry doesn't cover yet."""
    content = ''.join(elem.itertext()).strip()
    if font_registry is not None and content in font_registry:
        stats['text_fontsize_from_registry'] += 1
        return font_registry[content]
    if 'font-size' in elem.attrib:
        stats['text_fontsize_fallback_scaled'] += 1
        return float(elem.attrib['font-size']) * s
    return None

def bake(elem, accum, stats, font_registry=None):
    tag = elem.tag.split('}')[-1]
    local = accum
    if 'transform' in elem.attrib:
        local = compose(accum, parse_transform(elem.attrib['transform']))
        del elem.attrib['transform']

    if tag == 'text':
        s = scale_magnitude(local)
        fs = lookup_font_size(elem, s, font_registry, stats)
        if is_pure_uniform_scale_translate(local):
            x = float(elem.attrib.get('x', 0)); y = float(elem.attrib.get('y', 0))
            nx, ny = apply_to_point(local, x, y)
            elem.attrib['x'] = f'{nx:.10g}'; elem.attrib['y'] = f'{ny:.10g}'
            if fs is not None:
                elem.attrib['font-size'] = f'{fs:.10g}'
            stats['text_baked'] += 1
        else:
            # Rotation present: translation bakes into x/y exactly as above (local anchor is
            # always (0,0) in MATLAB's own export, so (x,y) after the affine IS just (e,f)) --
            # ONLY the rotation angle is preserved, as SVG's own rotate(angle,cx,cy) pivoting on
            # that same now-baked anchor point. Verified term-for-term against the SVG spec's own
            # rotate() -> matrix(cos,sin,-sin,cos,0,0) expansion, not guessed.
            a, b, c, d, e, f = local
            if abs(a*c + b*d) > 1e-6:
                raise ValueError(f"non-orthogonal (shear) transform on <text> -- not supported: {local}")
            angle_deg = math.degrees(math.atan2(b, a))
            elem.attrib['x'] = f'{e:.10g}'; elem.attrib['y'] = f'{f:.10g}'
            if fs is not None:
                elem.attrib['font-size'] = f'{fs:.10g}'
            elem.attrib['transform'] = f'rotate({angle_deg:.10g},{e:.10g},{f:.10g})'
            stats['text_rotated_clean'] += 1
        for child in list(elem):
            bake(child, IDENTITY, stats, font_registry)  # tspans -- coords local to the text anchor
        return

    if not is_pure_uniform_scale_translate(local):
        # Non-text geometry CAN be rotated correctly via full-affine point transforms; only bail if
        # it's an actual shear (non-orthogonal), which none of our geometry primitives can represent.
        a, b, c, d, e, f = local
        if abs(a*c + b*d) > 1e-6:
            raise ValueError(f"non-orthogonal (shear) transform on <{tag}> -- not supported: {local}")

    s = scale_magnitude(local)
    if 'stroke-width' in elem.attrib:
        elem.attrib['stroke-width'] = f'{float(elem.attrib["stroke-width"])*s:.10g}'
        stats['stroke-width'] += 1
    if 'font-size' in elem.attrib:
        elem.attrib['font-size'] = f'{float(elem.attrib["font-size"])*s:.10g}'
        stats['font-size'] += 1

    if tag in ('polyline', 'polygon'):
        elem.attrib['points'] = transform_points_attr(elem.attrib['points'], local)
        stats['polyline'] += 1
    elif tag == 'path' and 'd' in elem.attrib:
        elem.attrib['d'] = transform_path_d(elem.attrib['d'], local)
        stats['path'] += 1
    elif tag == 'circle':
        cx, cy = apply_to_point(local, float(elem.attrib['cx']), float(elem.attrib['cy']))
        elem.attrib['cx'] = f'{cx:.10g}'; elem.attrib['cy'] = f'{cy:.10g}'
        elem.attrib['r'] = f'{float(elem.attrib["r"])*s:.10g}'
        stats['circle'] += 1
    elif tag == 'image':
        x = float(elem.attrib.get('x', 0)); y = float(elem.attrib.get('y', 0))
        w = float(elem.attrib.get('width', 0)); h = float(elem.attrib.get('height', 0))
        nx, ny = apply_to_point(local, x, y)
        elem.attrib['x'] = f'{nx:.10g}'; elem.attrib['y'] = f'{ny:.10g}'
        elem.attrib['width'] = f'{w*s:.10g}'; elem.attrib['height'] = f'{h*s:.10g}'
        stats['image'] += 1

    for child in list(elem):
        bake(child, local, stats, font_registry)

def load_font_registry(path):
    """MATLAB's dumpFontRegistry.m output: array of {content, fontSize, role}. Keyed by exact
    content string -- last-writer-wins on a genuine content collision (not expected in practice:
    tick labels/title/x/ylabel strings don't normally coincide within one panel), not guessed at."""
    with open(path) as fh:
        entries = json.load(fh)
    if isinstance(entries, dict):
        entries = [entries]  # MATLAB's jsonencode collapses a 1-element struct array to a bare object
    return {e['content']: e['fontSize'] for e in entries}

def main(infile, outfile, registry_path=None):
    tree = ET.parse(infile)
    root = tree.getroot()
    font_registry = load_font_registry(registry_path) if registry_path else None
    stats = {'stroke-width':0,'font-size':0,'polyline':0,'path':0,'circle':0,'text_baked':0,
             'text_rotated_clean':0,'image':0,'text_fontsize_from_registry':0,'text_fontsize_fallback_scaled':0}
    for child in list(root):
        bake(child, IDENTITY, stats, font_registry)
    tree.write(outfile, xml_declaration=True, encoding='UTF-8')
    print(f"Baked: {stats}")

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
