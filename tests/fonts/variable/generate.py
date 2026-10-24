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


def pack_points(points):
    """Packed point numbers; None means all points (a count of 0)."""
    if points is None:
        return b"\x00"
    n = len(points)
    out = struct.pack(">B", n) if n < 128 else struct.pack(">H", 0x8000 | n)
    diffs, last = [], 0
    for p in points:
        diffs.append(p - last)
        last = p
    i = 0
    while i < n:
        words = diffs[i] > 255
        run = [diffs[i]]
        i += 1
        while i < n and len(run) < 128 and (diffs[i] > 255) == words:
            run.append(diffs[i])
            i += 1
        out += struct.pack(">B", (0x80 if words else 0) | (len(run) - 1))
        out += b"".join(struct.pack(">H" if words else ">B", d) for d in run)
    return out


def pack_deltas(values):
    """Packed deltas: runs of zeros, bytes, words and longs (0xC0)."""
    def kind(v):
        if v == 0:
            return 0x80
        if -128 <= v <= 127:
            return 0x00
        if -32768 <= v <= 32767:
            return 0x40
        return 0xC0
    out, i = b"", 0
    while i < len(values):
        k = kind(values[i])
        run = [values[i]]
        i += 1
        while i < len(values) and len(run) < 64 and kind(values[i]) == k:
            run.append(values[i])
            i += 1
        out += struct.pack(">B", k | (len(run) - 1))
        fmt = {0x80: None, 0x00: ">b", 0x40: ">h", 0xC0: ">i"}[k]
        if fmt:
            out += b"".join(struct.pack(fmt, v) for v in run)
    return out


def glyph_variations(axis_count, tuples, shared_points=None):
    """GlyphVariationData. tuples: dicts with `peak` (shared index or a
    float tuple to embed), optional `start`/`end` (intermediate),
    `points` (private point numbers, None for all, absent for the shared
    ones) and `deltas` (x list, y list)."""
    headers, datas = b"", []
    for t in tuples:
        index = 0
        extra = b""
        if isinstance(t["peak"], int):
            index = t["peak"]
        else:
            index |= 0x8000
            extra += b"".join(struct.pack(">h", f2(v)) for v in t["peak"])
        if "start" in t:
            index |= 0x4000
            extra += b"".join(struct.pack(">h", f2(v)) for v in t["start"])
            extra += b"".join(struct.pack(">h", f2(v)) for v in t["end"])
        data = b""
        if "points" in t:
            index |= 0x2000
            data += pack_points(t["points"])
        xs, ys = t["deltas"]
        data += pack_deltas(xs) + pack_deltas(ys)
        datas.append(data)
        headers += struct.pack(">HH", len(data), index) + extra
    serial = pack_points(shared_points) if shared_points is not None else b""
    count = len(tuples) | (0x8000 if shared_points is not None else 0)
    head_size = 4 + len(headers)
    return struct.pack(">HH", count, head_size) + headers + serial + b"".join(datas)


def gvar_table(axis_count, shared_tuples, glyph_datas):
    """A gvar with long offsets."""
    shared = b"".join(struct.pack(">h", f2(v)) for t in shared_tuples for v in t)
    count = len(glyph_datas)
    shared_at = 20 + 4 * (count + 1)
    data_at = shared_at + len(shared)
    offsets, at, blob = [], 0, b""
    for d in glyph_datas:
        offsets.append(at)
        if len(d) % 2:
            d += b"\x00"
        blob += d
        at += len(d)
    offsets.append(at)
    out = struct.pack(">HHHHIHHI", 1, 0, axis_count, len(shared_tuples), shared_at, count, 1, data_at)
    out += b"".join(struct.pack(">I", o) for o in offsets)
    return out + shared + blob


def outlines():
    """Outlines with glyph variations, for package/TableGvarTests.roc:
    simple glyphs (one with a side bearing other than its xMin, so the
    left phantom point shifts it), composite glyphs (an offset, a scale,
    an x and y scale, a 2x2 transform with scaled offsets, USE_MY_METRICS,
    anchor points, and a nested composite), an empty glyph, two glyphs whose
    extents tell double-precision tuple scalars from single, and a gvar with
    shared tuples, embedded peaks, an intermediate region, shared and
    private point numbers (so untouched points are inferred), and zero,
    8-, 16- and 32-bit deltas, some on phantom points."""
    from fontTools.ttLib.tables._g_l_y_f import Glyph, GlyphComponent, USE_MY_METRICS, SCALED_COMPONENT_OFFSET

    names = [".notdef", "box", "tri", "comp", "comp2", "nest", "space", "bar", "bar2"]
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap({0x61 + i: name for i, name in enumerate(names[1:])})

    def contours(paths):
        pen = TTGlyphPen(None)
        for path in paths:
            pen.moveTo(path[0])
            k = 1
            while k < len(path):
                if isinstance(path[k], list):
                    pen.qCurveTo(*path[k])
                else:
                    pen.lineTo(path[k])
                k += 1
            pen.closePath()
        return pen.glyph()

    def component(name, x=0, y=0, transform=None, flags=0, anchor=None):
        c = GlyphComponent()
        c.glyphName = name
        c.flags = flags
        if anchor:
            c.firstPt, c.secondPt = anchor
        else:
            c.x, c.y = x, y
        if transform:
            c.transform = transform
        return c

    def composite(components):
        g = Glyph()
        g.numberOfContours = -1
        g.components = components
        return g

    glyphs = {
        ".notdef": TTGlyphPen(None).glyph(),
        "box": contours([[(100, 0), (500, 0), (500, 700), (100, 700)]]),
        # Two contours, the second with off-curve points.
        "tri": contours([
            [(50, 0), (450, 0), (250, 600)],
            [(120, 650), [(200, 820), (300, 820), (380, 650)], (250, 700)],
        ]),
        "comp": composite([
            component("box", 600, 0, flags=USE_MY_METRICS),
            component("tri", 30, -40, transform=[[0.5, 0], [0, 0.5]]),
            component("tri", 900, 10, transform=[[1.25, 0], [0, 0.75]]),
        ]),
        "comp2": composite([
            component("box", 40, 20, transform=[[0.8, 0.3], [-0.2, 0.9]], flags=SCALED_COMPONENT_OFFSET),
            # tri's point 0 on box's point 2.
            component("tri", anchor=(2, 0)),
        ]),
        "nest": composite([component("comp", -100, 5, transform=[[0.6, 0], [0, 1.1]]), component("box", 1300, 0)]),
        "space": TTGlyphPen(None).glyph(),
        "bar": contours([[(0, 0), (100, 0), (100, 100), (0, 100)]]),
        "bar2": contours([[(0, 0), (100, 0), (100, 100), (0, 100)]]),
    }
    fb.setupGlyf(glyphs)
    # tri's side bearing differs from its xMin (50), so it shifts.
    metrics = {".notdef": (500, 0), "box": (600, 100), "tri": (520, 80), "comp": (1500, 0), "comp2": (900, 0), "nest": (2000, 0), "space": (250, 0), "bar": (200, 0), "bar2": (200, 0)}
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable({"familyName": "RocFontVarOutlines", "styleName": "Regular"})
    fb.setupOS2(sxHeight=500, usWinAscent=800, usWinDescent=200)
    fb.setupPost()
    fb.setupHead(unitsPerEm=1000, created=0, modified=0)
    fb.setupFvar([("wght", 100, 400, 900, "Weight"), ("wdth", 75, 100, 125, "Width")], [dict(location=dict(wght=400, wdth=100), stylename="Regular")])
    fb.font["hmtx"].metrics["comp"] = (1500, 0)

    shared = [(1.0, 0.0), (0.5, 0.0), (0.0, -1.0)]
    datas = [
        b"",
        # box: 4 points and 4 phantom points.
        glyph_variations(2, [
            {"peak": 0, "deltas": ([10, -20, 30, 0, 5, 7, 0, 0], [0, 0, 40, 40, 0, 0, 0, 0])},
            # Only points 0 and 2: 1 and 3 are inferred.
            {"peak": (0.0, -1.0), "points": [0, 2], "deltas": ([300, -333], [-1000, 1200])},
            # An intermediate region with a 32-bit delta.
            {"peak": 1, "start": (0.0, 0.0), "end": (1.0, 0.0), "points": [1, 5], "deltas": ([70000, 9], [-3, 0])},
        ]),
        # tri: 8 points (3 + 5) and 4 phantom points; shared points 0, 3, 5,
        # 7 and the left phantom point (8).
        glyph_variations(2, [
            {"peak": 2, "deltas": ([5, -6, 7, 8, 40], [1, 2, 3, 4, 0])},
            {"peak": 0, "points": None, "deltas": ([1, 2, 3, 4, 5, 6, 7, 8, -30, 0, 0, 0], [8, 7, 6, 5, 4, 3, 2, 1, 0, 0, 0, 0])},
            {"peak": (0.25, 0.5), "start": (0.0, 0.0), "end": (1.0, 1.0), "points": [1, 2, 6], "deltas": ([-50, 25, 129], [33, -33, 400])},
        ], shared_points=[0, 3, 5, 7, 8]),
        # comp: 3 component offsets and 4 phantom points.
        glyph_variations(2, [
            {"peak": 0, "points": None, "deltas": ([-100, 37, 0, 11, 0, 0, 0], [0, 15, -9, 0, 0, 0, 0])},
            {"peak": 2, "points": [1], "deltas": ([-77], [55])},
        ]),
        b"",
        glyph_variations(2, [{"peak": (1.0, 1.0), "points": None, "deltas": ([50, -20, 0, 0, 0, 0], [10, 10, 0, 0, 0, 0])}]),
        # space: only phantom points.
        glyph_variations(2, [{"peak": 0, "points": [0, 1], "deltas": ([12, 80], [0, 0])}]),
        # bar and bar2: a large delta on a two-axis scalar, where HarfBuzz's
        # double-precision scalar and a single-precision one round to
        # different extents (at wght 417.974853515625, wdth
        # 115.83099365234375 for bar; wght 479.65087890625, wdth
        # 106.18438720703125 for bar2).
        glyph_variations(2, [{"peak": (0.6, 0.7), "points": None, "deltas": ([32000] * 4 + [0] * 4, [0] * 8)}]),
        glyph_variations(2, [{"peak": (0.6, 0.7), "start": (0.15, 0.2), "end": (1.0, 1.0), "points": None, "deltas": ([32000] * 4 + [0] * 4, [0] * 8)}]),
    ]
    fb.font["gvar"] = raw_table("gvar", gvar_table(2, shared, datas))
    save(fb, "var-outlines.ttf")


if __name__ == "__main__":
    mapped()
    implicit()
    format1()
    outlines()
    sys.exit(0)
