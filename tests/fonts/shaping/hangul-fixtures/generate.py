"""Original rectangle-only Hangul fixtures, generated with fontTools4.61.1."""
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
HERE=Path(__file__).resolve().parent
cps={32:'space',97:'a',0x1100:'L',0x1161:'V',0x11A8:'T',0xA960:'oldL',0xD7B0:'oldV',0xD7CB:'oldT',0xAC00:'LV',0xAC01:'LVT',0x302E:'tone1',0x302F:'tone2',0x25CC:'circle'}
for mode in ['all','decomposed','no-jamo','zero-tone','no-circle']:
    cmap={cp:name for cp,name in cps.items() if not(mode=='decomposed' and name in ['LV','LVT']) and not(mode=='no-jamo' and name in ['L','V','T']) and not(mode=='no-circle' and name=='circle')}
    names=['.notdef']+list(cps.values())+['lalt','valt','talt','calt','aalt']
    fb=FontBuilder(1000,isTTF=True);fb.setupGlyphOrder(names);fb.setupCharacterMap(cmap)
    glyphs={}
    for name in names:
        pen=TTGlyphPen(None)
        if name!='space':pen.moveTo((0,0));pen.lineTo((200,0));pen.lineTo((200,300));pen.lineTo((0,300));pen.closePath()
        glyphs[name]=pen.glyph()
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({name:(0 if mode=='zero-tone' and name in ['tone1','tone2'] else 400+i,0) for i,name in enumerate(names)})
    fb.setupHorizontalHeader(ascent=800,descent=-200);fb.setupNameTable({'familyName':'Roc Hangul '+mode,'styleName':'Regular','psName':'RocHangul-'+mode})
    fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200);fb.setupPost();fb.setupMaxp()
    addOpenTypeFeaturesFromString(fb.font,'''languagesystem DFLT dflt; languagesystem hang dflt;
feature calt { sub [L V T oldL oldV oldT] by calt; sub a by aalt; } calt;
feature ljmo { sub [L oldL] by lalt; } ljmo;
feature vjmo { sub [V oldV] by valt; } vjmo;
feature tjmo { sub [T oldT] by talt; } tjmo;''')
    fb.font['head'].created=fb.font['head'].modified=3406620153;fb.font.recalcTimestamp=False
    fb.font.save(HERE/(mode+'.ttf'),reorderTables=True)
