"""Deterministic, original positioning fixtures (fontTools 4.61.1).

Run with the pinned oracle Python. These are deliberately valid sfnt fonts,
including contours/name/OS2/post; they contain no third-party font data.
"""
from pathlib import Path
import json

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.ttLib.tables import otTables as ot
from fontTools.varLib.builder import buildVarRegionList, buildVarData, buildVarStore

HERE = Path(__file__).resolve().parent
NAMES = ['.notdef', 'space', 'a', 'b', 'c', 'd', 'acute', 'grave', 'f', 'i', 'fi', 'dot']
CMAP = {32: 'space', 97: 'a', 98: 'b', 99: 'c', 100: 'd', 102: 'f', 105: 'i', 0x301: 'acute', 0x300: 'grave', 0x307: 'dot'}
GDEF = 'table GDEF { GlyphClassDef [a b c d f i], [fi], [acute grave dot], ; } GDEF;'
LANG = 'languagesystem DFLT dflt; languagesystem latn dflt;'
MARKS = 'markClass acute <anchor 100 200> @TOP; markClass grave <anchor 80 180> @TOP; markClass dot <anchor 50 100> @TOP;'


def base():
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(NAMES)
    fb.setupCharacterMap(CMAP)
    glyphs = {}
    for name in NAMES:
        pen = TTGlyphPen(None)
        if name != 'space':
            pen.moveTo((0, 0))
            pen.lineTo((200, 0))
            pen.lineTo((200, 300))
            pen.lineTo((0, 300))
            pen.closePath()
        glyphs[name] = pen.glyph()
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({name: (600, 0) for name in NAMES})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable({'familyName': 'Roc Font Positioning Test', 'styleName': 'Regular', 'psName': 'RocFontPositioningTest'})
    fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
    fb.setupPost()
    fb.setupMaxp()
    fb.font['head'].created = fb.font['head'].modified = 3406620153
    fb.font.recalcTimestamp = False
    return fb


def save(name, features, change=None):
    fb = base()
    addOpenTypeFeaturesFromString(fb.font, LANG + MARKS + GDEF + features)
    if change:
        change(fb)
    fb.font.save(HERE / (name + '.ttf'), reorderTables=True)


def variation(fb):
    fb.setupFvar([('wght', 100, 400, 900, 'Weight')], [])
    region = buildVarRegionList([{'wght': (0, 1, 1)}], ['wght'])
    store = buildVarStore(region, [buildVarData([0], [[80], [120]], optimize=False)])
    gdef = fb.font['GDEF'].table
    gdef.Version = 0x00010003
    gdef.VarStore = store
    sub = fb.font['GPOS'].table.LookupList.Lookup[0].SubTable[0]
    anchor = sub.BaseArray.BaseRecord[0].BaseAnchor[0]
    anchor.Format = 3
    for field, inner in [('XDeviceTable', 0), ('YDeviceTable', 1)]:
        d = ot.Device()
        d.StartSize, d.EndSize, d.DeltaFormat = 0, inner, 0x8000
        setattr(anchor, field, d)


def positional_record():
    record = ot.PosLookupRecord()
    record.SequenceIndex, record.LookupListIndex = 0, 0
    return record


def coverage(names):
    result = ot.Coverage()
    result.glyphs = names
    return result


def context_format(format):
    def change(fb):
        lookup = fb.font['GPOS'].table.LookupList.Lookup[1]
        lookup.LookupType = 7
        sub = ot.ContextPos()
        sub.Format = format
        if format == 3:
            sub.GlyphCount, sub.PosCount = 2, 1
            sub.Coverage = [coverage(['a']), coverage(['b'])]
            sub.PosLookupRecord = [positional_record()]
        elif format == 1:
            sub.Coverage = coverage(['a'])
            rule = ot.PosRule()
            rule.GlyphCount, rule.PosCount = 2, 1
            rule.Input, rule.PosLookupRecord = ['b'], [positional_record()]
            group = ot.PosRuleSet()
            group.PosRuleCount, group.PosRule = 1, [rule]
            sub.PosRuleSetCount, sub.PosRuleSet = 1, [group]
        else:
            sub.Coverage = coverage(['a'])
            sub.ClassDef = ot.ClassDef()
            sub.ClassDef.classDefs = {'a': 1, 'b': 2}
            rule = ot.PosClassRule()
            rule.GlyphCount, rule.PosCount = 2, 1
            rule.Class, rule.PosLookupRecord = [2], [positional_record()]
            group = ot.PosClassSet()
            group.PosClassRuleCount, group.PosClassRule = 1, [rule]
            sub.PosClassSetCount, sub.PosClassSet = 2, [None, group]
        lookup.SubTable = [sub]
    return change


def recursive(fb):
    context_format(3)(fb)
    fb.font['GPOS'].table.LookupList.Lookup[1].SubTable[0].PosLookupRecord[0].LookupListIndex = 1


def anchor_point(fb):
    sub = fb.font['GPOS'].table.LookupList.Lookup[0].SubTable[0]
    for anchor in [sub.BaseArray.BaseRecord[0].BaseAnchor[0], sub.MarkArray.MarkRecord[0].MarkAnchor]:
        anchor.Format = 2
        anchor.AnchorPoint = 0


def chain_classes(fb):
    sub = ot.ChainContextPos()
    sub.Format = 2
    sub.Coverage = coverage(['a'])
    for name, values in [('BacktrackClassDef', {'c': 1, 'd': 1}), ('InputClassDef', {'a': 1}), ('LookAheadClassDef', {'b': 1})]:
        definition = ot.ClassDef()
        definition.classDefs = values
        setattr(sub, name, definition)
    rule = ot.ChainPosClassRule()
    rule.BacktrackGlyphCount, rule.Backtrack = 1, [1]
    rule.InputGlyphCount, rule.Input = 1, []
    rule.LookAheadGlyphCount, rule.LookAhead = 1, [1]
    rule.PosCount, rule.PosLookupRecord = 1, [positional_record()]
    group = ot.ChainPosClassSet()
    group.ChainPosClassRuleCount, group.ChainPosClassRule = 1, [rule]
    sub.ChainPosClassSetCount, sub.ChainPosClassSet = 2, [None, group]
    fb.font['GPOS'].table.LookupList.Lookup[1].SubTable = [sub]


def single_variation(fb):
    fb.setupFvar([('wght', 100, 400, 900, 'Weight')], [])
    region = buildVarRegionList([{'wght': (0, 1, 1)}], ['wght'])
    store = buildVarStore(region, [buildVarData([0], [[80], [120]], optimize=False)])
    gdef = fb.font['GDEF'].table
    gdef.Version, gdef.VarStore = 0x00010003, store
    sub = fb.font['GPOS'].table.LookupList.Lookup[0].SubTable[0]
    for field, inner in [('XPlaDevice', 0), ('YPlaDevice', 1), ('XAdvDevice', 0)]:
        device = ot.Device()
        device.StartSize, device.EndSize, device.DeltaFormat = 0, inner, 0x8000
        setattr(sub.Value, field, device)
    sub.ValueFormat |= 0x70


def null_base(fb):
    fb.font['GPOS'].table.LookupList.Lookup[0].SubTable[0].BaseArray.BaseRecord[0].BaseAnchor[0] = None


def main():
    save('single', 'feature dist { pos a <11 17 23 0>; pos b <31 37 41 0>; } dist;')
    save('single-extension', 'lookup Shift useExtension { pos a <11 17 23 0>; } Shift; feature dist { lookup Shift; } dist;')
    save('mark-base', 'feature mark { pos base a <anchor 300 700> mark @TOP; pos base b <anchor 250 650> mark @TOP; } mark;')
    save('mark-mark', 'feature mark { pos base a <anchor 300 700> mark @TOP; } mark; feature mkmk { pos mark acute <anchor 120 350> mark @TOP; pos mark grave <anchor 90 320> mark @TOP; } mkmk;')
    save('mark-ligature', 'feature liga { lookupflag IgnoreMarks; sub f i by fi; } liga; feature mark { pos ligature fi <anchor 200 600> mark @TOP ligComponent <anchor 500 800> mark @TOP; } mark;')
    curs = 'pos cursive a <anchor 50 100> <anchor 450 120>; pos cursive b <anchor 30 200> <anchor 470 220>; pos cursive c <anchor 40 300> <anchor 480 320>;'
    save('cursive', 'feature curs { ' + curs + ' } curs;')
    save('cursive-rtl-flag', 'feature curs { lookupflag RightToLeft; ' + curs + ' } curs;')
    for format in (1, 2, 3):
        save(f'context-{format}', "lookup Shift { pos a <11 17 23 0>; } Shift; feature dist { pos a' lookup Shift b; } dist;", context_format(format))
    save('chained', "lookup Shift { pos a <11 17 23 0>; } Shift; feature dist { pos c a' lookup Shift b; } dist;")
    save('chained-coverage', "lookup Shift { pos a <11 17 23 0>; } Shift; feature dist { pos [c d] a' lookup Shift [b c]; } dist;")
    save('chained-classes', "lookup Shift { pos a <11 17 23 0>; } Shift; feature dist { pos c a' lookup Shift b; } dist;", chain_classes)
    save('mark-propagation', 'feature mark { pos base a <anchor 300 700> mark @TOP; } mark; feature dist { pos a <13 29 47 0>; } dist;')
    save('mark-filter', '@KEEP = [acute]; feature mark { lookupflag UseMarkFilteringSet @KEEP; pos base a <anchor 300 700> mark @TOP; } mark;')
    save('anchor-point', 'feature mark { pos base a <anchor 300 700> mark @TOP; } mark;', anchor_point)
    save('recursive', "lookup Shift { pos a <11 17 23 0>; } Shift; feature dist { pos a' lookup Shift b; } dist;", recursive)
    save('context-cursive', 'lookup Join { ' + curs + " } Join; feature curs { pos b' lookup Join c; } curs;")
    save('variable-anchor', 'feature mark { pos base a <anchor 300 700> mark @TOP; } mark;', variation)
    save('variable-single', 'feature dist { pos a <11 17 23 0>; } dist;', single_variation)
    save('null-base-anchor', 'feature mark { pos base a <anchor 300 700> mark @TOP; } mark;', null_base)
    cases = []
    for fixture, texts in {
        'single': ['abca'], 'single-extension': ['aba'],
        'mark-base': ['a\u0301b\u0300', '\u0301a\u0301'],
        'mark-mark': ['a\u0301\u0300\u0307', 'a\u0300\u0307'],
        'mark-ligature': ['f\u0301i\u0300', 'fi\u0301', 'fi\u0301\u0300'],
        'cursive': ['abc', 'abca'], 'cursive-rtl-flag': ['abc', 'abca'],
        'context-1': ['abac'], 'context-2': ['abac'], 'context-3': ['abac'],
        'chained': ['cabdab'], 'chained-coverage': ['cabdac'],
        'mark-propagation': ['a\u0301'], 'mark-filter': ['a\u0301\u0300'],
        'context-cursive': ['abc'], 'variable-anchor': ['a\u0301'],
        'anchor-point': ['a\u0301'],
        'chained-classes': ['cabdab'], 'variable-single': ['aba'], 'null-base-anchor': ['a\u0301'],
    }.items():
        for ti, text in enumerate(texts):
            for direction in ['ltr', 'rtl']:
                cases.append({'id': f'{fixture}-{ti}-{direction}', 'font': f'../fonts/positioning/{fixture}.ttf', 'text': text, 'options': {'script': 'Latn', 'direction': direction}, 'expected': 'oracle'})
    cases.append({'id': 'variable-anchor-bold', 'font': '../fonts/positioning/variable-anchor.ttf', 'text': 'a\u0301', 'variations': {'wght': 900}, 'expected': 'oracle'})
    for weight in [550, 900]:
        cases.append({'id': f'variable-single-{weight}', 'font': '../fonts/positioning/variable-single.ttf', 'text': 'aba', 'variations': {'wght': weight}, 'expected': 'oracle'})
        cases.append({'id': f'variable-anchor-{weight}', 'font': '../fonts/positioning/variable-anchor.ttf', 'text': 'a\u0301', 'variations': {'wght': weight}, 'expected': 'oracle'})
    for font in sorted(HERE.glob('*.ttf')):
        cases.append({'id': 'read-' + font.stem, 'kind': 'read', 'font': '../fonts/positioning/' + font.name, 'expected': 'oracle'})
    path = HERE.parents[1] / 'cases' / 'positioning.jsonc'
    path.write_text(json.dumps({'schema': 1, 'about': 'Original valid fixtures isolating full horizontal GPOS lookup families; regenerate with tests/fonts/positioning/generate.py.', 'cases': cases}, indent=2, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
