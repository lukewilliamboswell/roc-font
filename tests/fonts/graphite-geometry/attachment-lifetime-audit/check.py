"""Offline regeneration, immutable cache keys, and independent observations."""
import json
from pathlib import Path
import struct
import subprocess
import sys
HERE = Path(__file__).resolve().parent
PREFIX = 'collision-attachment-lifetime-'
def run(script, *args):
    subprocess.run([sys.executable, '-B', str(script), *args], check=True)
run(HERE / 'generate.py', '--check')
for cases, output in [('cases.jsonc', 'records.json'), ('mode6-cases.jsonc', 'mode6-records.json'), ('mode6-cases.jsonc', 'tracing-off-records.json'), ('mode6-cases.jsonc', 'tracing-on-records.json')]:
    run(HERE / 'record.py', '--check', '--cases', 'attachment-lifetime-audit/' + cases, '--output', 'attachment-lifetime-audit/' + output)
run(HERE.parent / 'record_traces.py', '--check', '--cases', 'attachment-lifetime-audit/cases.jsonc', '--output', 'attachment-lifetime-audit/traces.json')
run(HERE / 'record_ots.py', '--check')
files = ['records.json', 'mode6-records.json', 'tracing-off-records.json', 'tracing-on-records.json']
data = [json.loads((HERE / name).read_text()) for name in files]
assert all(len(item['records']) == 23 for item in data)
for group in zip(*(item['records'] for item in data)):
    assert all(item['id'] == group[0]['id'] and item['result'] == group[0]['result'] for item in group)
    assert group[0]['result']['face_accepted'] and group[0]['result']['segment']
assert data[2]['oracle']['library_sha256'] == data[3]['oracle']['library_sha256']
assert data[2]['oracle']['logging'] is False and data[3]['oracle']['logging'] is True
records = {r['id'].removeprefix(PREFIX): r['result'] for r in data[0]['records']}
traces = {r['id'].removeprefix(PREFIX): [m for p in r['collisions'] for phase in p for m in phase.get('moves', []) if 'vectors' in m] for r in json.loads((HERE / 'traces.json').read_text())['records']}
bits = lambda value: struct.unpack('>I', struct.pack('>f', value))[0]
def position(name, glyph):
    return next(s['position_bits'] for s in records[name]['slots'] if s['glyph'] == glyph)
def at(name, glyph, x, y):
    assert position(name, glyph) == [bits(x), bits(y)], (name, glyph)
def obstacles(move):
    return set(item[0] for vector in move['vectors'] for item in vector['removals'])
# The second-pass examples are stage-dependent observations, not a structural
# rule to exclude all descendants. The pre-positioning controls below refute it.
for name in ['descendant', 'descendant-ignore']:
    assert [m['result'] for m in traces[name]] == [[0, 600], [0, 0]]
    assert obstacles(traces[name][1]) == {'slot-3'}
    at(name, 2, 0, 600)
    at(name, 1, 80, 770)
for name in ['two-level', 'two-level-ignore-middle']:
    assert [m['result'] for m in traces[name]] == [[0, 600], [0, 0]]
    assert obstacles(traces[name][1]) == {'slot-4'}
    at(name, 3, 0, 600)
    at(name, 2, 80, 770)
    at(name, 1, 160, 940)
assert obstacles(traces['ancestor'][1]) == {'slot-1', 'slot-3'}
assert obstacles(traces['siblings'][1]) == {'slot-1', 'slot-3'}
assert obstacles(traces['siblings-ignore'][1]) == {'slot-3'}
at('ancestor', 2, 80, 600)
at('siblings', 2, 80, 770)
at('siblings-ignore', 2, 80, 600)
assert obstacles(traces['pre-delete0-ignore0'][0]) == {'slot-1', 'slot-2', 'slot-4'}
assert obstacles(traces['pre-delete0-ignore1'][0]) == {'slot-2', 'slot-4'}
at('pre-delete0-ignore0', 3, 0, -430)
at('pre-delete0-ignore1', 3, 0, -430)
assert obstacles(traces['pre-delete1-ignore0'][0]) == {'slot-1', 'slot-4'}
assert obstacles(traces['pre-delete1-ignore1'][0]) == {'slot-4'}
at('pre-delete1-ignore0', 3, 0, -260)
at('pre-delete1-ignore0', 1, 160, 80)
at('pre-delete1-ignore1', 3, 0, 0)
at('pre-delete1-ignore1', 1, 160, 340)
for active in [0, 1]:
    for dead in [-5000, 0, 5000]:
        name = f'metrics-a{active}-d{dead}'
        r = records[name]
        d = r['deleted_intermediate']
        assert d['advance_bits'] == [bits(dead), bits(0)]
        assert d['position_bits'] == [bits(80), bits(170)]
        assert d['parent_glyph'] == 3 and d['child_glyph'] == 1
        assert d['attributes']['0'] == dead
        at(name, 1, 160, 340)
        at(name, 3, 0, 0)
        at(name, 4, 5080 if dead > 0 else 603, 0)
        assert r['advance_bits'] == [bits(5684 if dead > 0 else 1207), bits(0)]
    for dead in [-1, 0, 1]:
        name = f'left-a{active}-d{dead}'
        r = records[name]
        d = r['deleted_intermediate']
        assert d['advance_bits'] == [bits(dead), bits(0)]
        assert d['position_bits'] == [bits(0), bits(170)]
        assert d['attributes']['3'] == -60 and d['attributes']['8'] == 20
        at(name, 1, 80, 340)
        at(name, 3, 80, 0)
        at(name, 4, 683, 0)
        assert r['advance_bits'] == [bits(1287), bits(0)]
run(HERE / 'provenance.py', '--check')
print('23 original attachment controls: exact mode/logging equality, stage/dead-metric relations and OTS keys pass offline')
