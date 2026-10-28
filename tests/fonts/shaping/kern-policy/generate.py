"""Original UPL fonts isolating script policy for legacy kern vs GPOS."""
from pathlib import Path
import argparse
import io
import json
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.ttLib import newTable
from fontTools.ttLib.tables._k_e_r_n import KernTable_format_0
HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument("--check",action="store_true");args=parser.parse_args()
def emit(name,data):
 path=HERE/name
 if args.check:
  assert path.read_bytes()==data, f"stale generated fixture: {path}"
 else:
  path.write_bytes(data)
for mode in ['legacy-only','gpos-dist','gpos-kern']:
 names=['.notdef','period','a','ka'];fb=FontBuilder(1000,isTTF=True);fb.setupGlyphOrder(names);fb.setupCharacterMap({46:'period',97:'a',0x0915:'ka'})
 glyphs={}
 for name in names:
  p=TTGlyphPen(None);p.moveTo((0,0));p.lineTo((50,0));p.lineTo((50,300));p.lineTo((0,300));p.closePath();glyphs[name]=p.glyph()
 fb.setupGlyf(glyphs);fb.setupHorizontalMetrics({name:(100,0) for name in names});fb.setupHorizontalHeader(ascent=800,descent=-200)
 fb.setupNameTable({'familyName':'Roc Kern Policy '+mode,'styleName':'Regular','psName':'RocKernPolicy-'+mode});fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200);fb.setupPost();fb.setupMaxp()
 kern=newTable('kern');kern.version=0;k=KernTable_format_0();k.version=0;k.coverage=1;k.kernTable={(name,name):500 for name in names[1:]};kern.kernTables=[k];fb.font['kern']=kern
 if mode!='legacy-only':
  tag='dist' if mode=='gpos-dist' else 'kern';amount=500 if tag=='dist' else 200
  addOpenTypeFeaturesFromString(fb.font,'languagesystem DFLT dflt; languagesystem deva dflt; languagesystem latn dflt; feature '+tag+' { '+''.join(f'pos {n} {n} {amount};' for n in names[1:])+' } '+tag+';')
 fb.font['head'].created=fb.font['head'].modified=3406620153;fb.font.recalcTimestamp=False;buffer=io.BytesIO();fb.font.save(buffer,reorderTables=True);emit(mode+'.ttf',buffer.getvalue())
cases=[]
for mode in ['legacy-only','gpos-dist','gpos-kern']:
 for script in ['Latn','Deva','Beng','Thai','Laoo','Khmr','Mymr','Tibt','Hang']:
  for text in ['..','aa','कक']:
   cases.append({'id':f'{mode}-{script}-{ord(text[0])}','font':mode+'.ttf','text':text,'options':{'script':script,'direction':'ltr','hb_options':['--show-flags']},'expected':'oracle'})
 for script in ['Latn','Deva']:
  for feature in ['kern=0','dist=0']:
   cases.append({'id':mode+'-'+script+'-'+feature,'font':mode+'.ttf','text':'..','options':{'script':script,'direction':'ltr','features':[feature],'hb_options':['--show-flags']},'expected':'oracle'})
emit('kern-cases.jsonc',(json.dumps({'schema':1,'about':'Original valid fonts distinguish script-disabled legacy kern from retained GPOSkern/dist and ordinary Latin/Hangul legacy kerning.','cases':cases},indent=2,ensure_ascii=False)+'\n').encode())
