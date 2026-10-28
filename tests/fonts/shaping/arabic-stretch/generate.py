"""Original stch five-tile fonts. Original data uses repository UPL."""
from pathlib import Path
import json
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
HERE=Path(__file__).resolve().parent
for mode,width in [('normal',100),('small',1),('zero',0)]:
 cmap={32:'space',97:'latin',0x0628:'beh',0x064E:'fatha',0x070F:'abbrev',0x0710:'alaph',0x0712:'beth',0x0715:'dalath',0x072A:'rish',0x071A:'heth',0x0730:'mark',0x200D:'zwj',0x200C:'zwnj'}
 names=['.notdef']+list(cmap.values())+['fixed0','repeat1','fixed2','repeat3','fixed4']
 fb=FontBuilder(1000,isTTF=True);fb.setupGlyphOrder(names);fb.setupCharacterMap(cmap)
 glyphs={}
 for name in names:
  pen=TTGlyphPen(None)
  if name not in ['space','zwj','zwnj']:
   pen.moveTo((0,0));pen.lineTo((100,0));pen.lineTo((100,300));pen.lineTo((0,300));pen.closePath()
  glyphs[name]=pen.glyph()
 fb.setupGlyf(glyphs)
 advances={n:(width if n.startswith('repeat') else 50 if n.startswith('fixed') else 0 if n in ['fatha','mark','zwj','zwnj'] else 600,0) for n in names}
 fb.setupHorizontalMetrics(advances);fb.setupHorizontalHeader(ascent=800,descent=-200)
 fb.setupNameTable({'familyName':'Roc Arabic Stretch '+mode,'styleName':'Regular','psName':'RocArabicStretch-'+mode});fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200);fb.setupPost();fb.setupMaxp()
 addOpenTypeFeaturesFromString(fb.font,'languagesystem arab dflt; languagesystem syrc dflt; feature stch { sub abbrev by fixed0 repeat1 fixed2 repeat3 fixed4; } stch;')
 fb.font['head'].created=fb.font['head'].modified=3406620153;fb.font.recalcTimestamp=False;fb.font.save(HERE/(mode+'.ttf'),reorderTables=True)
cases=[]
texts=['\u070f','\u070fܐ','\u070fܐܒ','\u070fܐܒܕܪ','\u070fܐܒ\u0730ܕ','\u070fܐ\u200dܒ','\u070fܐ\u200cܒ','\u070fܐaܒ','\u070fܐ ܒ','\u070fܐ\u070fܒ','\u070f'+('ܐ'*65),'\u070f'+('ܐ'*257)]
for mode in ['normal','small','zero']:
 for index,text in enumerate(texts):
  for script in ['Syrc','Arab']:
   for direction in ['rtl','ltr']:
    cases.append({'id':f'{mode}-{index}-{script}-{direction}','font':mode+'.ttf','text':text,'options':{'script':script,'direction':direction,'hb_options':['--show-flags']},'expected':'oracle'})
 for feature in ['stch=0','stch[0:2]=0']:
  cases.append({'id':mode+'-'+feature,'font':mode+'.ttf','text':'\u070fܐܒ','options':{'script':'Syrc','features':[feature],'hb_options':['--show-flags']},'expected':'oracle'})
(HERE/'stretch-cases.jsonc').write_text(json.dumps({'schema':1,'about':'Original valid five-tile stch fonts, exact spacing, zero widths,256glyphcap, controls, word boundaries and repeated markers.','cases':cases},indent=2,ensure_ascii=False)+'\n')
