"""Original Arabic presentation-only and partial-feature fonts (parent UPL)."""
from pathlib import Path
import json,re
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
raw=(ROOT/'package/ShaperArabicFallbackData.roc').read_text()
forms=[{k:int(v) for k,v in re.findall(r'(cp|init|medi|fina|isol): (\d+)',line)} for line in raw.splitlines() if '{ cp:' in line]
ligs=[{k:int(v) for k,v in re.findall(r'(group|first|second|third|substitute): (\d+)',line)} for line in raw.splitlines() if '{ group:' in line]
points={32,0x25CC,0x200C,0x200D,0x034F,0x064E,0x0651,0x0652}
for row in forms:
 points.update(v for v in row.values() if v)
for row in ligs:
 points.update(v for k,v in row.items() if k!='group' and v)
for mode in ['presentation','partial-isol','missing-forms']:
 cps=sorted(cp for cp in points if mode!='missing-forms' or cp<0xFB00 or cp in [0xFE8F,0xFE90,0xFE91,0xFE92])
 names=['.notdef']+[f'u{cp:04X}' for cp in cps]
 fb=FontBuilder(1000,isTTF=True);fb.setupGlyphOrder(names);fb.setupCharacterMap({cp:f'u{cp:04X}' for cp in cps})
 glyphs={}
 for i,name in enumerate(names):
  pen=TTGlyphPen(None)
  if name not in ['u0020','u200C','u200D','u034F']:
   pen.moveTo((0,0));pen.lineTo((200,0));pen.lineTo((200,300));pen.lineTo((0,300));pen.closePath()
  glyphs[name]=pen.glyph()
 fb.setupGlyf(glyphs);fb.setupHorizontalMetrics({name:(0 if name in ['u064E','u0651','u0652','u200C','u200D','u034F'] else 300+i,0) for i,name in enumerate(names)});fb.setupHorizontalHeader(ascent=800,descent=-200)
 fb.setupNameTable({'familyName':'Roc Arabic Fallback '+mode,'styleName':'Regular','psName':'RocArabicFallback-'+mode});fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200);fb.setupPost();fb.setupMaxp()
 if mode=='partial-isol':
  addOpenTypeFeaturesFromString(fb.font,'languagesystem arab dflt; feature isol { sub u0628 by uFE8F; } isol;')
 fb.font['head'].created=fb.font['head'].modified=3406620153;fb.font.recalcTimestamp=False;fb.font.save(HERE/(mode+'.ttf'),reorderTables=True)
texts=['ب','بب','ببب','لاب','بلاب','لآ','لأ','لإ','لَا','لّٰا','ب\u200dب','ب\u200cب','ب\u034fب','ب\u200dا','ل\u200dا','ل\u200cا','سَلَام','ڤڤڤ','کیک','َّ','َّ']
# Direct presentation characters exercise every mapped synthetic ligature,
# including historical PUA ligatures with no Unicode decomposition.
texts += [''.join(chr(row[k]) for k in ['first','second','third'] if row[k]) for row in ligs]
cases=[]
for mode in ['presentation','partial-isol','missing-forms']:
 for index,text in enumerate(texts):
  for direction in ['rtl','ltr']:
   cases.append({'id':f'{mode}-{index}-{direction}','font':f'{mode}.ttf','text':text,'options':{'script':'Arab','direction':direction,'hb_options':['--show-flags']},'expected':'oracle'})
 for feature in ['rlig=0','init=0','medi=0','fina=0','isol=0','init[0:2]=0']:
  cases.append({'id':f'{mode}-override-{feature}','font':f'{mode}.ttf','text':'ببب لاب','options':{'script':'Arab','features':[feature],'hb_options':['--show-flags']},'expected':'oracle'})
(HERE/'fallback-cases.jsonc').write_text(json.dumps({'schema':1,'about':'Original presentation-only Arabic fonts isolate synthesized forms, partial-GSUB fallback suppression and all pinned fallback ligature groups.','cases':cases},indent=2,ensure_ascii=False)+'\n')
