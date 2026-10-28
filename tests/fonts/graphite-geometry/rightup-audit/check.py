"""Check original RIGHTUP cache keys and measured signs/boundary offline."""
import hashlib,json
from pathlib import Path
HERE=Path(__file__).resolve().parent
sha=lambda data:hashlib.sha256(data).hexdigest()
canonical=lambda value:json.dumps(value,sort_keys=True,separators=(',',':')).encode()
cases=json.loads((HERE/'cases.jsonc').read_text())['cases'];assert len(cases)==20
for filename in ['records.json','traces.json']:
    saved=json.loads((HERE/filename).read_text());records={r['id']:r for r in saved['records']};assert len(records)==20
    for case in cases:assert records[case['id']]['key']==sha(canonical({'case':case,'font':sha((HERE.parent/case['font']).read_bytes()),'oracle':saved['oracle']}))
traces={r['id']:r for r in json.loads((HERE/'traces.json').read_text())['records']}
for case in cases:
    moves=[m for p in traces[case['id']]['collisions']for phase in p for m in phase.get('moves',[])]
    assert len(moves)==1
    vectors={v['direction']:v for v in moves[0]['vectors']}
    def rows(axis,tag):return [r[3]for r in vectors[axis]['removals']if r[1]==tag]
    fields=case['collision']['neighbor_fields'];a=80+fields.get('3',100);b=380+fields.get('5',-50)
    assert rows('x',-11)[0][:2]==[-1150,a]
    if b>=-1150:assert rows('x',-12)[0][:2]==[-1150,b]
    if fields.get('5')==-2000:assert rows('y',-13)[0][:2]==[-1300,20]
proof=json.loads((HERE/'oracle-proof.json').read_text())
for kind in ['records','traces']:assert proof[kind+'_sha256']==sha((HERE/(kind+'.json')).read_bytes())
assert proof['bit_identical_release_tracing_results']==20
print('20 RIGHTUP keys,positive above/below signs and explicit C-H boundary PASS')
