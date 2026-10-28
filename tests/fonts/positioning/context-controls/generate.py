"""Valid original GPOS input/backtrack/lookahead control-matching fixtures.

Run with pinned oracle Python; no upstream font data is used.
"""
from pathlib import Path
import json
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.ttLib.tables import otTables as ot
HERE=Path(__file__).resolve().parent
MODES={
 'input-manual':('mark',"pos a' lookup ADJ b';",False),
 'input-auto':('dist',"pos a' lookup ADJ b';",False),
 'input-context':('mark',"pos a' lookup ADJ b';",True),
 'lookahead-manual':('mark',"pos a' lookup ADJ b;",False),
 'backtrack-manual':('mark',"pos a b' lookup ADJ;",False),
}
for mode,(feature,rule,context) in MODES.items():
 names=['.notdef','space','a','b','zwj','zwnj','cgj']
 fb=FontBuilder(1000,isTTF=True);fb.setupGlyphOrder(names)
 fb.setupCharacterMap({32:'space',97:'a',98:'b',0x200D:'zwj',0x200C:'zwnj',0x034F:'cgj'})
 glyphs={}
 for name in names:
  pen=TTGlyphPen(None)
  if name in ['.notdef','a','b']:
   pen.moveTo((0,0));pen.lineTo((200,0));pen.lineTo((200,300));pen.lineTo((0,300));pen.closePath()
  glyphs[name]=pen.glyph()
 fb.setupGlyf(glyphs);fb.setupHorizontalMetrics({name:(600 if name in ['.notdef','a','b'] else 0,0) for name in names});fb.setupHorizontalHeader(ascent=800,descent=-200)
 fb.setupNameTable({'familyName':'Roc GPOS Controls '+mode,'styleName':'Regular','psName':'RocGPOSControls-'+mode})
 fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200);fb.setupPost();fb.setupMaxp()
 addOpenTypeFeaturesFromString(fb.font,"languagesystem DFLT dflt; lookup ADJ { pos [a b] -80; } ADJ; feature "+feature+" { "+rule+" } "+feature+";")
 if context:
  lookup=next(l for l in fb.font['GPOS'].table.LookupList.Lookup if l.LookupType==8)
  old=lookup.SubTable[0];assert old.Format==3 and old.BacktrackGlyphCount==0 and old.LookAheadGlyphCount==0
  sub=ot.ContextPos();sub.Format=3;sub.GlyphCount=old.InputGlyphCount;sub.PosCount=old.PosCount;sub.Coverage=old.InputCoverage;sub.PosLookupRecord=old.PosLookupRecord
  lookup.LookupType=7;lookup.SubTable=[sub]
 fb.font['head'].created=fb.font['head'].modified=3406620153;fb.font.recalcTimestamp=False;fb.font.save(HERE/(mode+'.ttf'),reorderTables=True)
cases=[]
for mode in MODES:
 for index,text in enumerate(['ab','a\u200db','a\u200cb','a\u034fb','a\u034f\u200db']):
  for level in [0,1]:
   cases.append({'id':f'{mode}-{index}-{level}','font':f'../fonts/positioning/context-controls/{mode}.ttf','text':text,'options':{'script':'Latn','hb_options':['--show-flags',f'--cluster-level={level}']},'expected':'oracle'})
(HERE.parents[2]/'cases'/'position-context-controls.jsonc').write_text(json.dumps({'schema':1,'about':'Original OTS-valid GPOS7/8 matching controls; mark inputs use manual ZWJ, automatic dist inputs and all backtrack/lookahead ignore it. GPOS always skips ZWNJ and hidden CGJ.','cases':cases},indent=2,ensure_ascii=False)+'\n')
