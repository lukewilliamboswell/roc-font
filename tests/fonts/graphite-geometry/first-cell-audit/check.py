"""Check recorded observations offline without pretending a full numeric proof."""
import hashlib,json,struct
from pathlib import Path
HERE=Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
canonical=lambda v:json.dumps(v,sort_keys=True,separators=(',',':')).encode()
for case_file,record_file in [('cases.jsonc','records.json'),('mode6-cases.jsonc','mode6-records.json'),('cases.jsonc','traces.json')]:
    cases=json.loads((HERE/case_file).read_text())['cases'];saved=json.loads((HERE/record_file).read_text());records={r['id']:r for r in saved['records']};assert len(cases)==len(records)==24
    for case in cases:assert records[case['id']]['key']==sha(canonical({'case':case,'font':sha((HERE.parent/case['font']).read_bytes()),'oracle':saved['oracle']}))
r0=json.loads((HERE/'records.json').read_text())['records'];r6=json.loads((HERE/'mode6-records.json').read_text())['records'];assert [r['result']for r in r0]==[r['result']for r in r6]
traces={r['id']:r for r in json.loads((HERE/'traces.json').read_text())['records']}
def move(name):
    rows=[m for p in traces['collision-cell-'+name]['collisions']for phase in p for m in phase.get('moves',[])];assert len(rows)==1;return rows[0]
def near(name,index):return next(s['nearEdge']for s in move(name)['slices']if s['i']==index)
for name,want in [('whole-height1',300),('part-height1',300),('whole-formal-height1',147.576),('part-formal-height1',147.576),('fractional-part-formal',100.941),('fractional-part-seeded',-29702.4),('sum245-formal',295.51),('sum246-seeded',300)]:assert near(name,1)==want,(name,near(name,1))
assert near('shifted-neighbor5',2)==297 and near('shifted-neighbor6',2)==300
assert near('combined-245-253',1)==299.902 and near('combined-part',1)==299.902
assert near('later-cell3',3)==299.98 and near('later-cell46',46)==154.098 and near('later-cell20',20)==300
for name,x in [('translated-midpoint32000',1301),('translated-midpoint31900',2301)]:
    assert move(name)['needed']==101
    result=next(r['result']for r in r0 if r['id']=='collision-cell-'+name);target=next(s for s in result['slots']if s['glyph']==1)
    assert target['position_bits'][0]==struct.unpack('>I',struct.pack('>f',x))[0]
proof=json.loads((HERE/'oracle-proof.json').read_text());assert proof['release_tracing_bit_identical']==24 and proof['mode0_mode6_bit_identical']==24
for file in ['records.json','mode6-records.json','traces.json']:assert proof[file+'_sha256']==sha((HERE/file).read_bytes())
print('24 exact scan-cell reference keys/observations; modes0/6 and release/tracing bit identity PASS')
