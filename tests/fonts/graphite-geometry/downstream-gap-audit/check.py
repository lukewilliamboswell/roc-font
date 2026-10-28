"""Offline ordered whole-neighbor/target-presence kerning evidence."""
import json,struct,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
commands=[[HERE/'generate.py','--check'],[HERE/'record.py','--check'],[HERE/'record.py','--check','--cases','downstream-gap-audit/mode6-cases.jsonc','--output','downstream-gap-audit/mode6-records.json'],[HERE.parent/'record_traces.py','--check','--cases','downstream-gap-audit/cases.jsonc','--output','downstream-gap-audit/traces.json'],[HERE/'record_hb.py','--check'],[HERE/'record_ots.py','--check']]
for file in ['tracing-off-records.json','tracing-on-records.json']:commands.append([HERE/'record_logging.py','--check','--cases','downstream-gap-audit/mode6-cases.jsonc','--output','downstream-gap-audit/'+file])
commands.append([HERE/'target_right_midpoint.py','--check'])
for command in commands:subprocess.run([sys.executable,*map(str,command)],check=True)
a=json.loads((HERE/'records.json').read_text())['records'];assert len(a)==27
for file in ['mode6-records.json','tracing-off-records.json','tracing-on-records.json']:
 b=json.loads((HERE/file).read_text())['records'];assert len(b)==27
 for x,y in zip(a,b):assert x['id']==y['id']and x['result']==y['result'],x['id']
values={'ltr-finite-empty':120,'ltr-empty-finite':-210,'rtl-mirror-0':210,'rtl-mirror-1':210,'rtl-negative-0':-390,'rtl-negative-1200':-390,'only-empty-0-0':1000,'only-empty-0-1':0,'only-empty-1-0':-1000,'only-empty-1-1':0,'target-cropped':-29.411758422851562,'target-diagonal':475.27447509765625,'part-only-empty':-210,'part-finite-empty':-210,'part-empty-finite':-210,'empty-cropped-x':120,'hole-low':120,'hole-high':120,'hole-separated':120,'target-child-far':120,'target-child-inside':620,'two-empty':120,'two-empty-swapped':120,'margin13':126,'margin30':160,'margin101':302,'width400':220};bits=lambda x:struct.unpack('>I',struct.pack('>f',x))[0]
for row in a:
 name=row['id'].removeprefix('collision-empty-gap-');assert row['result']['slots'][0]['advance_bits'][0]==bits(values[name]),name
traces={r['id'].removeprefix('collision-empty-gap-'):[m for p in r['collisions']for c in p if c.get('phase')=='3'for m in c['moves']]for r in json.loads((HERE/'traces.json').read_text())['records']}
assert traces['target-child-far'][0]['xbound']==310 and traces['target-child-inside'][0]['xbound']==810
assert traces['target-diagonal'][0]['xbound']<600  # whole bbox xMax=800; the bound is sampled ink.
assert not traces['only-empty-0-1']and not traces['only-empty-1-1']
for name in['part-only-empty','part-finite-empty','part-empty-finite']:
 assert traces[name][0]['needed']==-210
proof=json.loads((HERE/'before-public-proof.json').read_text());assert sum(r['passed']for r in proof['rows'])==12 and all(r['actual']['engine']=='Graphite'and not r['actual']['budgets']for r in proof['rows'])
print('27 exact mode/logging pairs, OTS and ordered finite/empty direction/part/hole/sampled-bound observations pass offline')
