"""Offline deterministic generation, cache keys and bounded observations."""
import json
from pathlib import Path
import struct
import subprocess
import sys
HERE = Path(__file__).resolve().parent
def run(script, *args):
    subprocess.run([sys.executable, '-B', str(script), *args], check=True)
run(HERE / 'generate.py', '--check')
for cases, output in [('cases.jsonc', 'records.json'), ('mode6-cases.jsonc', 'mode6-records.json'), ('mode6-cases.jsonc', 'tracing-off-records.json'), ('mode6-cases.jsonc', 'tracing-on-records.json')]:
    run(HERE / 'record.py', '--check', '--cases', 'prior-overlap-audit/' + cases, '--output', 'prior-overlap-audit/' + output)
run(HERE.parent / 'record_traces.py', '--check', '--cases', 'prior-overlap-audit/cases.jsonc', '--output', 'prior-overlap-audit/traces.json')
run(HERE / 'record_ots.py', '--check')
files = ['records.json', 'mode6-records.json', 'tracing-off-records.json', 'tracing-on-records.json']
data = [json.loads((HERE / name).read_text()) for name in files]
assert all(len(d['records']) == 42 for d in data)
for group in zip(*(d['records'] for d in data)):
    assert all(r['id'] == group[0]['id'] and r['result'] == group[0]['result'] for r in group)
    assert group[0]['result']['face_accepted'] and group[0]['result']['segment']
assert data[2]['oracle']['library_sha256'] == data[3]['oracle']['library_sha256']
assert data[2]['oracle']['logging'] is False and data[3]['oracle']['logging'] is True
records = {r['id'].removeprefix('collision-prior-overlap-'): r['result'] for r in data[0]['records']}
bits = lambda value: struct.unpack('>I', struct.pack('>f', value))[0]
expected = {1: [bits(80), bits(770)], 2: [bits(0), bits(600)], 3: [bits(180), bits(0)]}
for name in ['structure-attached', 'structure-independent'] + ['capture-' + q for q in ['baseline', 'constant', 'before', 'after', 'target-before', 'target-after']]:
    assert {s['glyph']: s['position_bits'] for s in records[name]['slots']} == expected
attached = records['structure-attached']['slots']
independent = records['structure-independent']['slots']
assert attached[0]['links_glyph'][0] == 2 and independent[0]['links_glyph'][0] is None
assert [s['advance_bits'][0] for s in attached] == list(map(bits, [100, 100, 603]))
assert [s['advance_bits'][0] for s in independent] == list(map(bits, [0, 180, 603]))
run(HERE / 'observations.py', '--check')
run(HERE / 'provenance.py', '--check')
print('42 prior-overlap controls: exact mode/logging equality, scalar/capture relations and OTS keys pass offline')
