"""Original deterministic Thai fallback fixtures; fontTools 4.61.1.

All glyphs are original rectangles. PUA characters deliberately have distinct
advances so cached HarfBuzz records observe selection as well as glyph ids.
"""
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
HERE = Path(__file__).resolve().parent
for mode in ('windows', 'macintosh', 'none'):
    cps = list(range(0xE01, 0xE5C))
    if mode == 'windows': cps += list(range(0xF700, 0xF71B))
    if mode == 'macintosh': cps += list(range(0xF884, 0xF89F))
    names = ['.notdef', 'space'] + ['u%04X' % cp for cp in cps]
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap({32: 'space', **{cp: 'u%04X' % cp for cp in cps}})
    glyphs = {}
    for name in names:
        pen = TTGlyphPen(None)
        if name != 'space':
            pen.moveTo((0,0)); pen.lineTo((200,0)); pen.lineTo((200,300)); pen.lineTo((0,300)); pen.closePath()
        glyphs[name] = pen.glyph()
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({name: (400 + i, 0) for i, name in enumerate(names)})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable({'familyName': 'Roc Thai Fallback ' + mode, 'styleName': 'Regular', 'psName': 'RocThaiFallback-' + mode})
    fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
    fb.setupPost(); fb.setupMaxp()
    fb.font['head'].created = fb.font['head'].modified = 3406620153
    fb.font.recalcTimestamp = False
    fb.font.save(HERE / (mode + '.ttf'), reorderTables=True)
