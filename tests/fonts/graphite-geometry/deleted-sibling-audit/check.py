"""Offline public link, head/middle/tail width and retained-parent proof."""
import json,struct,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
for command in [[HERE/'generate.py','--check'],[HERE/'record.py','--check'],[HERE/'record.py','--check','--cases','deleted-sibling-audit/mode6-cases.jsonc','--output','deleted-sibling-audit/mode6-records.json'],[HERE/'record.py','--check','--cases','deleted-sibling-audit/mode6-cases.jsonc','--output','deleted-sibling-audit/tracing-off-records.json'],[HERE/'record_hb.py','--check'],[HERE/'record_ots.py','--check'],[HERE/'record_logging.py','--check']]:subprocess.run([sys.executable,*map(str,command)],check=True)
a=json.loads((HERE/'records.json').read_text())['records'];cases=json.loads((HERE/'cases.jsonc').read_text())['cases'];assert len(a)==len(cases)==18
for file in ['mode6-records.json','tracing-off-records.json']:
 b=json.loads((HERE/file).read_text())['records'];assert len(b)==18
 for x,y in zip(a,b):assert x['id']==y['id']and x['result']==y['result'],x['id']
bits=lambda x:struct.unpack('>I',struct.pack('>f',x))[0];results={r['id']:r['result']for r in a}
def table(data,tag):
 for i in range(struct.unpack_from('>H',data,4)[0]):
  p=12+16*i
  if data[p:p+4]==tag.encode():start,size=struct.unpack_from('>II',data,p+8);assert start+size<=len(data);return data[start:start+size]
 raise AssertionError(tag)
for case,row in zip(cases,a):
 r=case['recipe'];result=row['result'];family={n['glyph']:n for n in result['reachable_family']};root=family[4];s=table((HERE/Path(case['font']).name).read_bytes(),'Silf');assert struct.unpack_from('>I',s)[0]==0x50000;sub=struct.unpack_from('>I',s,12)[0];assert s[sub+14]==3 and s[sub+16]==2;pm=sub+struct.unpack_from('>H',s,sub+4)[0]
 for i,action in enumerate(case['actions_hex']):
  first=sub+struct.unpack_from('>I',s,pm+4*i)[0];end=sub+struct.unpack_from('>I',s,pm+4*(i+1))[0];code=sub+struct.unpack_from('>I',s,first+16)[0];assert first<=code<end<=len(s)and s[code:end]==bytes.fromhex(action)+bytes([0x32])
 assert root['position_bits']==[bits(605 if r['rtl']else 0),bits(0)]
 if r['kind']=='star':
  pruned=r['deleted']and r['target']==1;assert result['advance_bits'][0]==bits(1209 if pruned else 9685)
  assert root['links_glyph'][1]==(2 if pruned else 1)
  if pruned:assert 1 not in family and family[2]['links_glyph']==[4,None,3]and family[3]['links_glyph']==[4,None,None]
  elif r['deleted']:
   dead=family[r['target']];assert not dead['active']and dead['links_glyph'][0]==4 and dead['links_glyph'][1]is None
   assert family[r['target']-1]['links_glyph'][2]==r['target']
 else:
  assert result['advance_bits'][0]==bits(1209)and root['links_glyph'][1]==2 and family[2]['links_glyph']==[4,None,3]
  assert family[2]['user0']==(123 if r['kind']=='constant'else 0 if r.get('detached')else 1)
  assert s[sub+30]==1
for row,case in zip(json.loads((HERE/'logging-outcomes.json').read_text())['records'],cases):
 failed=case['recipe']['kind']=='star'and case['recipe']['deleted']and case['recipe']['target']==1
 if failed:assert row['status']=='ReferenceProcessFailure'and row['returncode']==-11 and not row['trace_complete_json']and 'result'not in row
 else:assert row['status']=='Completed'and row['result']==results[row['id']]
print('18 exact mode pairs, three-sibling deletion order/width/parent proof and 16 logging-neutral / 2 reference crashes current')
