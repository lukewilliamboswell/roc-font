"""Original UPL ordered finite/empty kerning controls; public formats only."""
import argparse,io,json,struct,sys
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
import collision_generate as base

def recipes():
 def r(name,**extra):return {'name':name,'target':[0,0,300,600],'finite':[100,0,400,600],'empty':[200,700,500,800],'rtl':False,**extra}
 yield r('ltr-finite-empty');yield r('ltr-empty-finite',swap=True)
 for swap in [False,True]:yield r('rtl-mirror-'+str(int(swap)),rtl=True,swap=swap,target=[-300,0,0,600],finite=[-400,0,-100,600],empty=[-500,700,-200,800])
 for left in [0,1200]:yield r('rtl-negative-'+str(left),rtl=True,target=[700,0,1000,600],finite=[0,0,300,600],empty=[left,700,left+50,800])
 for rtl in [False,True]:
  for outside in [False,True]:yield r('only-empty-'+str(int(rtl))+'-'+str(int(outside)),rtl=rtl,ignore_finite=True,target=[700,0,1000,600]if rtl else[0,0,300,600],finite=[0,0,300,600]if rtl else[100,0,400,600],empty=[1200,3000 if outside else 700,1250,3100 if outside else 800]if rtl else[200,3000 if outside else 700,500,3100 if outside else 800])
 yield r('target-cropped',target_parts=[[0,128,0,255,0,255,0,255]])
 yield r('target-diagonal',target=[500,0,800,600],diag=[0,100,0,100],empty=[100,700,400,800])
 finite=[0,255,0,128,0,255,0,255];empty=[0,255,213,255,0,255,0,255]
 yield r('part-only-empty',empty=[200,0,500,1200],empty_parts=[empty])
 yield r('part-finite-empty',empty=[200,0,500,1200],empty_parts=[finite,empty])
 yield r('part-empty-finite',empty=[200,0,500,1200],empty_parts=[empty,finite])
 yield r('empty-cropped-x',empty_parts=[[128,255,0,255,0,255,0,255]])
 low=[0,255,0,43,0,255,0,255];high=[0,255,213,255,0,255,0,255]
 for name,parts in [('low',[low]),('high',[high]),('separated',[low,high])]:yield r('hole-'+name,target_parts=parts,empty=[200,250,500,300])
 yield r('target-child-far',child=[500,3000,800,3600]);yield r('target-child-inside',child=[500,300,800,400])
 yield r('two-empty',extra=[800,700,1100,800]);yield r('two-empty-swapped',empty=[800,700,1100,800],extra=[200,700,500,800])
 yield r('margin13',margin=13);yield r('margin30',margin=30);yield r('margin101',margin=101,empty=[200,1000,500,1100]);yield r('width400',target=[0,0,400,600])

def make(r):
 count=4 if 'child'in r or 'extra'in r else 3;flags=[17]+[0]*(count-1)
 if r.get('ignore_finite'):flags[2 if r.get('swap')else 1]=2
 data,_=base.make('OriginalEmptyGap-'+r['name'],{'group_flags':flags,'pass_flags':9,'margin':r.get('margin',10)},r['rtl']);font=TTFont(io.BytesIO(data),recalcTimestamp=False);g=base.geo;action=b''
 for i in range(count):action+=(g.NEXT if i else b'')+g.set_attr(0,0)
 if 'child'in r:action+=bytes([1,253,0x26,2])+b''.join(g.set_attr(attr,0)for attr in[3,8,4,9])
 action+=bytes([0x32]);old=bytearray(g.program(action,True,tuple(range(1,count+1))));old[24:26]=struct.pack('>H',count);old[35]=32;old[48]=2 if r['rtl']else 1;old[49]=1;old[84]=9;sub=16;pm=58;first=68
 s=bytearray(old[:sub+first-10]+struct.pack('>HHIIH',1,1,12,14,2)+old[sub+first:]);struct.pack_into('>I',s,0,0x50000)
 for i in[0,1]:struct.pack_into('>I',s,pm+4*i,struct.unpack_from('>I',old,pm+4*i)[0]+4)
 for at in[8,12,16]:struct.pack_into('>I',s,sub+first+4+at,struct.unpack_from('>I',old,sub+first+at)[0]+4)
 def raw(tag,data):t=DefaultTable(tag);t.data=bytes(data);font[tag]=t
 raw('Silf',s);boxes=[r['target'],r['empty']if r.get('swap')else r['finite'],r['finite']if r.get('swap')else r['empty']]
 if count==4:boxes.append(r.get('child',r.get('extra')))
 for gid,box in enumerate(boxes,1):
  x0,y0,x1,y1=box;p=TTGlyphPen(None);p.moveTo((x0,y0));p.lineTo((x1,y0));p.lineTo((x1,y1));p.lineTo((x0,y1));p.closePath();font['glyf'][font.getGlyphName(gid)]=p.glyph()
 glat=font.getTableData('Glat');loc=font.getTableData('Gloc');pool=bytearray(glat[:8]);offsets=[]
 for gid in range(font['maxp'].numGlyphs):
  offsets.append(len(pool));a,b=struct.unpack_from('>HH',loc,8+2*gid);entry=glat[a:b];parts=[ [0,255,0,255,0,255,0,255] ]if gid==0 else r.get('target_parts')if gid==1 else r.get('empty_parts')if gid==(2 if r.get('swap')else 3)else None
  if gid==1 and r.get('diag'):entry=entry[:2]+bytes(r['diag'])+entry[6:]
  if parts is not None:entry=struct.pack('>H',(1<<len(parts))-1)+entry[2:6]+b''.join(bytes(part)for part in parts)+entry[6:]
  pool.extend(entry)
 offsets.append(len(pool));raw('Glat',pool);raw('Gloc',loc[:8]+struct.pack('>'+'H'*len(offsets),*offsets));out=io.BytesIO();font.save(out,reorderTables=True);return out.getvalue(),action,count

def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();cases=[]
 def emit(path,data):
  if a.check:assert path.read_bytes()==data,path
  else:path.write_bytes(data)
 for r in recipes():
  ident='collision-empty-gap-'+r['name'];data,action,count=make(r);emit(HERE/(ident+'.ttf'),data);cases.append({'id':ident,'font':'downstream-gap-audit/'+ident+'.ttf','text':'abcd'[:count],'script':'Latn','direction':'rtl'if r['rtl']else'ltr','face_options':0,'recipe':r,'action_hex':action.hex()})
 for mode,file in[(0,'cases.jsonc'),(6,'mode6-cases.jsonc')]:emit(HERE/file,(json.dumps({'cases':[{**c,'face_options':mode}for c in cases]},indent=2)+'\n').encode())
 print(str(len(cases))+' original ordered finite/empty fonts '+('reproduced'if a.check else'generated'))
if __name__=='__main__':main()
