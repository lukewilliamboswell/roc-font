"""Validate the preserved native before/after evidence without an oracle."""
import hashlib,json
from pathlib import Path
HERE=Path(__file__).resolve().parent
proof=json.loads((HERE/'fallback-proof.json').read_text())
for field,file in [('case_file_sha256','fallback-cases.jsonc'),('oracle_records_sha256','fallback-cases-records.jsonl')]:
    assert proof[field]==hashlib.sha256((HERE/file).read_bytes()).hexdigest(),file
records={r['id']:r for r in map(json.loads,(HERE/'fallback-cases-records.jsonl').read_text().splitlines())}
assert len(records)==proof['cases']==220
for snapshot,want in zip(proof['snapshots'],[214,220]):
    assert snapshot['agree']==want and snapshot['source_sentinel']
    assert set(snapshot['answers'])==set(records)
    differing=[key for key,record in records.items()if snapshot['answers'][key]!=record['result']]
    assert sorted(differing)==sorted(f['id']for f in snapshot['failures'])
    assert len(differing)==220-want
assert proof['public_tests']['expects']==18 and proof['public_tests']['result']=='PASS'
print('220 preserved native answers:214 before,220 after;18 served-bundle public expects PASS')
