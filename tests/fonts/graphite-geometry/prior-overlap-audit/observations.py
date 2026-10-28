"""Derive bounded scalar comparisons from cached actual offsets, not requests."""
import argparse
import json
from pathlib import Path
HERE = Path(__file__).resolve().parent
p = argparse.ArgumentParser()
p.add_argument('--check', action='store_true')
a = p.parse_args()
cases = json.loads((HERE / 'cases.jsonc').read_text())['cases']
raw = json.loads((HERE / 'records.json').read_text())
traces = json.loads((HERE / 'traces.json').read_text())
rows = []
def obstacles(move):
    return sorted(set(item[0] for vector in move.get('vectors', []) for item in vector['removals']))
for case, record, trace in zip(cases, raw['records'], traces['records']):
    assert case['id'] == record['id'] == trace['id']
    r = case['recipe']
    moves = [m for ps in trace['collisions'] for phase in ps for m in phase.get('moves', []) if m.get('slot', m.get('missed')) == 'slot-2']
    assert len(moves) == 2
    first, second = moves
    assert first['target']['currOffset'] == [0, 0]
    slots = {s['glyph']: s for s in record['result']['slots']}
    row = {'id': case['id'], 'recipe': r, 'font_sha256': record['font_sha256'], 'raw_key': record['key'], 'trace_key': trace['key'], 'first_delta_logged': first['result'], 'second_obstacles': obstacles(second), 'second_missed': 'missed' in second, 'second_delta_logged': second.get('result'), 'final_position_bits': {str(gid): s['position_bits'] for gid, s in slots.items()}}
    if r['kind'] == 'y':
        prior = first['result'][1]
        assert prior == r['desired_prior']
        rel, margin, height = r['relative_y'], r['margin'], r['height']
        dx, dy = -80, -rel
        gate_dx, gate_dy = dx, dy - prior
        window = {'x_min': -1, 'x_max': 1, 'y_min': -1000 - prior, 'y_max': 1000 - prior}
        x_overlap = 600 - gate_dy >= window['y_min'] - margin and window['y_max'] + margin >= -gate_dy
        y_overlap = 300 - gate_dx >= window['x_min'] - margin and window['x_max'] + margin >= -gate_dx
        assert rel <= height and not y_overlap
        # Physical forbidden projectionX at orth0 is[-220,380], gap0.
        # Both arithmetic paths use exactly representable integer gate values.
        axis = 1 + (300 + margin) >= -220 and 380 + margin >= -1
        mixed = x_overlap and axis
        physical_gate = 600 - dy >= window['y_min'] - margin and window['y_max'] + margin >= -dy
        row.update(actual_prior=prior, physical_displacement=[dx, dy], gate_displacement=[gate_dx, gate_dy], window=window, x_overlap=x_overlap, y_overlap=y_overlap, physical_projection={'axis': 'X', 'low': -220, 'high': 380, 'gap': 0}, mixed_accepts=mixed, physical_gate_accepts=physical_gate and axis)
    elif r['kind'] == 'x':
        prior = first['result'][0]
        assert prior == r['desired_prior']
        margin = r['margin']
        dx, dy = -80, -170
        gate_dx, gate_dy = dx - prior, dy
        window = {'x_min': -1000, 'x_max': 1000 - prior, 'y_min': -1, 'y_max': 1}
        x_overlap = 600 - gate_dy >= window['y_min'] - margin and window['y_max'] + margin >= -gate_dy
        y_overlap = 300 - gate_dx >= window['x_min'] - margin and window['x_max'] + margin >= -gate_dx
        assert not x_overlap
        # Physical forbidden projectionY at orth0 is[-430,770], gap0.
        axis = 1 + (600 + margin) >= -430 and 770 + margin >= -1
        mixed = y_overlap and axis
        physical_gate = 300 - dx >= window['x_min'] - margin and window['x_max'] + margin >= -dx
        row.update(actual_prior=prior, physical_displacement=[dx, dy], gate_displacement=[gate_dx, gate_dy], window=window, x_overlap=x_overlap, y_overlap=y_overlap, physical_projection={'axis': 'Y', 'low': -430, 'high': 770, 'gap': 0}, mixed_accepts=mixed, physical_gate_accepts=physical_gate and axis)
    else:
        assert first['result'] == [0, 600] and second['result'] == [0, 0]
        assert obstacles(second) == ['slot-3']
        if r['kind'] == 'capture':
            expected = {'baseline': 0, 'constant': 123, 'before': 0, 'after': 770, 'target-before': 600, 'target-after': 600}[r['expression']]
            assert slots[1]['captured_user0'] == expected
            assert slots[2]['captured_user0'] == slots[3]['captured_user0'] == 0
            row['captured_A_user0'] = slots[1]['captured_user0']
    if r['kind'] in ['x', 'y']:
        assert row['physical_gate_accepts']
        assert row['mixed_accepts'] == ('slot-1' in obstacles(second)), case['id']
        assert row['second_missed'] == (not row['mixed_accepts'])
    rows.append(row)
result = {'about': 'Bounded observations only. Actual prior offsets come from the first public trace; exact final bits come from unlogged public C-ABI records. The deciding gates/projections in this matrix have exactly representable integer inputs. No general float association, diagonal projection, arbitrary overlapping-gate or numerical-bound proof is inferred.', 'raw_oracle': raw['oracle'], 'trace_oracle': traces['oracle'], 'rows': rows}
output = HERE / 'observations.json'
if a.check:
    assert json.loads(output.read_text()) == result
    print('42 bounded observations and actual-prior scalar comparisons current')
else:
    output.write_text(json.dumps(result, indent=2) + '\n')
