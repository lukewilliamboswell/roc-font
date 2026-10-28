"""Check cached keys and independently observed relations without any oracle."""
import hashlib,json,struct,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
sha=lambda data:hashlib.sha256(data).hexdigest()
canonical=lambda v:json.dumps(v,sort_keys=True,separators=(',',':')).encode()
cases=json.loads((HERE/'cases.jsonc').read_text())['cases']
for name in ['records.json','traces.json']:
    saved=json.loads((HERE/name).read_text());records={r['id']:r for r in saved['records']}
    assert len(records)==len(cases)==224
    for case in cases:
        font=(HERE.parent/case['font']).read_bytes()
        assert records[case['id']]['key']==sha(canonical({'case':case,'font':sha(font),'oracle':saved['oracle']})),case['id']
results=json.loads((HERE/'records.json').read_text())['records']
traces=json.loads((HERE/'traces.json').read_text())['records']
changed=[]
for i in range(0,len(cases),4):
    group=results[i:i+4];assert [c['face_options']for c in cases[i:i+4]]==[0,2,4,6]
    assert group[0]['result']==group[2]['result'] and group[1]['result']==group[3]['result']
    if group[0]['result']!=group[1]['result']:changed.append(group[0]['id'].rsplit('-mode',1)[0])
    if 'real-'in group[0]['id']:assert all(t['collisions']==traces[i]['collisions']for t in traces[i:i+4])
assert changed==['collision-preload-whole-only','collision-preload-margin','collision-preload-attachment']
by_id={r['id']:r['result']for r in results}
float32=lambda bits:struct.unpack('>f',struct.pack('>I',bits))[0]
for mode,want in [(0,300),(2,100),(4,300),(6,100)]:
    assert float32(by_id['collision-preload-whole-only-mode'+str(mode)]['slots'][1]['position_bits'][0])==want
    assert float32(by_id['collision-preload-full-subbox-unused-mode'+str(mode)]['slots'][1]['position_bits'][0])==300
for metric,want in enumerate([0,302,600,0,0,300,600,300,602,0,0]):
    assert float32(by_id['collision-preload-metric-'+str(metric)+'-mode0']['slots'][1]['position_bits'][1])==want
# Public trace pins the changed geometry without guessing an engine cause.
for mode,want in [(0,[0,-600,900,300]),(2,[0,0,0,0]),(4,[0,-600,900,300]),(6,[0,0,0,0])]:
    record=next(t for t in traces if t['id']=='collision-preload-whole-only-mode'+str(mode))
    moves=[m for p in record['collisions']for phase in p for m in phase.get('moves',[])]
    assert moves[0]['target']['bbox']==[0,0,300,600]
    assert moves[0]['target']['slantBox']==want
proof=json.loads((HERE/'oracle-proof.json').read_text())
assert proof['bit_identical_result_count']==224
assert proof['release_records_sha256']==sha((HERE/'records.json').read_bytes())
assert proof['trace_records_sha256']==sha((HERE/'traces.json').read_bytes())
assert proof['tracing_result_digest']==sha(canonical([r['result']for r in results]))
print('224 explicit-mode cache keys; 3 changed original groups; 13 unchanged real groups; metrics, attributes and public geometry relations PASS')
