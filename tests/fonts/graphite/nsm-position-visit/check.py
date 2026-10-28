"""Offline table/key and placement-marker checks; no reference library needed."""
from pathlib import Path
import json,struct,subprocess,sys
HERE=Path(__file__).resolve().parent
subprocess.run([sys.executable,str(HERE/'record_raw.py'),'--check'],check=True)
subprocess.run([sys.executable,str(HERE.parent/'record_shapes.py'),'--check','--font-root',str(HERE),'--cases',str(HERE/'cases.jsonc'),'--output',str(HERE/'hb-records.json'),'--oracle',str(HERE/'hb-oracle.json')],check=True)
rows=json.loads((HERE/'raw-records.json').read_text())['records'];by_id={r['id']:r['result']for r in rows};bits=lambda x:struct.unpack('>I',struct.pack('>f',x))[0]
for row in rows:
 recipe,text=row['id'].split('/');native,flags,action=recipe.split('-');f=row['facts'];r=row['result']
 assert f['native']==int(native)and f['flags']==int(flags)and f['version']==0x50000 and f['advances']==[600,601,20]
 assert f['action_hex']=={'identity':'1b31','y0':'010023151b31','y17':'011123151b31'}[action]
 baseline=by_id[f'{native}-{flags}-identity/{text}'];x_key=lambda v:(v['advance_x_bits'],[(s['glyph'],s['position_bits'][0])for s in v['slots']])
 assert x_key(r)==x_key(baseline)
 if action=='y17':
  assert all(s['shift_y']==17 for s in r['slots'])
  if flags=='0':assert all(s['position_bits'][1]==bits(17)for s in r['slots'])
  else:assert any(s['position_bits'][1]==bits(0)for s in r['slots'])
print('All 72 exact glyph-marker observations current; X/advance invariance across actions verified')

subprocess.run([sys.executable,str(HERE/'record_raw.py'),'--check','--cases','arabic-cases.jsonc','--output','arabic-raw-records.json'],check=True)
subprocess.run([sys.executable,str(HERE.parent/'record_shapes.py'),'--check','--font-root',str(HERE),'--cases',str(HERE/'arabic-cases.jsonc'),'--output',str(HERE/'arabic-hb-records.json'),'--oracle',str(HERE/'arabic-hb-oracle.json')],check=True)
def table(data,tag):
 for i in range(struct.unpack_from('>H',data,4)[0]):
  at=12+16*i
  if data[at:at+4]==tag.encode():
   start,size=struct.unpack_from('>II',data,at+8);assert start+size<=len(data);return data[start:start+size]
 raise AssertionError(tag)
def mapped(data,code):
 cmap=table(data,'cmap')
 for i in range(struct.unpack_from('>H',cmap,2)[0]):
  platform,encoding,start=struct.unpack_from('>HHI',cmap,4+8*i)
  if platform not in [0,3]or struct.unpack_from('>H',cmap,start)[0]!=4:continue
  count=struct.unpack_from('>H',cmap,start+6)[0]//2
  for j in range(count):
   end=struct.unpack_from('>H',cmap,start+14+2*j)[0];begin=struct.unpack_from('>H',cmap,start+16+2*count+2*j)[0]
   if begin<=code<=end:
    delta=struct.unpack_from('>h',cmap,start+16+4*count+2*j)[0];at=start+16+6*count+2*j;offset=struct.unpack_from('>H',cmap,at)[0]
    glyph=code if offset==0 else struct.unpack_from('>H',cmap,at+offset+2*(code-begin))[0]
    return(glyph+delta)&0xffff if glyph or offset==0 else 0
 return 0
for row in json.loads((HERE/'arabic-raw-records.json').read_text())['records']:
 recipe,_=row['id'].split('/');_,flags,advance,action=recipe.split('-');r=row['result'];f=row['facts'];data=(HERE/(recipe+'.ttf')).read_bytes()
 assert mapped(data,0x628)==1 and mapped(data,0x64e)==2
 assert f['native']==2 and f['advances']==[600,601,int(advance)]
 assert r['advance_x_bits']==bits(0 if flags=='32'else 601+int(advance))
 if action=='y17':assert all(s['shift_y']==17 and s['position_bits'][1]==bits(0 if flags=='32'else 17)for s in r['slots'])
print('8 natural Arabic/native-RTL observations current; cmap mapping independently decoded')
