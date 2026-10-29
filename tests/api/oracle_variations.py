#!/usr/bin/env python3
"""Print the HarfBuzz results the expects in tests/api/VariationTests.roc
embed: kerning and glyph extents of variable fonts at several locations,
named instances and normalised coordinates, and the former variable defaults at
Regular (now test-only fixtures).

Run with the pinned oracle environment (HarfBuzz 14.6.0 through uharfbuzz
0.56.3, fontTools 4.61.1, see tools/oracle/requirements.txt):

    tools/oracle/.venv/bin/python -I tests/api/oracle_variations.py

Shaping uses default features and UTF-8 byte clusters, as Font.shape does;
extents are hb_font_get_glyph_extents at a scale of units per em, printed
as x_min, y_min, x_max, y_max (or Empty for zero extents).
"""

from pathlib import Path

import uharfbuzz as hb
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[2]


def font_at(path, variations):
    font = hb.Font(hb.Face(Path(path).read_bytes()))
    if variations:
        font.set_variations(variations)
    return font


def shape(path, text, variations):
    font = font_at(path, variations)
    buf = hb.Buffer()
    buf.cluster_level = hb.BufferClusterLevel.MONOTONE_CHARACTERS
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(font, buf, {})
    pos = buf.glyph_positions
    return {
        "glyphs": [i.codepoint for i in buf.glyph_infos],
        "advances": [p.x_advance for p in pos],
        "offsets": [(p.x_offset, p.y_offset) for p in pos],
    }


def extents(path, variations, glyphs):
    font = font_at(path, variations)
    out = []
    for g in glyphs:
        e = font.get_glyph_extents(g)
        if e is None or (e.x_bearing, e.y_bearing, e.width, e.height) == (0, 0, 0, 0):
            out.append("Empty")
        else:
            out.append((e.x_bearing, e.y_bearing + e.height, e.x_bearing + e.width, e.y_bearing))
    return out


def coords(path, variations):
    font = font_at(path, variations)
    return font.get_var_coords_normalized()


def main():
    layout = ROOT / "tests/fonts/variable-layout/kern-var.ttf"
    outlines = ROOT / "tests/fonts/variable/var-outlines.ttf"
    mapped = ROOT / "tests/fonts/variable/var-mapped.ttf"
    locations = [{"wght": 400}, {"wght": 900}, {"wght": 100}, {"wght": 650, "wdth": 125}, {"wght": 400, "wdth": 50}]
    print("kern-var shapes")
    for loc in locations:
        for text in ["abcdefg", "gfedcba", "aceg"]:
            print(" ", loc, repr(text), shape(layout, text, loc))
    print("var-outlines extents of glyphs 0-8")
    glyphs = range(TTFont(outlines)["maxp"].numGlyphs)
    for loc in locations:
        print(" ", loc, extents(outlines, loc, glyphs))
    print("var-mapped coordinates")
    for loc in [{"wght": 400}, {"wght": 700}, {"wght": 100, "wdth": 125}, {"wght": 456.7}]:
        print(" ", loc, coords(mapped, loc))
    face = hb.Face(mapped.read_bytes())
    names = TTFont(mapped)["name"]
    for i, inst in enumerate(face.named_instances):
        print("  instance", i, names.getDebugName(inst.subfamily_name_id), inst.design_coords)
    print("built-in fonts at Regular (wght 400)")
    fonts = {"sans": "Inter-Variable.ttf", "serif": "Merriweather-Variable.ttf", "mono": "FiraCode-Variable.ttf"}
    for name, file in fonts.items():
        path = ROOT / "tests/fonts/default-variable" / file
        tt = TTFont(path)
        family = tt["name"].getBestFamilyName()
        print(" ", name, repr(family), "upem", tt["head"].unitsPerEm)
        for text in ["Hello, world!", "AVATAR office", "Wave To -> 0xFF != 12:30"]:
            r = shape(path, text, {"wght": 400})
            print("   ", repr(text), "width", sum(r["advances"]))
        print("    extents of glyphs 1-4", extents(path, {"wght": 400}, range(1, 5)))
        print("    bold width of 'AVATAR office'", sum(shape(path, "AVATAR office", {"wght": 700})["advances"]))


main()
