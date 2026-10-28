"""Original UPL AAT programs; generate checked fonts and cached-oracle cases."""
from pathlib import Path
import argparse, io, json, struct
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
u16=lambda *v:struct.pack('>'+'H'*len(v),*v)
u32=lambda *v:struct.pack('>'+'I'*len(v),*v)
def emit(name,data):
 p=HERE/name
 if args.check: assert p.read_bytes()==data, f'stale {p}'
 else:p.write_bytes(data)
def lookup(first,values):return u16(8,first,len(values))+u16(*values)
def machine(kind):
 classes=lookup(1,[4,5]);columns=6
 if kind=='insertion':
  rows=[[0,0,0,0,1,0]]*2;entries=[(0,0,65535,65535),(0,0x0820,0,65535)];words=2
 elif kind=='rearrange':
  rows=[[0,0,0,0,1,0]]*2+[[0,0,0,0,1,2]];entries=[(0,0),(2,0x8000),(0,0x2003)];words=0
 elif kind=='context':
  rows=[[0,0,0,0,1,0]]*2+[[0,0,0,0,1,2]];entries=[(0,0,65535,65535),(2,0x8000,65535,65535),(0,0,0,1)];words=2
 else:
  rows=[[0,0,0,0,1,0]]*2+[[0,0,0,0,1,2]];entries=[(0,0,0),(2,0x8000,0),(0,0xA000,0)];words=1
 header=16+({'rearrange':0,'context':4,'insertion':4,'ligature':12}[kind]);class_at=header;state_at=class_at+len(classes);entry_at=state_at+len(rows)*columns*2
 state=u16(*(v for row in rows for v in row));entry=u16(*(v for record in entries for v in record));tail_at=entry_at+len(entry)
 if kind=='rearrange':extra=b'';tail=b''
 elif kind=='context':
  one=lookup(1,[5]);two=lookup(2,[6]);extra=u32(tail_at);tail=u32(8,8+len(one))+one+two
 elif kind=='insertion':extra=u32(tail_at);tail=u16(5)
 else:
  actions=u32(0,0x80000000);components=u16(0,0,1,0,0,0,0,0,0);ligatures=u16(0,5);extra=u32(tail_at,tail_at+len(actions),tail_at+len(actions)+len(components));tail=actions+components+ligatures
 return u32(columns,class_at,state_at,entry_at)+extra+classes+state+entry+tail
names=['.notdef']+[f'g{i}' for i in range(1,9)]
fonts=[]
for kind,typ in [('direct',4),('rearrange',0),('context',1),('ligature',2),('insertion',5)]:
 for order,coverage in [('logical',0x30000000),('visual',0x20000000),('reverse',0x60000000),('features',0x30000000)]:
  label=kind+'-'+order;fonts.append(label)
  data=lookup(1,[5,6,0]) if kind=='direct' else machine(kind)
  sub=u32(12+len(data),coverage|typ,1)+data
  feature_data=(u16(1,2)+u32(1,0xFFFFFFFF)+u16(1,3)+u32(0,0xFFFFFFFE)+u16(0,1)+u32(0,0)) if order=='features' else b''
  chain=u32(1,16+len(feature_data)+len(sub),3 if feature_data else 0,1)+feature_data+sub
  chain+=bytes((-len(chain))%4);chain=chain[:4]+u32(len(chain))+chain[8:]
  table=u32(0x00020000,1)+chain
  fb=FontBuilder(1000,isTTF=True);fb.setupGlyphOrder(names);fb.setupCharacterMap({32:'g4',97:'g1',98:'g2',99:'g3',0x301:'g7',0x915:'g1',0x916:'g2'})
  glyphs={}
  for name in names:
   p=TTGlyphPen(None)
   if name!='g4':p.moveTo((0,0));p.lineTo((50,0));p.lineTo((50,300));p.lineTo((0,300));p.closePath()
   glyphs[name]=p.glyph()
  fb.setupGlyf(glyphs);fb.setupHorizontalMetrics({n:(100+i*10,0) for i,n in enumerate(names)});fb.setupHorizontalHeader(ascent=800,descent=-200)
  fb.setupNameTable({'familyName':'Roc AAT '+label,'styleName':'Regular','psName':'RocAat-'+label});fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200);fb.setupPost();fb.setupMaxp()
  morx=DefaultTable('morx');morx.data=table;fb.font['morx']=morx
  if order=='features':
   feat=DefaultTable('feat');feat.data=u32(0x00010000)+u16(1,0)+u32(0)+u16(1,2)+u32(24)+u16(0,256)+u16(2,257,3,258);fb.font['feat']=feat
   for id,text in [(256,'Ligatures'),(257,'On'),(258,'Off')]:fb.font['name'].setName(text,id,3,1,0x409)
  fb.font['head'].created=fb.font['head'].modified=3406620153;fb.font.recalcTimestamp=False;b=io.BytesIO();fb.font.save(b,reorderTables=True);emit(label+'.ttf',b.getvalue())
cases=[]
for name in fonts:
 for text in ['', 'a','b','ab','aab','aba','ba','abc','aa','a\u0301b','a b']:
  for direction in ['ltr','rtl','ttb','btt']:
   cases.append({'id':name+'-'+direction+'-'+text.encode().hex(),'font':name+'.ttf','text':text,'options':{'script':'Latn','direction':direction,'hb_options':['--show-flags']},'expected':'oracle'})
 for script,text in [('Arab','ab'),('Deva','कख')]:
  for direction in ['ltr','rtl']:
   cases.append({'id':name+'-'+script+'-'+direction,'font':name+'.ttf','text':text,'options':{'script':script,'direction':direction,'hb_options':['--show-flags']},'expected':'oracle'})
for name in fonts:
 if not name.endswith('-features'):continue
 for text in ['ab','aab','aba','abc','a b']:
  settings=[['liga=0'],['liga=1'],['liga=0','liga=1'],['liga=1','liga=0'],['liga[1:2]=0'],['liga[0:1]=0'],['liga[0:4294967295]=0','liga[1:2]=1'],['liga[1:2]=0','liga[0:3]=1'],['liga[0:4294967295]=0','liga[0:4294967295]=1'],['liga[0:4294967295]=1','liga[0:4294967295]=0']]
  for index,features in enumerate(settings):
   for direction in ['ltr','rtl','ttb','btt']:
    cases.append({'id':name+'-setting'+str(index)+'-'+direction+'-'+text.encode().hex(),'font':name+'.ttf','text':text,'options':{'script':'Latn','direction':direction,'features':features,'hb_options':['--show-flags']},'expected':'oracle'})
emit('morx-cases.jsonc',(json.dumps({'schema':1,'about':'Original UPL fonts isolate all five morx substitution types, processing order, clusters, end-of-text and directions.','cases':cases},indent=2,ensure_ascii=False)+'\n').encode())
