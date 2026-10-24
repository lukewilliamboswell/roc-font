"""Print HarfBuzz's results for the fixtures in this directory, in the shape
the expects in package/LayoutVarTests.roc embed them.

    tools/oracle/.venv/bin/python -I tests/fonts/variable-layout/oracle.py

Pinned: uharfbuzz 0.56.3 (HarfBuzz 14.6.0), scale equal to units per em.

kern-var.ttf: for each location, the normalised coordinates (F2Dot14) and,
for every ordered pair of the glyphs a-g shaped alone (the font has only
the `kern` feature), the change to the first glyph's x advance, its x and y
offset, and the same for the second glyph. Each location is shaped twice
and the second pass printed: HarfBuzz quantises region scalars in a cache
filled by the first evaluation, which is the steady state roc-font models.

feature-var.ttf: for each location, the coordinates and which
FeatureVariations record applied, read off the glyphs "ab" shapes to (-1
for none).
"""
import os

import uharfbuzz as hb

HERE = os.path.dirname(os.path.abspath(__file__))

KERN_LOCATIONS = [
    {}, {"wght": 100}, {"wght": 250}, {"wght": 400}, {"wght": 500}, {"wght": 525}, {"wght": 650},
    {"wght": 700}, {"wght": 900}, {"wdth": 50}, {"wdth": 150}, {"wght": 650, "wdth": 125},
    {"wght": 900, "wdth": 150}, {"wght": 456.7, "wdth": 110.25}, {"wght": 812, "wdth": 81},
    {"wght": 150, "wdth": 60},
]

FEATURE_WGHT = [100, 150, 175, 212.5, 250, 300, 362.5, 370, 400, 437.5, 450, 650, 700, 900]
FEATURE_WDTH = [50, 55, 56.25, 75, 80, 100, 137.5, 150]

LETTERS = "abcdefg"


def font_of(name):
    face = hb.Face(hb.Blob.from_file_path(os.path.join(HERE, name)))
    font = hb.Font(face)
    font.scale = (face.upem, face.upem)
    return font


def shape(font, text):
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(font, buf, {"kern": True})
    return buf


def coords(font):
    return [round(c * 16384) for c in font.get_var_coords_normalized()]


def kern():
    font = font_of("kern-var.ttf")
    print("# kern-var.ttf")
    for loc in KERN_LOCATIONS:
        font.set_variations(loc)
        rows = None
        for _ in range(2):
            rows = []
            for x in LETTERS:
                for y in LETTERS:
                    buf = shape(font, x + y)
                    g, p = buf.glyph_infos, buf.glyph_positions
                    rows.append([
                        p[0].x_advance - font.get_glyph_h_advance(g[0].codepoint), p[0].x_offset, p[0].y_offset,
                        p[1].x_advance - font.get_glyph_h_advance(g[1].codepoint), p[1].x_offset, p[1].y_offset,
                    ])
        print(f"{loc} coords={coords(font)}")
        for k in range(6):
            print(f"  column {k}: [{', '.join(str(r[k]) for r in rows)}]")


def feature():
    font = font_of("feature-var.ttf")
    names = {font.get_glyph_name(i): i for i in range(7)}
    outcome = {
        ("a.alt1", "b.alt"): 0, ("a.alt1", "b"): 1, ("a", "b.alt"): 2,
        ("a.alt2", "b"): 3, ("a", "b.alt2"): 4, ("a", "b"): -1,
    }
    print("# feature-var.ttf")
    out = []
    for wght in FEATURE_WGHT:
        for wdth in FEATURE_WDTH:
            font.set_variations({"wght": wght, "wdth": wdth})
            buf = shape(font, "ab")
            glyphs = tuple(font.get_glyph_name(i.codepoint) for i in buf.glyph_infos)
            c = coords(font)
            out.append(f"({wght}, {wdth}, {c[0]}, {c[1]}, {outcome[glyphs]})")
    print("[" + ", ".join(out) + "]")


kern()
feature()
