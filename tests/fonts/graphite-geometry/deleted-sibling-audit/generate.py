"""Original UPL three-sibling DELETE controls; public format definitions only."""
import argparse,importlib.util,io,json,struct
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE=Path(__file__).resolve().parent
sp=importlib.util.spec_from_file_location('original_frame',HERE.parent/'kern-frame-audit/generate.py');frame=importlib.util.module_from_spec(sp);sp.loader.exec_module(frame);geo=frame.base.geo

def recipes():
 for rtl in [False,True]:
  for target in [1,2,3]:
   for deleted in [False,True]:yield {'kind':'star','target':target,'deleted':deleted,'rtl':rtl}
  for kind,detached in [('getter',False),('constant',False),('getter',True)]:yield {'kind':kind,'target':1,'deleted':True,'detached':detached,'rtl':rtl}

def name(r):
 return f"collision-deleted-sibling-{r['kind']}-{r['target']}-{int(r['deleted'])}"+('-detached'if r.get('detached')else'')+('-rtl'if r['rtl']else'-ltr')

def make(r):
 data,_=frame.make({'name':'Original-'+name(r),'flags':[0]*5,'boxes':[frame.SMALL]*5,'promotion':0,'rtl':r['rtl']});font=TTFont(io.BytesIO(data),recalcTimestamp=False);chain=b''
 for gid in [1,2,3]:chain+=geo.set_attr(0,9000 if gid==r['target']else 1)+(b''if gid==1 and r.get('detached')else geo.attach(4-gid))+(geo.NEXT if gid<3 else b'')
 deletion=(geo.NEXT*(r['target']-1)+bytes([0x20]))if r['deleted']else b''
 if r['kind']in['getter','constant']:deletion=bytes([0x20])+(bytes([1,123])if r['kind']=='constant'else bytes([0x28,2,0]))+geo.NEXT+bytes([0x23,22])
 remain=tuple(g for g in range(1,6)if not r['deleted']or g!=r['target']);actions=[chain,deletion,b''];programs=[bytearray(geo.program(chain+bytes([0x32]),False,(1,2,3,4,5))),bytearray(geo.program(deletion+bytes([0x32]),False,(1,2,3,4,5))),bytearray(geo.program(bytes([0x32]),True,remain))]
 for q in programs:q[24:26]=struct.pack('>H',5);q[35]=0;q[48]=2 if r['rtl']else 1
 header=bytearray(programs[0][:58]);header[30]=header[33]=3;header[32]=2
 if r['kind']in['getter','constant']:header[46]=1
 struct.pack_into('>H',header,22,58);bodies=[];offsets=[76];delta=8
 for q in programs:
  body=bytearray(q[84:])
  for at in [8,12,16]:struct.pack_into('>I',body,at,struct.unpack_from('>I',body,at)[0]+delta)
  bodies.append(body);delta+=len(body);offsets.append(offsets[-1]+len(body))
 old=bytes(header)+struct.pack('>4I',*offsets)+programs[0][66:84]+b''.join(bodies);sub=16;pm=58;start=offsets[0];assert old[sub+start-10:sub+start]==struct.pack('>5H',1,1,8,10,2)
 s=bytearray(old[:sub+start-10]+struct.pack('>HHIIH',1,1,12,14,2)+old[sub+start:]);struct.pack_into('>I',s,0,0x50000)
 for i in range(4):struct.pack_into('>I',s,pm+4*i,offsets[i]+4)
 for first in offsets[:-1]:
  for at in [8,12,16]:struct.pack_into('>I',s,sub+first+4+at,struct.unpack_from('>I',old,sub+first+at)[0]+4)
 table=DefaultTable('Silf');table.data=bytes(s);font['Silf']=table;out=io.BytesIO();font.save(out,reorderTables=True);return out.getvalue(),actions

def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();cases=[]
 def emit(path,data):
  if args.check:assert path.read_bytes()==data,path
  else:path.write_bytes(data)
 for r in recipes():
  ident=name(r);data,actions=make(r);emit(HERE/(ident+'.ttf'),data);cases.append({'id':ident,'font':'deleted-sibling-audit/'+ident+'.ttf','text':'abcde','script':'Latn','direction':'rtl'if r['rtl']else'ltr','face_options':0,'recipe':r,'actions_hex':[a.hex()for a in actions]})
 for mode,file in [(0,'cases.jsonc'),(6,'mode6-cases.jsonc')]:emit(HERE/file,(json.dumps({'schema':1,'cases':[{**c,'face_options':mode}for c in cases]},indent=2)+'\n').encode())
 print('18 original three-sibling deletion fonts '+('reproduced'if args.check else'generated'))
if __name__=='__main__':main()
