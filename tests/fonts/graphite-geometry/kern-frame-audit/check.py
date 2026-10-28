"""Offline reproducibility and public output/trace relation checks."""
import json,struct,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
for command in [[HERE/'generate.py','--check'],[HERE/'record_modes.py','--check'],[HERE/'record_modes.py','--check','--cases','kern-frame-audit/mode6-cases.jsonc','--output','kern-frame-audit/mode6-records.json'],[HERE.parent/'record_traces.py','--check','--cases','kern-frame-audit/cases.jsonc','--output','kern-frame-audit/traces.json']]:subprocess.run([sys.executable,*map(str,command)],check=True)
a=json.loads((HERE/'records.json').read_text())['records'];b=json.loads((HERE/'mode6-records.json').read_text())['records'];assert len(a)==len(b)==55
for x,y in zip(a,b):assert x['id']==y['id']and x['result']==y['result'],x['id']
records={r['id'].removeprefix('collision-kern-frame-'):r['result']for r in a}
traces={r['id'].removeprefix('collision-kern-frame-'):[m for p in r['collisions']for phase in p if phase.get('phase')=='3'for m in phase['moves']]for r in json.loads((HERE/'traces.json').read_text())['records']}
def bounds(m):return [m['miny'],m['maxy']]
def finite(m):return [s['i']for s in m['slices']if abs(s['targetEdge'])<1e30]
for flag in [0,1,2,17]:
 assert bounds(traces[f'first-{flag}'][-1])==[-610,1210]
 assert bounds(traces[f'middle-{flag}'][-1])==[-910,1810]
assert all(bounds(m)==[-10,610]for m in traces['future-tall'])
assert bounds(traces['second-tall'][0])==[-10,610]and bounds(traces['second-tall'][-1])==[-910,1810]
assert [min(finite(traces['first-0'][-1])),max(finite(traces['first-0'][-1]))]==[91,182]
for flag in [0,1,17,2]:
 assert bounds(traces[f'child-forward-{flag}'][-1])==[-440,1380]
 assert bounds(traces[f'child-backward-{flag}'][-1])==[-10,610]
 assert traces[f'child-forward-{flag}'][-1]['xbound']==traces[f'child-backward-{flag}'][-1]['xbound']==-1327
assert bounds(traces['pass-reset'][-1])==[-10,4210]
for name in ['seed-blank','seed-point0']:
 assert bounds(traces[name][-1])==[-10,1610]
 assert [min(finite(traces[name][-1])),max(finite(traces[name][-1]))]==[151,242]
assert bounds(traces['seed-raised'][-1])==[990,1610]
bits=lambda x:struct.unpack('>I',struct.pack('>f',x))[0]
assert records['sample-0']['advance_bits'][0]==bits(508)
assert records['sample--603']['advance_bits'][0]==bits(510)
assert records['sample--607']['advance_bits'][0]==bits(508.3333435058594)
for q,last in [(128,74),(160,108),(255,139)]:
 m=traces[f'child-part-{q}'][-1];child=[s['i']for s in m['slices']if s['targetEdge']<0]
 assert max(child)==last and bounds(m)==[-10,610]
for name,first in [('lower-child--7-None',0),('lower-child--2-None',1),('lower-child-3-None',2),('lower-child--7-13',1),('lower-child-3-64',10)]:
 m=traces[name][-1];assert min(s['i']for s in m['slices']if s['targetEdge']<0)==first
assert min(finite(traces['lower-target-13'][-1]))==2
for high,last in [(-18,0),(-12,0),(-11,1),(-25,None),(-1000,None)]:
 m=traces[f'negative-upper-{high}'][-1];indices=[s['i']for s in m['slices']if s['targetEdge']<0]
 assert (max(indices)if indices else None)==last
assert not any(s['targetEdge']<0 for s in traces['negative-upper-part'][-1]['slices'])
f=lambda x:struct.unpack('>f',struct.pack('>f',x))[0]
for name,moves in traces.items():
 for m in moves:
  # These fixtures use integral authored bounds/anchors, so public logged extrema are exact.
  margin=max(10,next(c['recipe'].get('margin',10)for c in json.loads((HERE/'cases.jsonc').read_text())['cases']if c['id']=='collision-kern-frame-'+name))
  width=f(f(2*margin)/3);predicted=int(f(f(f(f(m['maxy']-m['miny']+2)/width)*1.5)+1))
  assert len(m['slices'])==predicted,(name,len(m['slices']),predicted)
control=records['promotion-prior-y-0'];promoted=records['promotion-prior-y-17']
parent=lambda r:next(s for s in r['slots']if s['glyph']==2)
child=lambda r:next(s for s in r['slots']if s['glyph']==1)
assert parent(control)['position_bits'][1]==bits(600)and child(control)['position_bits'][1]==bits(770)
assert parent(promoted)['position_bits'][1]==bits(0)and child(promoted)['position_bits'][1]==bits(170)
assert parent(control)['collision_attributes'][6]==parent(promoted)['collision_attributes'][6]==600
assert parent(promoted)['collision_attributes'][0]==81
kern=traces['promotion-prior-y-17'][-1]
assert bounds(kern)==[590,1380]and kern['target']['origin']==[0,600]and kern['target']['offsetPrev']==[0,600]
for file in ['tracing-off-records.json','tracing-on-records.json']:
 subprocess.run([sys.executable,str(HERE/'record_logging.py'),'--check','--cases','kern-frame-audit/mode6-cases.jsonc','--output','kern-frame-audit/'+file],check=True)
 saved=json.loads((HERE/file).read_text())
 for release,tracing in zip(b,saved['records']):assert release['id']==tracing['id']and release['result']==tracing['result']
for flag in [0,17]:
 r=records[f'promotion-positive-y-{flag}'];assert parent(r)['collision_attributes'][6]==600
 assert parent(r)['position_bits'][1]==bits(0 if flag==17 else 600)
 for detached in [False,True]:
  r=records[f'promotion-downstream-{flag}-{detached}'];c=next(slot for slot in r['slots']if slot['glyph']==3)
  assert c['advance_bits'][0]==bits(1100 if detached else 320)
  if not detached and flag==17:
   d=next(slot for slot in r['slots']if slot['glyph']==4);assert d['position_bits'][1]==bits(170)
print('55 exact mode pairs and independent frame/occupancy/output relations pass offline')
