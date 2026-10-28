"""Offline reproducibility, cache-key, mode-equivalence and observation proof."""
import json,subprocess,sys,struct
from pathlib import Path
HERE=Path(__file__).resolve().parent
for command in [[HERE/'generate.py','--check'],[HERE/'record_modes.py','--check','--cases','phase3-space-audit/cases.jsonc','--output','phase3-space-audit/records.json'],[HERE/'record_modes.py','--check','--cases','phase3-space-audit/mode6-cases.jsonc','--output','phase3-space-audit/mode6-records.json'],[HERE.parent/'record_traces.py','--check','--cases','phase3-space-audit/cases.jsonc','--output','phase3-space-audit/traces.json']]:subprocess.run([sys.executable,*map(str,command)],check=True)
a=json.loads((HERE/'records.json').read_text())['records'];b=json.loads((HERE/'mode6-records.json').read_text())['records'];assert len(a)==len(b)==80
for x,y in zip(a,b):assert x['id']==y['id']and x['result']==y['result'],x['id']
records={r['id']:r['result']for r in a}
def get(shape,flags,direction):return records[f'collision-space-{shape}-{flags}-{direction}']
def target_advance(record):return next(s['advance_bits'][0]for s in record['slots']if s['glyph']==1)
for direction in ['rtl','ltr']:
 space=target_advance(get('empty',0,direction))
 for flags in [0,2,4,8,12,14,128,130,132,136,140,142]:assert target_advance(get('empty',flags,direction))==space
 for flags in [128,130,132,136,140,142]:assert target_advance(get('ink',flags,direction))==space
 for flags in [4,8,12]:assert target_advance(get('ink',flags,direction))==target_advance(get('ink',0,direction))
 assert target_advance(get('ink',2,direction))==target_advance(get('ink',14,direction))
 for shape in ['vertical','horizontal','point']:
  assert target_advance(get(shape,0,direction))!=space
  assert target_advance(get(shape,2,direction))==target_advance(get('ink',2,direction))
  for flags in [128,130]:assert target_advance(get(shape,flags,direction))==space
 for flags in [0,2,128,130]:assert target_advance(get('origin-point',flags,direction))==space
print('80 mode pairs and phase-3 observational relations pass offline')
