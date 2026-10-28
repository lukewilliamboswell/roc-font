"""Offline reference-key and causal-witness checks; standard library only."""
import hashlib,json
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
canonical=lambda value:json.dumps(value,sort_keys=True,separators=(',',':')).encode()
sha=lambda data:hashlib.sha256(data).hexdigest()

def check(cases_file,records_file):
    cases=json.loads((HERE/cases_file).read_text())['cases']
    saved=json.loads((HERE/records_file).read_text())
    assert len(cases)==len(saved['records'])==1
    for case,record in zip(cases,saved['records']):
        assert case['id']==record['id']
        assert record['key']==sha(canonical({'case':case,'font':sha((ROOT/case['font']).read_bytes()),'oracle':saved['oracle']}))
    return saved['records'][0]

zero=check('cases.jsonc','records.json')
six=check('mode6-cases.jsonc','mode6-records.json')
check('cases.jsonc','traces.json')
check('cases.jsonc','public-records.json')
assert zero['result']==six['result']
proof=json.loads((HERE/'before-proof.json').read_text())
assert proof['font_sha256']==sha((HERE/'negative-window-three.ttf').read_bytes())
assert proof['expected']['glyphs']!=proof['actual_before']['glyphs']
assert proof['reference_trace_sha256']==sha((HERE/'traces.json').read_bytes())
assert proof['source_predicate']['near_forbidden_x']==[-983,317]
assert proof['source_predicate']['far_forbidden_x']==[-2267,-967]
print('One neutral-preload negative-window witness and four independent cache keys pass')
