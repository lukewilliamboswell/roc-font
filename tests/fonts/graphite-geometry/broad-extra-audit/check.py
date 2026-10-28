"""Check public reference keys and the explicitly measured attempt modes."""
import hashlib,json
from pathlib import Path
HERE=Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
canonical=lambda v:json.dumps(v,sort_keys=True,separators=(',',':')).encode()
cases=json.loads((HERE/'cases.jsonc').read_text())['cases'];assert len(cases)==14
for filename in ['records.json','traces.json']:
    saved=json.loads((HERE/filename).read_text());records={r['id']:r for r in saved['records']};assert len(records)==14
    for case in cases:assert records[case['id']]['key']==sha(canonical({'case':case,'font':sha((HERE.parent/case['font']).read_bytes()),'oracle':saved['oracle']}))
traces={r['id']:r for r in json.loads((HERE/'traces.json').read_text())['records']}
for case in cases:
    moves=[m for p in traces[case['id']]['collisions']for phase in p for m in phase.get('moves',[])];assert moves
    mode='missed'if'missed'in moves[-1]else'full';assert mode==case['recipe']['expected_mode'],case['id']
proof=json.loads((HERE/'oracle-proof.json').read_text());assert proof['release_tracing_bit_identical']==14
for file in ['records.json','traces.json']:assert proof[file+'_sha256']==sha((HERE/file).read_bytes())
print('14 independent broad keys/full-missed observations PASS; no general formula claimed')
