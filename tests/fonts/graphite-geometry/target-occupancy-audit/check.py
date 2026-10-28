"""Offline generation, exact-cache and independently observed bin proof."""
import json,struct,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
for command in [[HERE/'generate.py','--check'],[HERE/'record_modes.py','--check','--cases','target-occupancy-audit/cases.jsonc','--output','target-occupancy-audit/records.json'],[HERE/'record_modes.py','--check','--cases','target-occupancy-audit/mode6-cases.jsonc','--output','target-occupancy-audit/mode6-records.json'],[HERE.parent/'record_traces.py','--check','--cases','target-occupancy-audit/cases.jsonc','--output','target-occupancy-audit/traces.json']]:subprocess.run([sys.executable,*map(str,command)],check=True)
a=json.loads((HERE/'records.json').read_text())['records'];b=json.loads((HERE/'mode6-records.json').read_text())['records']
assert len(a)==len(b)==27
for x,y in zip(a,b):assert x['id']==y['id']and x['result']==y['result'],x['id']
last=[92,92,48,47,90,92,32,18,17,32,11,7,11,11,7,11,4,5,8,14,2,4,4,94,94,48,47]
traces=json.loads((HERE/'traces.json').read_text())['records']
for record,expected in zip(traces,last):
 moves=[m for p in record['collisions']for phase in p if phase.get('phase')=='3'for m in phase['moves']]
 assert len(moves)==1
 occupied=[s['i']for s in moves[0]['slices']if abs(s['targetEdge'])<1e30]
 assert max(occupied)==expected,(record['id'],max(occupied),expected)
print('27 mode pairs and target-upper trace boundaries pass offline')
