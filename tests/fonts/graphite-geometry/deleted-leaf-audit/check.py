"""Offline exact programs, links, widths, getter and reference failure proof."""
import json,struct,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
commands=[[HERE/'generate.py','--check'],[HERE/'record.py','--check'],[HERE/'record.py','--check','--cases','deleted-leaf-audit/mode6-cases.jsonc','--output','deleted-leaf-audit/mode6-records.json'],[HERE/'record.py','--check','--cases','deleted-leaf-audit/mode6-cases.jsonc','--output','deleted-leaf-audit/tracing-off-records.json'],[HERE/'record_hb.py','--check'],[HERE/'record_ots.py','--check'],[HERE/'record_logging.py','--check']]
for command in commands:subprocess.run([sys.executable,*map(str,command)],check=True)
cases=json.loads((HERE/'cases.jsonc').read_text())['cases'];a=json.loads((HERE/'records.json').read_text())['records'];assert len(cases)==len(a)==18
for file in ['mode6-records.json','tracing-off-records.json']:
 b=json.loads((HERE/file).read_text())['records'];assert len(b)==18
 for x,y in zip(a,b):assert x['id']==y['id']and x['result']==y['result'],x['id']
records={r['id']:r['result']for r in a};bits=lambda x:struct.unpack('>I',struct.pack('>f',x))[0]
def table(data,tag):
 for i in range(struct.unpack_from('>H',data,4)[0]):
  p=12+16*i
  if data[p:p+4]==tag.encode():start,size=struct.unpack_from('>II',data,p+8);assert start+size<=len(data);return data[start:start+size]
 raise AssertionError(tag)
for case,row in zip(cases,a):
 recipe=case['recipe'];kind=recipe['kind'];result=row['result'];family={n['glyph']:n for n in result['reachable_family']};data=(HERE/Path(case['font']).name).read_bytes();s=table(data,'Silf');assert struct.unpack_from('>I',s)[0]==0x50000;sub=struct.unpack_from('>I',s,12)[0];assert s[sub+14]==3 and s[sub+16]==2;pm=sub+struct.unpack_from('>H',s,sub+4)[0]
 for i,action in enumerate(case['actions_hex']):
  first=sub+struct.unpack_from('>I',s,pm+4*i)[0];end=sub+struct.unpack_from('>I',s,pm+4*(i+1))[0];code=sub+struct.unpack_from('>I',s,first+16)[0];assert first<=code<end<=len(s)and s[code:end]==bytes.fromhex(action)+bytes([0x32])
 if kind in ['getter','constant']:
  assert s[sub+30]==1 and result['advance_bits'][0]==bits(1809)
  assert family[2]['links_glyph'][1]is None
  expected=123 if kind=='constant'else 0 if recipe.get('detached')else 1
  assert family[2]['user0']==expected
 else:
  assert result['advance_bits'][0]==bits(1207 if kind=='delete-ad'else 5684)
  if kind=='delete-d':assert not family[2]['active']and family[2]['links_glyph'][:2]==[3,1]
  if kind=='delete-da':assert not family[2]['active']and family[2]['links_glyph'][:2]==[3,None]and family[3]['links_glyph'][1]==2
  if kind=='delete-ad':assert 2 not in family and family[3]['links_glyph'][1]is None
outcomes=json.loads((HERE/'logging-outcomes.json').read_text())['records'];assert len(outcomes)==18
for row,case in zip(outcomes,cases):
 if case['recipe']['kind']in['delete-a','delete-da','delete-ad']:
  assert row['status']=='ReferenceProcessFailure'and row['returncode']==-11 and not row['trace_complete_json']and 'result'not in row
 else:assert row['status']=='Completed'and row['result']==records[row['id']]and row['trace_complete_json']
print('18 exact programs/mode pairs, DELETE-time links, widths, getter and 12 logging-neutral / 6 reference-crash outcomes pass offline')
