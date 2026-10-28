"""Original UPL phase-3 whitespace and group witnesses; public formats only."""
import argparse,importlib.util,io,json,struct,sys
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
import collision_generate as base
from fontTools.ttLib.tables.DefaultTable import DefaultTable

def recipes():
 for rtl in [True,False]:
  for shape in ['empty','ink']:
   for flags in [0,2,4,8,12,14,128,130,132,136,140,142]:yield {'shape':shape,'flags':flags,'rtl':rtl}
  for shape in ['vertical','horizontal','point','origin-point']:
   for flags in [0,2,128,130]:yield {'shape':shape,'flags':flags,'rtl':rtl}

def make(recipe):
 name='OriginalPhase3-'+recipe['shape']+'-'+str(recipe['flags'])+'-'+str(recipe['rtl'])
 data,action=base.make(name,{'group_flags':[17,recipe['flags'],0],'distance':100,'pass_flags':9},recipe['rtl'])
 f=TTFont(io.BytesIO(data),recalcTimestamp=False)
 box={'empty':None,'ink':(0,0,300,600),'vertical':(5,10,5,610),'horizontal':(5,10,305,10),'point':(5,10,5,10),'origin-point':(0,0,0,0)}[recipe['shape']]
 pen=TTGlyphPen(None)
 if box is not None:
  x0,y0,x1,y1=box;pen.moveTo((x0,y0));pen.lineTo((x1,y0));pen.lineTo((x1,y1));pen.lineTo((x0,y1));pen.closePath()
 f['glyf'][f.getGlyphName(2)]=pen.glyph()
 old=f.getTableData('Glat');loc=f.getTableData('Gloc');pool=bytearray(old[:8]);offsets=[]
 for gid in range(f['maxp'].numGlyphs):
  offsets.append(len(pool));a,b=struct.unpack_from('>HH',loc,8+2*gid);entry=old[a:b]
  if gid==0:entry=b'\0\1'+entry[2:6]+bytes([0,255,0,255,0,255,0,255])+entry[6:]
  pool.extend(entry)
 offsets.append(len(pool))
 for tag,data in [('Glat',bytes(pool)),('Gloc',loc[:8]+struct.pack('>'+'H'*len(offsets),*offsets))]:
  table=DefaultTable(tag);table.data=data;f[tag]=table
 out=io.BytesIO();f.save(out,reorderTables=True);return out.getvalue(),action

def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();cases=[]
 def emit(path,data):
  if args.check:assert path.read_bytes()==data,path
  else:path.write_bytes(data)
 for recipe in recipes():
  name='collision-space-'+recipe['shape']+'-'+str(recipe['flags'])+'-'+('rtl'if recipe['rtl']else'ltr');data,action=make(recipe);emit(HERE/(name+'.ttf'),data)
  cases.append({'id':name,'font':'phase3-space-audit/'+name+'.ttf','text':'abc','direction':'rtl'if recipe['rtl']else'ltr','positioning':True,'precontext':0,'face_options':0,'recipe':recipe,'action':list(action)})
 for mode,file in [(0,'cases.jsonc'),(6,'mode6-cases.jsonc')]:emit(HERE/file,(json.dumps({'schema':1,'cases':[{**c,'face_options':mode}for c in cases]},indent=2)+'\n').encode())
 print(len(cases),'original phase-3 cases reproduced'if args.check else'original phase-3 cases generated')
if __name__=='__main__':main()
