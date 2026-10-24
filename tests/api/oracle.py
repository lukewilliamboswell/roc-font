#!/usr/bin/env python3
"""Print the HarfBuzz results the expects in tests/api/ShapeTests.roc and
tests/api/ReadTests.roc embed.

Run with the pinned oracle environment (HarfBuzz 14.6.0 through uharfbuzz
0.56.3, see tools/oracle/requirements.txt):

    tools/oracle/.venv/bin/python -I tests/api/oracle.py

Shaping uses UTF-8 byte clusters and prints glyphs, clusters, x advances,
x offsets and unsafe-to-break flags (bit 0 of HarfBuzz's glyph flags).
"""

from pathlib import Path

import uharfbuzz as hb

ROOT = Path(__file__).resolve().parents[2]


def shape(path, text, script=None, language=None, direction=None, features=None, variations=None):
    face = hb.Face(Path(path).read_bytes())
    font = hb.Font(face)
    if variations:
        font.set_variations(variations)
    buf = hb.Buffer()
    buf.cluster_level = hb.BufferClusterLevel.MONOTONE_CHARACTERS
    buf.add_str(text)
    buf.guess_segment_properties()
    if script:
        buf.script = script
    if language:
        buf.language = language
    if direction:
        buf.direction = direction
    hb.shape(font, buf, features or {})
    infos, positions = buf.glyph_infos, buf.glyph_positions
    return {
        "glyphs": [i.codepoint for i in infos],
        "clusters": [i.cluster for i in infos],
        "advances": [p.x_advance for p in positions],
        "offsets": [p.x_offset for p in positions],
        "flags": [int(i.flags) & 1 for i in infos],
    }


def utf8_clusters(text, result):
    # uharfbuzz adds text as code points; convert clusters to byte offsets.
    offsets, at = [], 0
    for ch in text:
        offsets.append(at)
        at += len(ch.encode("utf-8"))
    result["clusters"] = [offsets[c] for c in result["clusters"]]
    return result


def metrics(path, variations=None):
    face = hb.Face(Path(path).read_bytes())
    font = hb.Font(face)
    if variations:
        font.set_variations(variations)
    tags = hb.OTMetricsTag
    out = {}
    for name in ("X_HEIGHT", "CAP_HEIGHT", "UNDERLINE_OFFSET", "UNDERLINE_SIZE", "STRIKEOUT_OFFSET", "STRIKEOUT_SIZE"):
        out[name.lower()] = font.get_metric_position(getattr(tags, name))
    return out


def advances(path, variations, count):
    face = hb.Face(Path(path).read_bytes())
    font = hb.Font(face)
    font.set_variations(variations)
    return [font.get_glyph_h_advance(g) for g in range(count)]


def main():
    inter = ROOT / "tests/fonts/Inter-Regular-metrics.ttf"
    print("inter shapes")
    for text in ["AVATAR", "Tomorrow", "office ->", "A*B", "x --> y"]:
        print(" ", repr(text), utf8_clusters(text, shape(inter, text, script="Latn")))
    print("inter right to left, script Latn")
    for text in ["AV", "AVATAR", "office", "Tomorrow"]:
        print(" ", repr(text), utf8_clusters(text, shape(inter, text, script="Latn", direction="rtl")))
    print("inter right to left, script Thaa")
    for text in ["AVATAR", "office"]:
        print(" ", repr(text), utf8_clusters(text, shape(inter, text, script="Thaa", direction="rtl")))
    print("inter features")
    print("  liga 0..2 off", utf8_clusters("->->", shape(inter, "->->", script="Latn", features={"calt": [(0, 2, False)], "liga": [(0, 2, False)]})))
    print("  kern off", utf8_clusters("AVA", shape(inter, "AVA", script="Latn", features={"kern": False})))
    print("  kern off 1..", utf8_clusters("AVA", shape(inter, "AVA", script="Latn", features={"kern": [(1, 3, False)]})))
    print("  tnum", utf8_clusters("1234", shape(inter, "1234", script="Latn", features={"tnum": True})))
    print("  greek", utf8_clusters("αβγ", shape(inter, "αβγ", script="Grek")))
    print("  cyrillic", utf8_clusters("Привет", shape(inter, "Привет", script="Cyrl")))
    print("inter metrics", metrics(inter))
    variable = ROOT / "tests/fonts/variable"
    for name in ("var-mapped.ttf", "var-implicit.ttf"):
        path = variable / name
        face = hb.Face(path.read_bytes())
        print(name, "axes", [(a.tag, a.min_value, a.default_value, a.max_value) for a in face.axis_infos], "glyphs", face.glyph_count)
        for loc in ({"wght": 400}, {"wght": 400, "wdth": 100}, {"wght": 700}, {"wght": 100}, {"wght": 1000}, {"wght": 550, "wdth": 87.5}, {"wght": 456.7}):
            print(" ", loc, advances(path, loc, face.glyph_count), metrics(path, loc))


main()
