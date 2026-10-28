"""Original UPL target-bin occupancy witnesses from public formats/API only."""
import argparse,io,json,struct,sys
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
import collision_generate as base

def recipes():
 for height,margin,ty,upper in [(600,10,0,None),(600,10,0,255),(600,10,0,128),(600,10,0,127),(600,10,0,248),(600,10,0,254),(600,30,0,None),(600,30,0,128),(600,30,0,127),(600,30,0,248),(600,101,0,None),(600,101,0,128),(600,101,0,248),(600,101,32000,None),(600,101,32000,128),(600,101,32000,248),(201,101,32000,128),(201,101,32000,255),(100,13,-1000,128),(100,13,-1000,248),(1,10,0,None),(9,10,0,None),(10,10,0,None),(609,10,0,None),(610,10,0,None)]:
  yield {'height':height,'margin':margin,'ty':ty,'upper':upper}
 for upper,low,high in [(128,310,315),(127,303,307)]:yield {'height':600,'margin':10,'ty':0,'upper':upper,'neighbor':[0,low,300,high]}

def make(r):
 data,action=base.make('OriginalTargetBins',{'pass_flags':9,'flags_a':17,'flags_b':0,'margin':r['margin'],'distance':100},True)
 f=TTFont(io.BytesIO(data),recalcTimestamp=False)
 for gid in [1,2]:
  p=TTGlyphPen(None);x0,lo,x1,hi=r['neighbor']if gid==2 and 'neighbor'in r else [0,r['ty'],300,r['ty']+r['height']];p.moveTo((x0,lo));p.lineTo((x1,lo));p.lineTo((x1,hi));p.lineTo((x0,hi));p.closePath();f['glyf'][f.getGlyphName(gid)]=p.glyph()
 old=f.getTableData('Glat');loc=f.getTableData('Gloc');pool=bytearray(old[:8]);offsets=[]
 for gid in range(f['maxp'].numGlyphs):
  offsets.append(len(pool));a,b=struct.unpack_from('>HH',loc,8+2*gid);entry=old[a:b]
  part=[0,255,0,255,0,255,0,255]if gid==0 else [0,255,0,r['upper'],0,255,0,255]if gid==1 and r['upper']is not None else None
  if part is not None:entry=b'\0\1'+entry[2:6]+bytes(part)+entry[6:]
  pool.extend(entry)
 offsets.append(len(pool))
 for tag,data in [('Glat',bytes(pool)),('Gloc',loc[:8]+struct.pack('>'+'H'*len(offsets),*offsets))]:
  t=DefaultTable(tag);t.data=data;f[tag]=t
 out=io.BytesIO();f.save(out,reorderTables=True);return out.getvalue(),action

def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();cases=[]
 def emit(path,data):
  if args.check:assert path.read_bytes()==data,path
  else:path.write_bytes(data)
 for i,r in enumerate(recipes()):
  name=f'collision-target-bin-{i:02d}';data,action=make(r);emit(HERE/(name+'.ttf'),data);cases.append({'id':name,'font':'target-occupancy-audit/'+name+'.ttf','text':'ab','direction':'rtl','positioning':True,'precontext':0,'face_options':0,'recipe':r,'action':list(action)})
 for mode,file in [(0,'cases.jsonc'),(6,'mode6-cases.jsonc')]:emit(HERE/file,(json.dumps({'schema':1,'cases':[{**c,'face_options':mode}for c in cases]},indent=2)+'\n').encode())
 print(len(cases),'original target-bin cases reproduced'if args.check else'original target-bin cases generated')
if __name__=='__main__':main()
