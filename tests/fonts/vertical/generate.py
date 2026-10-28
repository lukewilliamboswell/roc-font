"""Original UPL vertical metrics/positioning fonts; deterministic fontTools4.61.1."""
from pathlib import Path
import argparse,io,json
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.ttLib import newTable
from fontTools.ttLib.tables import otTables
from fontTools.ttLib.tables._f_v_a_r import Axis
from fontTools.varLib.builder import buildVarRegionList,buildVarData,buildVarStore
HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
def emit(name,data):
 p=HERE/name
 if args.check:assert p.read_bytes()==data,p
 else:p.write_bytes(data)
forms={0x2013:0xfe32,0x2014:0xfe31,0x2026:0xfe19,0x3001:0xfe11,0x3002:0xfe12,0xff08:0xfe35,0xff09:0xfe36}
cmap={32:'space',97:'a',98:'b',99:'c',0x301:'acute',0x200d:'zwj',0x200c:'zwnj',0x34f:'cgj'}
cmap.update({cp:f'u{cp:04x}' for cp in list(forms)+list(forms.values())})
names=['.notdef']+list(cmap.values())+['a.vert','b.vert','a.vrt2']
for mode in ['metrics','fallback','gpos','global-vert','variable','ttf-vorg','lang-vert','gpos-selected-vert']:
 fb=FontBuilder(1000,isTTF=True);fb.setupGlyphOrder(names);fb.setupCharacterMap(cmap)
 glyphs={}
 for name in names:
  pen=TTGlyphPen(None)
  if name not in ['space','zwj','zwnj','cgj']:
   pen.moveTo((20,50));pen.lineTo((320,50));pen.lineTo((320,650));pen.lineTo((20,650));pen.closePath()
  glyphs[name]=pen.glyph()
 fb.setupGlyf(glyphs);fb.setupHorizontalMetrics({n:(601 if n=='a' else 500,20) for n in names});fb.setupHorizontalHeader(ascent=800,descent=-200)
 fb.setupNameTable({'familyName':'Roc Vertical '+mode,'styleName':'Regular','psName':'RocVertical-'+mode})
 fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200);fb.setupPost();fb.setupMaxp()
 if mode!='fallback':
  fb.setupVerticalMetrics({n:(1200 if n=='a' else 1000,100 if n=='a' else 50) for n in names});fb.setupVerticalHeader(ascent=500,descent=-500)
 if mode in ['gpos','global-vert']:
  languages='languagesystem latn dflt;' if mode=='global-vert' else 'languagesystem DFLT dflt; languagesystem latn dflt; languagesystem hani dflt;'
  fea='''feature vert { sub a by a.vert; sub b by b.vert; } vert;
feature vrt2 { sub a.vert by a.vrt2; } vrt2;
feature vkrn { pos a.vert b.vert <11 13 77 90>; pos b.vert a.vert <7 -9 0 -50>; } vkrn;
feature dist { pos a.vert <5 17 0 30>; } dist;
markClass acute <anchor 100 500> @TOP;
feature mark { pos base a.vert <anchor 200 700> mark @TOP; } mark;
feature curs { pos cursive a.vert <anchor 20 650> <anchor 200 50>; pos cursive b.vert <anchor 100 750> <anchor 300 60>; } curs;
feature calt { sub a.vert c by b.vert; } calt;
'''
  addOpenTypeFeaturesFromString(fb.font,languages+fea)
 if mode=='lang-vert':
  addOpenTypeFeaturesFromString(fb.font,'languagesystem latn dflt; languagesystem hani dflt; feature vert { script latn; sub a by a.vert; script hani; sub a by b.vert; } vert;')
 if mode=='gpos-selected-vert':
  addOpenTypeFeaturesFromString(fb.font,'languagesystem latn dflt; languagesystem hani dflt; feature vert { script latn; sub a by a.vert; script hani; pos a <11 13 0 0>; } vert; feature locl { script hani; sub c by b; } locl;')
 if mode=='variable':
  axis=Axis();axis.axisTag='wght';axis.minValue=100;axis.defaultValue=400;axis.maxValue=900;axis.flags=0;axis.axisNameID=256
  fvar=newTable('fvar');fvar.axes=[axis];fvar.instances=[];fb.font['fvar']=fvar
  gvar=newTable('gvar');gvar.variations={n:[] for n in names};fb.font['gvar']=gvar
  store=buildVarStore(buildVarRegionList([{'wght':(0,1,1)}],['wght']),[buildVarData([0],[[100+i*10] for i in range(len(names))],optimize=False)])
  table=newTable('VVAR');table.table=otTables.VVAR();table.table.Version=0x10000;table.table.VarStore=store
  table.table.AdvHeightMap=None;table.table.TsbMap=None;table.table.BsbMap=None;table.table.VOrgMap=None;fb.font['VVAR']=table
 if mode=='ttf-vorg':
  table=newTable('VORG');table.majorVersion=1;table.minorVersion=0;table.defaultVertOriginY=999;table.VOriginRecords={'a':1234};fb.font['VORG']=table
 fb.font['head'].created=fb.font['head'].modified=3406620153;fb.font.recalcTimestamp=False
 buf=io.BytesIO();fb.font.save(buf,reorderTables=True);emit(mode+'.ttf',buf.getvalue())
cases=[]
for mode in ['metrics','fallback','gpos','global-vert','variable']:
 for script in ['Latn','Hani','Mong']:
  for direction in ['ttb','btt']:
   for i,text in enumerate(['','a','ab','ba','a\u0301b','a\u200db','a\u200cb','a\u034fb','（）—…、。','a b']):
    cases.append({'id':f'{mode}-{script}-{direction}-{i}','font':mode+'.ttf','text':text,'options':{'script':script,'direction':direction,'hb_options':['--show-flags']},'expected':'oracle'})
for mode in ['gpos','global-vert']:
 for direction in ['ttb','btt']:
  for feature in ['vert=0','vrt2=1','vkrn=1','dist=1','curs=1','calt=1','vkrn[0:1]=1','vert[0:1]=0']:
   cases.append({'id':mode+'-'+direction+'-'+feature,'font':mode+'.ttf','text':'ababa','options':{'script':'Hani','direction':direction,'features':[feature],'hb_options':['--show-flags']},'expected':'oracle'})
for weight in [100,400,650,900]:
 for direction in ['ttb','btt']:
  cases.append({'id':f'variable-{weight}-{direction}','font':'variable.ttf','text':'abca','variations':{'wght':weight},'options':{'script':'Latn','direction':direction,'hb_options':['--show-flags']},'expected':'oracle'})
emit('vertical-cases.jsonc',(json.dumps({'schema':1,'about':'Original vertical metrics, origins, VVAR, substitutions, placements, controls and feature ranges.','cases':cases},indent=2,ensure_ascii=False)+'\n').encode())

selection=[]
for mode in ['lang-vert','gpos-selected-vert']:
 for script in ['Latn','Hani','Kana']:
  for direction in ['ttb','btt']:
   for i,text in enumerate(['a','a（）']):
    selection.append({'id':f'{mode}-{script}-{direction}-{i}','font':mode+'.ttf','text':text,'options':{'script':script,'direction':direction,'hb_options':['--show-flags']},'expected':'oracle'})
emit('vert-selection-cases.jsonc',(json.dumps({'schema':1,'about':'Selected language vert wins before global search; selected GPOS vert suppresses unrelated GSUB fallback.','cases':selection},indent=2,ensure_ascii=False)+'\n').encode())
