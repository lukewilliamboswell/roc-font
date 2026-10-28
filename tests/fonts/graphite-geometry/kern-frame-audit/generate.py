"""Original UPL kerning-frame history controls; public formats/API only."""
import argparse,io,json,struct,sys
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
import collision_generate as base
SMALL=[0,0,300,600];TALL=[0,-600,300,1200]
def recipes():
 for flags in [0,1,2,17]:yield {'name':f'first-{flags}','flags':[flags,17,0],'boxes':[TALL,SMALL,SMALL]}
 yield {'name':'future-tall','flags':[17,17,0],'boxes':[SMALL,SMALL,[0,-900,300,1800]]}
 for flags in [0,1,2,17]:yield {'name':f'middle-{flags}','flags':[17,flags,17,0],'boxes':[SMALL,[0,-900,300,1800],SMALL,SMALL]}
 yield {'name':'second-tall','flags':[17,17,0],'boxes':[SMALL,[0,-900,300,1800],SMALL]}
 for direction in ['forward','backward']:
  for flags in [0,1,17,2]:
   child=[-2000,-600,-1700,1200]
   yield {'name':f'child-{direction}-{flags}','flags':[flags,17,0]if direction=='forward'else[17,flags,0],'boxes':[child,SMALL,SMALL]if direction=='forward'else[SMALL,child,SMALL],'attachment':direction}
 yield {'name':'pass-reset','flags':[17,17,0],'boxes':[TALL,SMALL,SMALL],'reset':True}
 for kind,prior in [('blank',None),('point0',[0,0,0,0]),('raised',[0,1000,300,1600])]:yield {'name':'seed-'+kind,'flags':[0,17,0],'boxes':[prior,[0,1000,300,1600],[0,1000,300,1600]]}
 for ymin in [0,-603,-607]:yield {'name':f'sample-{ymin}','flags':[0,17,0],'boxes':[[0,ymin,300,1200],SMALL,[0,303,300,307]]}
 yield {'name':'first-tall-ltr','flags':[17,17,0],'boxes':[TALL,SMALL,SMALL],'rtl':False}
 for q in [128,160,255]:yield {'name':f'child-part-{q}','flags':[17,0,0],'boxes':[SMALL,[-2000,-600,-1700,1200],SMALL],'attachment':'backward','child_part_upper':q}

 for h,m,ty in [(9,10,0),(10,10,0),(601,10,0),(1,30,0),(201,101,0),(201,101,32000)]:yield {'name':f'capacity-{h}-{m}-{ty}','flags':[17,0],'boxes':[[0,ty,300,ty+h],[0,ty,300,ty+h]],'margin':m}
 for d,q in [(-7,None),(-2,None),(3,None),(-7,13),(3,64)]:
  r={'name':f'lower-child-{d}-{q}','flags':[17,0,0],'boxes':[SMALL,[-2000,d-170,-1700,d+85],SMALL],'attachment':'backward'}
  if q is not None:r['part']={'glyph':2,'bytes':[0,255,q,255,0,255,0,255]}
  yield r
 yield {'name':'lower-target-13','flags':[17,0],'boxes':[[0,0,300,255],[0,0,300,255]],'part':{'glyph':1,'bytes':[0,255,13,255,0,255,0,255]}}
 for high in [-18,-12,-11,-25,-1000]:yield {'name':f'negative-upper-{high}','flags':[17,0,0],'boxes':[SMALL,[-2000,high-270,-1700,high-170],SMALL],'attachment':'backward'}
 yield {'name':'negative-upper-part','flags':[17,0,0],'boxes':[SMALL,[-2000,-370,-1700,-270],SMALL],'attachment':'backward','part':{'glyph':2,'bytes':[0,255,0,128,0,255,0,255]}}

 for flags in [0,17]:yield {'name':f'promotion-prior-y-{flags}','flags':[0,1,0],'boxes':[SMALL,SMALL,SMALL],'promotion':flags,'rtl':False}

 for flags in [0,17]:yield {'name':f'promotion-positive-y-{flags}','flags':[0,1,0],'boxes':[SMALL,SMALL,SMALL],'promotion':flags,'positive_y':True,'rtl':False}
 for flags in [0,17]:
  for detached in [False,True]:yield {'name':f'promotion-downstream-{flags}-{detached}','flags':[0,1,17,0,0],'boxes':[SMALL,SMALL,[0,1000,300,1600],SMALL,SMALL],'promotion':flags,'positive_y':True,'downstream':True,'detached':detached,'rtl':False}

def make(r):
 params={'group_flags':r['flags'],'margin':r.get('margin',10),'pass_flags':9}
 if 'attachment'in r:params['attachment']=r['attachment']
 if r.get('reset')or 'promotion'in r:params['second']='repeat'
 if 'promotion'in r:params['pass_flags']=1;params['axis']='y'
 data,action=base.make('OriginalKernelFrame-'+r['name'],params,r.get('rtl',True));f=TTFont(io.BytesIO(data),recalcTimestamp=False)
 for gid,box in enumerate(r['boxes'],1):
  p=TTGlyphPen(None)
  if box is not None:
   x0,y0,x1,y1=box;p.moveTo((x0,y0));p.lineTo((x1,y0));p.lineTo((x1,y1));p.lineTo((x0,y1));p.closePath()
  f['glyf'][f.getGlyphName(gid)]=p.glyph()
 old=f.getTableData('Glat');loc=f.getTableData('Gloc');pool=bytearray(old[:8]);offsets=[]
 for gid in range(f['maxp'].numGlyphs):
  offsets.append(len(pool));a,b=struct.unpack_from('>HH',loc,8+2*gid);entry=old[a:b]
  part=[0,255,0,255,0,255,0,255]if gid==0 else r['part']['bytes']if 'part'in r and r['part']['glyph']==gid else [0,255,0,r['child_part_upper'],0,255,0,255]if gid==2 and 'child_part_upper'in r else None
  if part is not None:entry=b'\0\1'+entry[2:6]+bytes(part)+entry[6:]
  pool.extend(entry)
 offsets.append(len(pool))
 def raw(tag,data):t=DefaultTable(tag);t.data=bytes(data);f[tag]=t
 if 'promotion'in r:
  for gid in range(f['maxp'].numGlyphs):
   off=offsets[gid];bitmap=struct.unpack_from('>H',pool,off)[0];values=off+6+8*bitmap.bit_count()+4
   struct.pack_into('>h',pool,values+2,-1000 if r.get('downstream')and gid==3 else -1);struct.pack_into('>h',pool,values+6,1000 if r.get('downstream')and gid==3 else 1)
   if r.get('positive_y'):struct.pack_into('>h',pool,values+4,600)
 raw('Glat',pool);raw('Gloc',loc[:8]+struct.pack('>'+'H'*len(offsets),*offsets))
 if r.get('reset')or 'promotion'in r:
  s=bytearray(f.getTableData('Silf'));sub=struct.unpack_from('>I',s,12)[0];pm=sub+struct.unpack_from('>H',s,sub+4)[0];second=struct.unpack_from('>I',s,pm+4)[0]
  second_action=(base.geo.attach(1)+base.geo.set_attr(57,r['promotion']))if 'promotion'in r else base.geo.set_attr(21,3000)+action
  if r.get('downstream')and not r.get('detached'):second_action=second_action+base.geo.NEXT*3+base.geo.attach(-2)
  payload=bytearray(base.geo.program(second_action+bytes([0x32]),True,tuple(range(1,len(r['flags'])+1)))[84:]);payload[0]=9
  for at in [8,12,16]:struct.pack_into('>I',payload,at,struct.unpack_from('>I',payload,at)[0]+second-68)
  s=s[:sub+second]+payload;struct.pack_into('>I',s,pm+8,len(s)-sub);raw('Silf',s)
 out=io.BytesIO();f.save(out,reorderTables=True);return out.getvalue(),action

def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();cases=[]
 def emit(path,data):
  if args.check:assert path.read_bytes()==data,path
  else:path.write_bytes(data)
 for r in recipes():
  name='collision-kern-frame-'+r['name'];data,action=make(r);emit(HERE/(name+'.ttf'),data);cases.append({'id':name,'font':'kern-frame-audit/'+name+'.ttf','text':''.join(chr(97+i)for i in range(len(r['flags']))),'direction':'rtl'if r.get('rtl',True)else'ltr','face_options':0,'positioning':True,'precontext':0,'recipe':r,'action':list(action)})
 for mode,file in [(0,'cases.jsonc'),(6,'mode6-cases.jsonc')]:emit(HERE/file,(json.dumps({'schema':1,'cases':[{**c,'face_options':mode}for c in cases]},indent=2)+'\n').encode())
 print(len(cases),'original kernel-frame cases reproduced'if args.check else'original kernel-frame cases generated')
if __name__=='__main__':main()
