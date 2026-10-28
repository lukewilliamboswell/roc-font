"""Original UPL three-pass DELETE-order controls; public formats only."""
import argparse,importlib.util,io,json,struct
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('original_frame',HERE.parent/'kern-frame-audit/generate.py');frame=importlib.util.module_from_spec(spec);spec.loader.exec_module(frame);geo=frame.base.geo

def recipes():
 for rtl in [False,True]:
  for kind in ['keep','delete-d','delete-a','delete-da','delete-ad']:yield {'kind':kind,'rtl':rtl}
  for kind in ['getter','constant']:
   for detached in [False,True]:yield {'kind':kind,'rtl':rtl,'detached':detached}

def make(r):
 name='OriginalDeletedLeaf-'+r['kind']+('-detached'if r.get('detached')else'')+('-rtl'if r['rtl']else'-ltr');data,_=frame.make({'name':name,'flags':[0,0,0,0],'boxes':[frame.SMALL]*4,'promotion':0,'rtl':r['rtl']});font=TTFont(io.BytesIO(data),recalcTimestamp=False)
 chain=geo.set_attr(0,1)+geo.attach(1)+geo.NEXT+geo.attach(1)+geo.set_attr(0,5000)
 deletion={'keep':b'','delete-d':geo.NEXT+bytes([0x20]),'delete-a':bytes([0x20]),'delete-da':geo.NEXT+bytes([0x20,0x20]),'delete-ad':bytes([0x20])+geo.NEXT+bytes([0x20]),'getter':bytes([0x20,0x28,2,0])+geo.NEXT+bytes([0x23,22]),'constant':bytes([0x20,1,123])+geo.NEXT+bytes([0x23,22])}[r['kind']]
 if r['kind']in['getter','constant']:chain=geo.set_attr(0,1)+(b''if r.get('detached')else geo.attach(1))
 remain={'keep':(1,2,3,4),'delete-d':(1,3,4),'delete-a':(2,3,4),'delete-da':(3,4),'delete-ad':(3,4),'getter':(2,3,4),'constant':(2,3,4)}[r['kind']]
 actions=[chain,deletion,b''];programs=[bytearray(geo.program(chain+bytes([0x32]),False,(1,2,3,4))),bytearray(geo.program(deletion+bytes([0x32]),False,(1,2,3,4))),bytearray(geo.program(bytes([0x32]),True,remain))]
 for q in programs:q[24:26]=struct.pack('>H',4);q[35]=0;q[48]=2 if r['rtl']else 1
 header=bytearray(programs[0][:58]);header[30]=header[33]=3;header[32]=2
 if r['kind']in['getter','constant']:header[46]=1
 struct.pack_into('>H',header,22,58);bodies=[];offsets=[76];delta=8
 for q in programs:
  body=bytearray(q[84:])
  for at in [8,12,16]:struct.pack_into('>I',body,at,struct.unpack_from('>I',body,at)[0]+delta)
  bodies.append(body);delta+=len(body);offsets.append(offsets[-1]+len(body))
 old=bytes(header)+struct.pack('>4I',*offsets)+programs[0][66:84]+b''.join(bodies)
 # Proper Silf5 and wide class offsets; preserve all three original pass bodies.
 sub=struct.unpack_from('>I',old,12)[0];pm=sub+struct.unpack_from('>H',old,sub+4)[0];start=offsets[0];assert old[sub+start-10:sub+start]==struct.pack('>5H',1,1,8,10,2)
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
  name='collision-deleted-leaf-'+r['kind']+('-detached'if r.get('detached')else'')+('-rtl'if r['rtl']else'-ltr');data,actions=make(r);emit(HERE/(name+'.ttf'),data);cases.append({'id':name,'font':'deleted-leaf-audit/'+name+'.ttf','text':'abcd','direction':'rtl'if r['rtl']else'ltr','face_options':0,'recipe':r,'actions_hex':[a.hex()for a in actions]})
 for mode,file in [(0,'cases.jsonc'),(6,'mode6-cases.jsonc')]:emit(HERE/file,(json.dumps({'schema':1,'cases':[{**c,'face_options':mode}for c in cases]},indent=2)+'\n').encode())
 print('18 original three-pass DELETE-order/getter fonts '+('reproduced'if args.check else'generated'))
if __name__=='__main__':main()
