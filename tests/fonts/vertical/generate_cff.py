"""Original UPL CFF/CFF2 VORG and origin-map witnesses."""
from pathlib import Path
import argparse,io,json
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.ttLib import newTable
from fontTools.ttLib.tables import otTables
from fontTools.ttLib.tables._f_v_a_r import Axis
from fontTools.varLib.builder import buildVarRegionList,buildVarData,buildVarStore,buildVarIdxMap
from fontTools.cffLib.CFFToCFF2 import convertCFFToCFF2
HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
def emit(name,data):
 p=HERE/name
 if args.check:assert p.read_bytes()==data,p
 else:p.write_bytes(data)
names=['.notdef','space','a','b'];cases=[]
for mode in ['cff-vorg','cff-centered','cff2-vvar']:
 fb=FontBuilder(1000,isTTF=False);fb.setupGlyphOrder(names);fb.setupCharacterMap({32:'space',97:'a',98:'b'})
 strings={}
 for name in names:
  pen=T2CharStringPen(600,None)
  if name!='space':
   pen.moveTo((20,50));pen.lineTo((320,50));pen.lineTo((320,650));pen.lineTo((20,650));pen.closePath()
  strings[name]=pen.getCharString()
 fb.setupCFF('RocVertical-'+mode,{'FullName':'Roc Vertical '+mode,'FamilyName':'Roc Vertical '+mode,'Weight':'Regular'},strings,{})
 fb.setupHorizontalMetrics({n:(600,20) for n in names});fb.setupHorizontalHeader(ascent=800,descent=-200)
 fb.setupVerticalMetrics({n:(1200,100) for n in names});fb.setupVerticalHeader(ascent=500,descent=-500)
 fb.setupNameTable({'familyName':'Roc Vertical '+mode,'styleName':'Regular','psName':'RocVertical-'+mode});fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200);fb.setupPost();fb.setupMaxp()
 if mode!='cff-centered':
  table=newTable('VORG');table.majorVersion=1;table.minorVersion=0;table.defaultVertOriginY=850;table.VOriginRecords={'a':900};fb.font['VORG']=table
 if mode=='cff2-vvar':
  convertCFFToCFF2(fb.font)
  axis=Axis();axis.axisTag='wght';axis.minValue=100;axis.defaultValue=400;axis.maxValue=900;axis.flags=0;axis.axisNameID=256
  fvar=newTable('fvar');fvar.axes=[axis];fvar.instances=[];fb.font['fvar']=fvar
  rows=[[100+i*10] for i in range(len(names))]+[[50+i*10] for i in range(len(names))]
  store=buildVarStore(buildVarRegionList([{'wght':(0,1,1)}],['wght']),[buildVarData([0],rows,optimize=False)])
  table=newTable('VVAR');table.table=otTables.VVAR();table.table.Version=0x10000;table.table.VarStore=store
  table.table.AdvHeightMap=None;table.table.TsbMap=None;table.table.BsbMap=None;table.table.VOrgMap=buildVarIdxMap([4+i for i in range(len(names))],names);fb.font['VVAR']=table
 fb.font['head'].created=fb.font['head'].modified=3406620153;fb.font.recalcTimestamp=False
 out=io.BytesIO();fb.font.save(out,reorderTables=True);emit(mode+'.otf',out.getvalue())
 for direction in ['ttb','btt']:
  for i,text in enumerate(['ab','a b','ba','a','']):
   for weight in ([100,400,650,900] if mode=='cff2-vvar' else [400]):
    cases.append({'id':f'{mode}-{direction}-{i}-{weight}','font':mode+'.otf','text':text,'variations':{'wght':weight} if mode=='cff2-vvar' else {},'options':{'script':'Latn','direction':direction,'hb_options':['--show-flags']},'expected':'oracle'})
emit('cff-cases.jsonc',(json.dumps({'schema':1,'about':'Original valid CFF/CFF2 vertical origins, missing-VORG centering, VVAR origin maps and both directions.','cases':cases},indent=2)+'\n').encode())
