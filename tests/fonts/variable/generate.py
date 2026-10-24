"""Generate the tiny variable-font fixtures in this directory.

Run with the pinned oracle environment (fontTools 4.61.1):

    tools/oracle/.venv/bin/python -I tests/fonts/variable/generate.py

The output is byte-for-byte reproducible. Each font has a handful of empty
glyphs; what matters are its variation tables. `HVAR` and `MVAR` are
assembled by hand, so the fixtures cover encodings fontTools' builders do
not choose on their own: 32-bit (LONG_WORDS) and 8-bit deltas, an
intermediate region, a two-axis region, an advance map shorter than the
glyph list, a format 1 map with 1-byte entries, and the implicit glyph-id
mapping.
"""
import os
import struct
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import newTable
from fontTools.ttLib.tables.DefaultTable import DefaultTable

HERE = os.path.dirname(os.path.abspath(__file__))
F2 = 16384  # F2Dot14 one


def f2(x):
    return round(x * F2)


def ivs(axis_count, regions, datas):
    """An ItemVariationStore. regions: list of [(start, peak, end)] per axis
    (floats); datas: list of (region_indexes, word_count, long_words, rows)."""
    region_list = struct.pack(">HH", axis_count, len(regions))
    for region in regions:
        for start, peak, end in region:
            region_list += struct.pack(">hhh", f2(start), f2(peak), f2(end))
    data_blobs = []
    for indexes, words, long_words, rows in datas:
        blob = struct.pack(">HHH", len(rows), words | (0x8000 if long_words else 0), len(indexes))
        blob += b"".join(struct.pack(">H", i) for i in indexes)
        wide, narrow = (">i", ">h") if long_words else (">h", ">b")
        for row in rows:
            assert len(row) == len(indexes)
            for k, d in enumerate(row):
                blob += struct.pack(wide if k < words else narrow, d)
        data_blobs.append(blob)
    header_size = 8 + 4 * len(datas)
    offset = header_size + len(region_list)
    offsets = []
    for blob in data_blobs:
        offsets.append(offset)
        offset += len(blob)
    out = struct.pack(">HIH", 1, header_size, len(datas))
    out += b"".join(struct.pack(">I", o) for o in offsets)
    return out + region_list + b"".join(data_blobs)


def delta_map(fmt, entry_size, inner_bits, entries):
    """A DeltaSetIndexMap of (outer, inner) entries."""
    entry_format = ((entry_size - 1) << 4) | (inner_bits - 1)
    if fmt == 0:
        out = struct.pack(">BBH", 0, entry_format, len(entries))
    else:
        out = struct.pack(">BBI", 1, entry_format, len(entries))
    for outer, inner in entries:
        assert inner < (1 << inner_bits)
        u = (outer << inner_bits) | inner
        out += u.to_bytes(entry_size, "big")
    return out


def hvar(store, advance_map):
    head_size = 20
    store_at = head_size
    map_at = store_at + len(store) if advance_map is not None else 0
    out = struct.pack(">HHIIII", 1, 0, store_at, map_at, 0, 0)
    return out + store + (advance_map or b"")


def mvar(store, records):
    records = sorted(records)
    head_size = 12 + 8 * len(records)
    out = struct.pack(">HHHHHH", 1, 0, 0, 8, len(records), head_size if records else 0)
    for tag, outer, inner in records:
        out += tag.encode("ascii") + struct.pack(">HH", outer, inner)
    return out + (store if records else b"")


def raw_table(tag, data):
    table = DefaultTable(tag)
    table.data = data
    return table


def base_font(glyph_names, advances, axes, instances):
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(glyph_names)
    fb.setupCharacterMap({0x61 + i: name for i, name in enumerate(glyph_names[1:])})
    pen = TTGlyphPen(None)
    empty = pen.glyph()
    fb.setupGlyf({name: empty for name in glyph_names})
    fb.setupHorizontalMetrics({name: (advances[i], 0) for i, name in enumerate(glyph_names)})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable({"familyName": "RocFontVarTest", "styleName": "Regular"})
    fb.setupOS2(sxHeight=500, usWinAscent=800, usWinDescent=200)
    fb.setupPost()
    fb.setupHead(unitsPerEm=1000, created=0, modified=0)
    fb.setupFvar(axes, instances)
    return fb


def save(fb, name):
    path = os.path.join(HERE, name)
    fb.font.save(path)
    # FontBuilder writes deterministic bytes once head dates are fixed.
    print(name, os.path.getsize(path))


def mapped():
    """Two axes, a bent wght axis, five regions, two data subtables (one
    LONG_WORDS), an advance map shorter than the glyph list, and MVAR."""
    names = [".notdef", "a", "b", "c", "d", "e", "f"]
    advances = [500, 600, 610, 620, 630, 640, 650]
    axes = [
        ("wght", 100, 400, 900, "Weight"),
        ("wdth", 75, 100, 125, "Width"),
    ]
    instances = [
        dict(location=dict(wght=100, wdth=100), stylename="Thin"),
        dict(location=dict(wght=400, wdth=100), stylename="Regular", postscriptfontname="RocFontVarTest-Regular"),
        dict(location=dict(wght=700, wdth=75), stylename="Bold Condensed"),
    ]
    fb = base_font(names, advances, axes, instances)
    fb.font["avar"] = newTable("avar")
    fb.font["avar"].segments = {
        "wght": {-1.0: -1.0, -0.5: -0.625, 0.0: 0.0, 0.3: 0.45, 1.0: 1.0},
        "wdth": {-1.0: -1.0, 0.0: 0.0, 1.0: 1.0},
    }
    regions = [
        [(0, 1, 1), (0, 0, 0)],          # wght max
        [(-1, -1, 0), (0, 0, 0)],        # wght min
        [(0, 0, 0), (0, 1, 1)],          # wdth max
        [(0, 0.5, 1), (0, 0, 0)],        # wght intermediate
        [(0, 1, 1), (-1, -1, 0)],        # wght max x wdth min
    ]
    store = ivs(2, regions, [
        # region columns 0, 1, 2, 3: one 16-bit column, three 8-bit.
        ([0, 1, 2, 3], 1, False, [
            [0, 0, 0, 0],
            [300, -100, 25, -7],
            [-333, 101, -128, 127],
            [1, -1, 3, 5],
        ]),
        # LONG_WORDS: one 32-bit column, two 16-bit.
        ([4, 0, 3], 1, True, [
            [40000, 15, -3],
            [-70001, 32767, -32768],
        ]),
    ])
    # Seven glyphs, six entries: glyph 6 takes the last entry.
    advance_map = delta_map(0, 2, 2, [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (0, 3)])
    fb.font["HVAR"] = raw_table("HVAR", hvar(store, advance_map))
    mstore = ivs(2, regions, [([0, 2, 4], 0, False, [[20, -10, 7], [-15, 3, 0]])])
    fb.font["MVAR"] = raw_table("MVAR", mvar(mstore, [("xhgt", 0, 0), ("undo", 0, 1)]))
    save(fb, "var-mapped.ttf")


def implicit():
    """One axis whose default is its minimum (as Merriweather and Fira
    Code), no avar, and the implicit glyph-id advance mapping."""
    names = [".notdef", "a", "b", "c"]
    advances = [500, 600, 700, 800]
    axes = [("wght", 300, 300, 700, "Weight")]
    instances = [dict(location=dict(wght=300), stylename="Light"), dict(location=dict(wght=700), stylename="Bold")]
    fb = base_font(names, advances, axes, instances)
    regions = [[(0, 1, 1)], [(0, 0.25, 1)]]
    store = ivs(1, regions, [([0, 1], 0, False, [[0, 0], [100, -9], [-50, 3], [7, 11]])])
    fb.font["HVAR"] = raw_table("HVAR", hvar(store, None))
    save(fb, "var-implicit.ttf")


def format1():
    """A format 1 advance map with 1-byte entries and 3 inner bits, and a
    data subtable with no regions (as Fira Code's)."""
    names = [".notdef", "a", "b", "c", "d"]
    advances = [500, 510, 520, 530, 540]
    axes = [("wght", 200, 400, 800, "Weight"), ("opsz", 8, 12, 48, "Optical size")]
    instances = [dict(location=dict(wght=400, opsz=12), stylename="Regular")]
    fb = base_font(names, advances, axes, instances)
    regions = [[(0, 1, 1), (0, 0, 0)], [(0, 0, 0), (0, 1, 1)], [(0, 1, 1), (0, 1, 1)]]
    store = ivs(2, regions, [
        ([], 0, False, [[], []]),
        ([0, 1, 2], 3, False, [[1000, -500, 77], [-1, 1, -1], [12345, -12345, 3]]),
    ])
    advance_map = delta_map(1, 1, 3, [(0, 0), (1, 0), (1, 1), (0, 1), (1, 2)])
    fb.font["HVAR"] = raw_table("HVAR", hvar(store, advance_map))
    save(fb, "var-format1.ttf")


if __name__ == "__main__":
    mapped()
    implicit()
    format1()
    sys.exit(0)
