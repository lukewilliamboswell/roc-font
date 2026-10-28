"""Offline post-DELETE VM metric and ordinary public-run witness proof."""
import json,struct,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
for command in [[HERE/'generate.py','--check'],[HERE/'record.py','--check'],[HERE/'record.py','--check','--cases','deleted-metric-audit/mode6-cases.jsonc','--output','deleted-metric-audit/mode6-records.json'],[HERE/'record.py','--check','--cases','deleted-metric-audit/mode6-cases.jsonc','--output','deleted-metric-audit/tracing-off-records.json'],[HERE/'record_hb.py','--check'],[HERE/'record_ots.py','--check'],[HERE/'record_logging.py','--check']]:subprocess.run([sys.executable,*map(str,command)],check=True)
cases=json.loads((HERE/'cases.jsonc').read_text())['cases'];a=json.loads((HERE/'records.json').read_text())['records'];assert len(cases)==len(a)==22
for file in ['mode6-records.json','tracing-off-records.json']:
 b=json.loads((HERE/file).read_text())['records'];assert len(b)==22
 for x,y in zip(a,b):assert x['id']==y['id']and x['result']==y['result'],x['id']
bits=lambda x:struct.unpack('>I',struct.pack('>f',x))[0];results={r['id']:r['result']for r in a}
for case,row in zip(cases,a):
 r=case['recipe'];kind=r['kind'];metric=r['metric'];level=r['level']
 if metric==8:expected=(603 if kind=='intermediate'else 604)if level==0 else 5080 if kind=='intermediate'else 604 if kind=='head'else 9080
 elif metric==2:expected=600 if level==0 else 940 if kind=='intermediate'else 770
 else:expected=300 if level==0 else 460 if kind=='intermediate'else 380
 active=[n for n in row['result']['reachable_family']if n['active']];assert active[0]['user0']==expected and active[-1]['advance_bits'][0]==bits(expected)
for row,case in zip(json.loads((HERE/'logging-outcomes.json').read_text())['records'],cases):
 if case['recipe']['kind']=='head':assert row['returncode']==-11 and row['status']=='ReferenceProcessFailure'and not row['trace_complete_json']and 'result'not in row
 else:assert row['status']=='Completed'and row['result']==results[row['id']]
proof=json.loads((HERE/'before-public-proof.json').read_text());assert len(proof['rows'])==22 and sum(r['passed']for r in proof['rows'])==14
print('22 VM metric/public-advance witnesses, exact mode pairs, OTS and 17 logging-neutral / 5 reference-crash outcomes current')
