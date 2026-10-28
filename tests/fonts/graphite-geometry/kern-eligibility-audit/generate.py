"""Original UPL whole-neighbor eligibility witnesses; public formats only."""
import argparse,io,json,struct,sys
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
import collision_generate as base

def recipes():
 for margin,below,above in [(10,-30,922),(13,-39,930),(101,-303,1109)]:
  for y in [below-1,below]:yield {'name':f'lower-{margin}-{y}','margin':margin,'target_y':0,'neighbor':[0,y-100,300,y]}
  for y in [above,above+1]:yield {'name':f'upper-{margin}-{y}','margin':margin,'target_y':0,'neighbor':[0,y,300,y+100]}
 for margin,ty,first in [(10,1000,970),(13,-1000,-1039)]:
  for high in [first-1,first]:yield {'name':f'translated-{margin}-{ty}-{high}','margin':margin,'target_y':ty,'neighbor':[0,high-100,300,high]}
 for name,lo,hi,bottom,top in [('below-half',-255,0,0,128),('above-part',0,1000,248,255),('below-whole',-255,0,0,255),('above-whole',0,1000,0,255),('below-part224',-255,0,0,224),('below-part225',-255,0,0,225)]:yield {'name':name,'margin':10,'target_y':0,'neighbor':[0,lo,300,hi],'part':[0,255,bottom,top,0,255,0,255]}

def make(r):
 data,action=base.make('OriginalKernEligibility-'+r['name'],{'margin':r['margin'],'pass_flags':9,'flags_a':17,'flags_b':0},True);f=TTFont(io.BytesIO(data),recalcTimestamp=False)
 for gid,box in [(1,[0,r['target_y'],300,r['target_y']+600]),(2,r['neighbor'])]:
  p=TTGlyphPen(None);x0,y0,x1,y1=box;p.moveTo((x0,y0));p.lineTo((x1,y0));p.lineTo((x1,y1));p.lineTo((x0,y1));p.closePath();f['glyf'][f.getGlyphName(gid)]=p.glyph()
 def raw(tag,data):t=DefaultTable(tag);t.data=bytes(data);f[tag]=t
 old=f.getTableData('Glat');loc=f.getTableData('Gloc');pool=bytearray(old[:8]);offsets=[]
 for gid in range(f['maxp'].numGlyphs):
  offsets.append(len(pool));a,b=struct.unpack_from('>HH',loc,8+2*gid);entry=old[a:b]
  part=[0,255,0,255,0,255,0,255]if gid==0 else r.get('part')if gid==2 else None
  if part is not None:entry=b'\0\1'+entry[2:6]+bytes(part)+entry[6:]
  pool.extend(entry)
 offsets.append(len(pool));raw('Glat',pool);raw('Gloc',loc[:8]+struct.pack('>'+'H'*len(offsets),*offsets))
 # Proper Silf5: collision pass bits and 32-bit class offsets, not reserved v3 diagnostics.
 old=f.getTableData('Silf');sub=struct.unpack_from('>I',old,12)[0];pm=sub+struct.unpack_from('>H',old,sub+4)[0];start=struct.unpack_from('>I',old,pm)[0]
 assert old[sub+start-10:sub+start]==struct.pack('>5H',1,1,8,10,2)
 classes=struct.pack('>HHIIH',1,1,12,14,2);s=bytearray(old[:sub+start-10]+classes+old[sub+start:]);struct.pack_into('>I',s,0,0x50000)
 for i in [0,1]:struct.pack_into('>I',s,pm+4*i,struct.unpack_from('>I',old,pm+4*i)[0]+4)
 for at in [8,12,16]:struct.pack_into('>I',s,sub+start+4+at,struct.unpack_from('>I',old,sub+start+at)[0]+4)
 raw('Silf',s);o=io.BytesIO();f.save(o,reorderTables=True);return o.getvalue(),action

def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();cases=[]
 def emit(path,data):
  if a.check:assert path.read_bytes()==data,path
  else:path.write_bytes(data)
 for r in recipes():
  name='collision-eligibility-'+r['name'];data,action=make(r);emit(HERE/(name+'.ttf'),data);cases.append({'id':name,'font':'kern-eligibility-audit/'+name+'.ttf','text':'ab','direction':'rtl','face_options':0,'positioning':True,'precontext':0,'recipe':r,'action':list(action)})
 for mode,file in [(0,'cases.jsonc'),(6,'mode6-cases.jsonc')]:emit(HERE/file,(json.dumps({'schema':1,'cases':[{**c,'face_options':mode}for c in cases]},indent=2)+'\n').encode())
 print(len(cases),'original Silf5 eligibility cases reproduced'if a.check else'original Silf5 eligibility cases generated')
if __name__=='__main__':main()
