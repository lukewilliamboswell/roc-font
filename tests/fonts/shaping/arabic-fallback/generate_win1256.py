"""Original fonts with the pinned Windows-1256 glyph arrangement (UPL)."""
from pathlib import Path
import json
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
HERE=Path(__file__).resolve().parent
names=['.notdef']+[f'g{i:03}' for i in range(1,257)]
for mode in ['win1256','wrong-alef','no-sukun','prefer-unicode']:
 cmap={ord(bytes([i]).decode('cp1256')):names[i] for i in range(1,256)}
 if mode=='wrong-alef':cmap[0x0627]=names[198]
 if mode=='no-sukun':cmap.pop(0x0652)
 if mode=='prefer-unicode':cmap[0xFE8F]=names[256]
 fb=FontBuilder(1000,isTTF=True);fb.setupGlyphOrder(names);fb.setupCharacterMap(cmap)
 glyphs={}
 for name in names:
  pen=TTGlyphPen(None)
  if name!='g032':pen.moveTo((0,0));pen.lineTo((100,0));pen.lineTo((100,300));pen.lineTo((0,300));pen.closePath()
  glyphs[name]=pen.glyph()
 fb.setupGlyf(glyphs);fb.setupHorizontalMetrics({name:(300+i,0) for i,name in enumerate(names)});fb.setupHorizontalHeader(ascent=800,descent=-200)
 fb.setupNameTable({'familyName':'Roc Windows Arabic '+mode,'styleName':'Regular','psName':'RocWindowsArabic-'+mode});fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200);fb.setupPost();fb.setupMaxp()
 fb.font['head'].created=fb.font['head'].modified=3406620153;fb.font.recalcTimestamp=False;fb.font.save(HERE/(mode+'.ttf'),reorderTables=True)
texts=['ب','بب','ببب','تثجحخسشصضكلمناهوي','لا','بلا','لآ','بلآ','لأ','بلأ','لإ','بلإ','لَا','ب\u200dب','ب\u200cب','ل\u200dا','ل\u200cا','شَّ','شُّ','شِّ','ىىيي','بَّب']
cases=[]
for mode in ['win1256','wrong-alef','no-sukun','prefer-unicode']:
 for i,text in enumerate(texts):
  for direction in ['rtl','ltr']:
   cases.append({'id':f'{mode}-{i}-{direction}','font':mode+'.ttf','text':text,'options':{'script':'Arab','direction':direction,'hb_options':['--show-flags']},'expected':'oracle'})
 for feature in ['rlig=0','init=0','medi=0','fina=0','isol=0','init[0:2]=0']:
  cases.append({'id':mode+'-'+feature,'font':mode+'.ttf','text':'بلا ببب','options':{'script':'Arab','features':[feature],'hb_options':['--show-flags']},'expected':'oracle'})
(HERE/'windows-cases.jsonc').write_text(json.dumps({'schema':1,'about':'Original Windows-1256 glyph-order fallback fonts plus failed heuristic and Unicode-fallback-precedence controls.','cases':cases},indent=2,ensure_ascii=False)+'\n')
