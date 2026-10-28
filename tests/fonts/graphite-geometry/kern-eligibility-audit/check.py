"""Offline reproducibility, exact caches and eligibility counterexamples."""
import json,struct,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
commands=[[HERE/'generate.py','--check'],[HERE/'record_modes.py','--check'],[HERE/'record_modes.py','--check','--cases','kern-eligibility-audit/mode6-cases.jsonc','--output','kern-eligibility-audit/mode6-records.json'],[HERE.parent/'record_traces.py','--check','--cases','kern-eligibility-audit/cases.jsonc','--output','kern-eligibility-audit/traces.json'],[HERE/'record_ots.py','--check']]
for file in ['tracing-off-records.json','tracing-on-records.json']:commands.append([HERE/'record_logging.py','--check','--cases','kern-eligibility-audit/mode6-cases.jsonc','--output','kern-eligibility-audit/'+file])
for command in commands:subprocess.run([sys.executable,*map(str,command)],check=True)
records=json.loads((HERE/'records.json').read_text())['records'];assert len(records)==22
for file in ['mode6-records.json','tracing-off-records.json','tracing-on-records.json']:
 other=json.loads((HERE/file).read_text())['records'];assert len(other)==22
 for x,y in zip(records,other):assert x['id']==y['id']and x['result']==y['result'],x['id']
traces={r['id']:[m for p in r['collisions']for phase in p if phase.get('phase')=='3'for m in phase['moves']]for r in json.loads((HERE/'traces.json').read_text())['records']};bits=lambda x:struct.unpack('>I',struct.pack('>f',x))[0]
for c,r in zip(json.loads((HERE/'cases.jsonc').read_text())['cases'],records):
 q=c['recipe'];name=q['name'];data=(HERE/Path(c['font']).name).read_bytes()
 # Verify proper Silf5 from the actual SFNT directory, independently of the generator.
 found=False
 for i in range(struct.unpack_from('>H',data,4)[0]):
  p=12+16*i
  if data[p:p+4]==b'Silf':start,size=struct.unpack_from('>II',data,p+8);assert struct.unpack_from('>I',data,start)[0]==0x50000;found=True
 assert found
 if name.startswith('lower-'):eligible=q['neighbor'][3]>=q['target_y']-3*q['margin']
 elif name.startswith('upper-'):eligible=q['neighbor'][1]in[922,930,1109]
 elif name.startswith('translated-'):eligible=q['neighbor'][3]in[970,-1039]
 else:eligible=True
 assert bool(traces[c['id']])==eligible,c['id']
 if not eligible:assert r['result']['advance_bits'][0]==bits(701)
 elif name not in ['below-whole','above-whole']:assert r['result']['advance_bits'][0]==bits(-299)
print('22 proper-Silf5 cases: exact mode/logging equality, OTS retention and whole-vs-part eligibility pass offline')
