"""Generate the tiny variable-layout fixtures in this directory.

Run with the pinned oracle environment (fontTools 4.61.1):

    tools/oracle/.venv/bin/python -I tests/fonts/variable-layout/generate.py

The output is byte-for-byte reproducible. Each font has a handful of empty
glyphs; what matters are its layout tables:

- `kern-var.ttf`: a `GDEF` 1.3 item variation store (five regions, among
  them an intermediate and a two-axis one; 8-, 16- and 32-bit deltas) and a
  `GPOS` `kern` feature with three lookups: pair adjustment format 1 with
  `VariationIndex`, `NO_VARIATION`, hinting and null devices on the x
  advance; format 2 with placement and advance devices on the first glyph
  and placement devices on the second; format 1 through an extension with
  every value and device on the second glyph; and format 2 without devices.
- `feature-var.ttf`: a `GSUB` 1.1 with `FeatureVariations`: five records
  whose condition sets use axis ranges (format 1), a value from the `GDEF`
  store (format 2), and, or and not (formats 3 to 5), substituting the
  lookups of `calt` and `liga`.
"""
import os

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import newTable
from fontTools.ttLib.tables import otTables as ot
from fontTools.ttLib.tables.otBase import ValueRecord
from fontTools.varLib.builder import buildVarRegionList, buildVarData, buildVarStore

HERE = os.path.dirname(os.path.abspath(__file__))
AXES = [("wght", 100, 400, 900, "Weight"), ("wdth", 50, 100, 150, "Width")]
TAGS = ["wght", "wdth"]


def base_font(glyph_names, advances, cmap):
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(glyph_names)
    fb.setupCharacterMap(cmap)
    empty = TTGlyphPen(None).glyph()
    fb.setupGlyf({name: empty for name in glyph_names})
    fb.setupHorizontalMetrics({name: (advances[i], 0) for i, name in enumerate(glyph_names)})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable({"familyName": "RocFontVarLayoutTest", "styleName": "Regular"})
    fb.setupOS2(sxHeight=500, usWinAscent=800, usWinDescent=200)
    fb.setupPost()
    fb.setupHead(unitsPerEm=1000, created=0, modified=0)
    fb.setupFvar(AXES, [])
    return fb


def save(fb, name):
    path = os.path.join(HERE, name)
    fb.font.save(path)
    print(name, os.path.getsize(path))


def store(regions, datas):
    """regions: list of {tag: (start, peak, end)}; datas: (region_indexes, rows)."""
    region_list = buildVarRegionList(regions, TAGS)
    return buildVarStore(region_list, [buildVarData(ix, rows, optimize=False) for ix, rows in datas])


def gdef(var_store):
    table = ot.GDEF()
    table.Version = 0x00010003
    table.GlyphClassDef = None
    table.AttachList = None
    table.LigCaretList = None
    table.MarkAttachClassDef = None
    table.MarkGlyphSetsDef = None
    table.VarStore = var_store
    t = newTable("GDEF")
    t.table = table
    return t


def var_device(outer, inner):
    d = ot.Device()
    d.StartSize, d.EndSize, d.DeltaFormat = outer, inner, 0x8000
    return d


def hinting_device():
    d = ot.Device()
    d.StartSize, d.EndSize, d.DeltaFormat = 9, 12, 1
    d.DeltaValue = [1, -1, 0, 1]
    return d


FIELDS = [(0x01, "XPlacement"), (0x02, "YPlacement"), (0x04, "XAdvance"), (0x08, "YAdvance"),
          (0x10, "XPlaDevice"), (0x20, "YPlaDevice"), (0x40, "XAdvDevice"), (0x80, "YAdvDevice")]


def value(fmt, **fields):
    v = ValueRecord()
    for bit, name in FIELDS:
        if fmt & bit:
            setattr(v, name, fields.get(name, None if bit >= 0x10 else 0))
    return v


def coverage(glyphs):
    c = ot.Coverage()
    c.glyphs = glyphs
    return c


def class_def(classes):
    c = ot.ClassDef()
    c.classDefs = classes
    return c


def pair_format1(fmt1, fmt2, pairs, order):
    """pairs: {first: [(second, value1, value2)]}"""
    st = ot.PairPos()
    st.Format = 1
    firsts = sorted(pairs, key=order.index)
    st.Coverage = coverage(firsts)
    st.ValueFormat1, st.ValueFormat2 = fmt1, fmt2
    st.PairSet = []
    for first in firsts:
        ps = ot.PairSet()
        ps.PairValueRecord = []
        for second, v1, v2 in sorted(pairs[first], key=lambda p: order.index(p[0])):
            r = ot.PairValueRecord()
            r.SecondGlyph = second
            if fmt1:
                r.Value1 = v1
            if fmt2:
                r.Value2 = v2
            ps.PairValueRecord.append(r)
        ps.PairValueCount = len(ps.PairValueRecord)
        st.PairSet.append(ps)
    st.PairSetCount = len(st.PairSet)
    return st


def pair_format2(fmt1, fmt2, covered, classes1, classes2, grid):
    st = ot.PairPos()
    st.Format = 2
    st.Coverage = coverage(covered)
    st.ValueFormat1, st.ValueFormat2 = fmt1, fmt2
    st.ClassDef1 = class_def(classes1)
    st.ClassDef2 = class_def(classes2)
    st.Class1Count = len(grid)
    st.Class2Count = len(grid[0])
    st.Class1Record = []
    for row in grid:
        r1 = ot.Class1Record()
        r1.Class2Record = []
        for v1, v2 in row:
            r2 = ot.Class2Record()
            if fmt1:
                r2.Value1 = v1
            if fmt2:
                r2.Value2 = v2
            r1.Class2Record.append(r2)
        st.Class1Record.append(r1)
    return st


def lookup(kind, subtables):
    lk = ot.Lookup()
    lk.LookupType = kind
    lk.LookupFlag = 0
    lk.SubTable = subtables
    lk.SubTableCount = len(subtables)
    return lk


def extension(pos):
    ext = ot.ExtensionPos()
    ext.Format = 1
    ext.ExtensionLookupType = pos.LookupType = 2
    ext.ExtSubTable = pos
    return ext


def layout_table(cls, features, lookups):
    """features: [(tag, [lookup indexes])]; one DFLT script using all of them."""
    table = cls()
    table.Version = 0x00010000
    langsys = ot.LangSys()
    langsys.LookupOrder = None
    langsys.ReqFeatureIndex = 0xFFFF
    langsys.FeatureIndex = list(range(len(features)))
    langsys.FeatureCount = len(features)
    script = ot.Script()
    script.DefaultLangSys = langsys
    script.LangSysRecord = []
    script.LangSysCount = 0
    record = ot.ScriptRecord()
    record.ScriptTag = "DFLT"
    record.Script = script
    table.ScriptList = ot.ScriptList()
    table.ScriptList.ScriptRecord = [record]
    table.ScriptList.ScriptCount = 1
    table.FeatureList = ot.FeatureList()
    table.FeatureList.FeatureRecord = []
    for tag, indexes in features:
        fr = ot.FeatureRecord()
        fr.FeatureTag = tag
        fr.Feature = feature(indexes)
        table.FeatureList.FeatureRecord.append(fr)
    table.FeatureList.FeatureCount = len(features)
    table.LookupList = ot.LookupList()
    table.LookupList.Lookup = lookups
    table.LookupList.LookupCount = len(lookups)
    return table


def feature(indexes):
    f = ot.Feature()
    f.FeatureParams = None
    f.LookupListIndex = indexes
    f.LookupCount = len(indexes)
    return f


def kern_var():
    names = [".notdef", "a", "b", "c", "d", "e", "f", "g"]
    fb = base_font(names, [500, 600, 610, 620, 630, 640, 650, 660], {0x61 + i: n for i, n in enumerate(names[1:])})
    var_store = store(
        [
            {"wght": (0, 1, 1)},
            {"wght": (-1, -1, 0)},
            {"wght": (0.2, 0.5, 0.8)},
            {"wght": (0, 1, 1), "wdth": (0, 1, 1)},
            {"wdth": (-1, -1, 0)},
        ],
        [
            ([0, 1, 2, 3, 4], [[101, -60, 0, 0, 0], [-101, 0, 33, 0, 7], [10, 10, 10, -77, 3], [0, 0, 0, 0, 0], [-3, 250, -1, 1, -129]]),
            ([3, 0], [[40000, -1], [5, 70000]]),
            ([2], [[-7]]),
        ],
    )
    fb.font["GDEF"] = gdef(var_store)
    X = 0x44
    sub0 = pair_format1(X, 0, {
        "a": [("b", value(X, XAdvance=-50, XAdvDevice=var_device(0, 0)), None),
              ("c", value(X, XAdvance=20, XAdvDevice=var_device(0, 1)), None),
              ("d", value(X, XAdvance=0, XAdvDevice=var_device(0xFFFF, 0xFFFF)), None)],
        "b": [("a", value(X, XAdvance=-10, XAdvDevice=hinting_device()), None),
              ("e", value(X, XAdvance=15), None),
              ("f", value(X, XAdvance=5, XAdvDevice=var_device(1, 0)), None)],
    }, names)
    F1, F2 = 0x55, 0x22
    v = lambda xp, xa, dp, da: value(F1, XPlacement=xp, XAdvance=xa, XPlaDevice=dp, XAdvDevice=da)
    w = lambda yp, dp: value(F2, YPlacement=yp, YPlaDevice=dp)
    sub1 = pair_format2(F1, F2, ["a", "c", "d", "g"], {"c": 1, "d": 1, "g": 2}, {"a": 1, "b": 1, "e": 2, "f": 2}, [
        [(v(0, 0, None, None), w(0, None)), (v(1, -5, var_device(0, 2), var_device(0, 4)), w(3, var_device(1, 1))), (v(0, 7, None, var_device(2, 0)), w(0, None))],
        [(v(0, -1, var_device(0, 4), None), w(-2, var_device(0, 0))), (v(-3, 12, var_device(1, 1), var_device(0, 1)), w(0, None)), (v(2, 2, var_device(0, 0), var_device(0, 0)), w(1, var_device(0, 2)))],
        [(v(0, 0, None, var_device(1, 0)), w(0, var_device(0, 4))), (v(5, -9, None, var_device(0, 2)), w(0, None)), (v(0, 0, None, None), w(0, None))],
    ])
    ALL = 0xFF
    full = lambda n: value(ALL, XPlacement=n, YPlacement=-n, XAdvance=2 * n, YAdvance=3 * n,
                           XPlaDevice=var_device(0, 0), YPlaDevice=var_device(0, 1),
                           XAdvDevice=var_device(0, 4), YAdvDevice=var_device(1, 0))
    sub2 = pair_format1(0, ALL, {"c": [("d", None, full(4))], "e": [("a", None, full(-6)), ("g", None, value(ALL))]}, names)
    sub3 = pair_format2(0x04, 0, ["f", "g"], {"g": 1}, {"g": 1}, [[(value(0x04, XAdvance=-30), None), (value(0x04, XAdvance=11), None)], [(value(0x04, XAdvance=-4), None), (value(0x04, XAdvance=0), None)]])
    gpos = layout_table(ot.GPOS, [("kern", [0, 1, 2])], [lookup(2, [sub0, sub1]), lookup(9, [extension(sub2)]), lookup(2, [sub3])])
    fb.font["GPOS"] = newTable("GPOS")
    fb.font["GPOS"].table = gpos
    save(fb, "kern-var.ttf")


def single(mapping):
    st = ot.SingleSubst()
    st.mapping = mapping
    return st


def axis_range(axis, low, high):
    c = ot.ConditionTable()
    c.Format = 1
    c.AxisIndex, c.FilterRangeMinValue, c.FilterRangeMaxValue = axis, low, high
    return c


def combine(fmt, conditions):
    c = ot.ConditionTable()
    c.Format = fmt
    if fmt == 5:
        c.ConditionTable = conditions[0]
    else:
        c.ConditionTable = conditions
        c.ConditionCount = len(conditions)
    return c


def value_condition(default, var_idx):
    c = ot.ConditionTable()
    c.Format = 2
    c.DefaultValue, c.VarIdx = default, var_idx
    return c


def var_record(conditions, substitutions):
    r = ot.FeatureVariationRecord()
    r.ConditionSet = ot.ConditionSet()
    r.ConditionSet.ConditionTable = conditions
    r.ConditionSet.ConditionCount = len(conditions)
    s = ot.FeatureTableSubstitution()
    s.Version = 0x00010000
    s.SubstitutionRecord = []
    for index, lookups in substitutions:
        sr = ot.FeatureTableSubstitutionRecord()
        sr.FeatureIndex = index
        sr.Feature = feature(lookups)
        s.SubstitutionRecord.append(sr)
    s.SubstitutionCount = len(s.SubstitutionRecord)
    r.FeatureTableSubstitution = s
    return r


def feature_var():
    names = [".notdef", "a", "b", "a.alt1", "a.alt2", "b.alt", "b.alt2"]
    fb = base_font(names, [500, 600, 610, 620, 630, 640, 650], {0x61: "a", 0x62: "b"})
    fb.font["GDEF"] = gdef(store([{"wght": (-1, -1, 0)}], [([0], [[200]])]))
    lookups = [
        lookup(1, [single({"a": "a.alt2"})]),
        lookup(1, [single({"a": "a.alt1"})]),
        lookup(1, [single({"b": "b.alt"})]),
        lookup(1, [single({"b": "b.alt2"})]),
    ]
    gsub = layout_table(ot.GSUB, [("calt", []), ("liga", [])], lookups)
    records = [
        var_record([axis_range(0, 0.5, 1), axis_range(1, -1, -0.5)], [(0, [1]), (1, [2])]),
        var_record([axis_range(0, 0.5, 1)], [(0, [1])]),
        var_record([combine(4, [axis_range(1, 0.75, 1), combine(5, [axis_range(0, -0.75, 1)])])], [(0, [2])]),
        var_record([value_condition(-100, 0)], [(0, [0])]),
        var_record([combine(3, [axis_range(1, -1, -0.875), axis_range(0, -0.125, 0.125)])], [(1, [3])]),
    ]
    gsub.FeatureVariations = ot.FeatureVariations()
    gsub.FeatureVariations.Version = 0x00010000
    gsub.FeatureVariations.FeatureVariationRecord = records
    gsub.FeatureVariations.FeatureVariationCount = len(records)
    gsub.Version = 0x00010001
    fb.font["GSUB"] = newTable("GSUB")
    fb.font["GSUB"].table = gsub
    save(fb, "feature-var.ttf")


kern_var()
feature_var()
