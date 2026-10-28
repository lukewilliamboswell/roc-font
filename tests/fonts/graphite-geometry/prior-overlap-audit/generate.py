"""Original UPL prior-offset gate challenges; documented formats/API only."""
import argparse
import importlib.util
import io
import json
from pathlib import Path
import struct
import sys
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
spec = importlib.util.spec_from_file_location('original_frame', HERE.parent / 'kern-frame-audit/generate.py')
frame = importlib.util.module_from_spec(spec)
spec.loader.exec_module(frame)
g = frame.base.geo

def recipes():
    for prior in [100, 300, 414, 415, 416, 500, 600, 800]:
        yield {'name': f'y-offset-{prior}', 'kind': 'y', 'height': 600, 'relative_y': 170, 'margin': 0, 'desired_prior': prior, 'first_upper': 1000}
    for height in [300, 900]:
        for relative in [80, 300]:
            for margin in [10, 30]:
                edge = (1000 + margin - relative) // 2
                for prior in [edge, edge + 1]:
                    yield {'name': f'y-h{height}-r{relative}-m{margin}-p{prior}', 'kind': 'y', 'height': height, 'relative_y': relative, 'margin': margin, 'desired_prior': prior, 'first_upper': 2000}
    for prior in [-885, -886]:
        yield {'name': f'y-negative-{prior}', 'kind': 'y', 'height': 600, 'relative_y': 170, 'margin': 0, 'desired_prior': prior, 'first_upper': 2000}
    for margin, prior in [(0, 460), (0, 461), (10, 465), (10, 466), (0, -1380), (0, -1381), (10, -1390), (10, -1391)]:
        yield {'name': f'x-m{margin}-p{prior}', 'kind': 'x', 'margin': margin, 'desired_prior': prior}
    for relation in ['attached', 'independent']:
        yield {'name': 'structure-' + relation, 'kind': 'structure', 'relation': relation}
    for expression in ['baseline', 'constant', 'before', 'after', 'target-before', 'target-after']:
        yield {'name': 'capture-' + expression, 'kind': 'capture', 'expression': expression}

def raw(font, tag, data):
    table = DefaultTable(tag)
    table.data = bytes(data)
    font[tag] = table

def initial(name, flags, boxes, margin):
    data, _ = frame.make({'name': name, 'flags': flags, 'boxes': boxes, 'promotion': 0, 'rtl': False, 'margin': margin})
    return TTFont(io.BytesIO(data), recalcTimestamp=False)

def first_limits(font, limits):
    glat = bytearray(font.getTableData('Glat'))
    gloc = font.getTableData('Gloc')
    for glyph in range(font['maxp'].numGlyphs):
        start = struct.unpack_from('>H', gloc, 8 + glyph * 2)[0]
        bitmap = struct.unpack_from('>H', glat, start)[0]
        values = start + 6 + 8 * bitmap.bit_count() + 4
        struct.pack_into('>4h', glat, values + 2, *limits)
    raw(font, 'Glat', glat)

def second_action(font, action, flags, user=False):
    silf = bytearray(font.getTableData('Silf'))
    sub = struct.unpack_from('>I', silf, 12)[0]
    if user:
        meta = sub + 8 + 20 + silf[sub + 8 + 19] * 8
        silf[meta + 2] = 1  # One declared user attribute, attr22 aliases index0.
    offsets = sub + struct.unpack_from('>H', silf, sub + 4)[0]
    second = struct.unpack_from('>I', silf, offsets + 4)[0]
    payload = bytearray(g.program(action + bytes([0x32]), True, (1, 2, 3))[84:])
    payload[0] = flags
    for at in [8, 12, 16]:
        struct.pack_into('>I', payload, at, struct.unpack_from('>I', payload, at)[0] + second - 68)
    silf = silf[:sub + second] + payload
    struct.pack_into('>I', silf, offsets + 8, len(silf) - sub)
    raw(font, 'Silf', silf)

def make(r):
    name = 'prior-overlap-' + r['name']
    if r['kind'] == 'y':
        height, relative, margin, prior = (r[k] for k in ['height', 'relative_y', 'margin', 'desired_prior'])
        obstacle = [0, 0, 300, prior] if prior > 0 else [0, height + prior, 300, height + prior + 600]
        font = initial(name, [2, 1, 0], [frame.SMALL, [0, 0, 300, height], obstacle], margin)
        first_limits(font, [-1, 0 if prior > 0 else -2000, 1, r['first_upper'] if prior > 0 else 0])
        action = g.attach(1) + g.set_attr(4, relative + 30) + g.set_attr(57, 0) + g.NEXT + g.set_attr(59, -1000) + g.set_attr(61, 1000) + g.NEXT + g.set_attr(57, 2)
        second_action(font, action, 1)
    elif r['kind'] == 'x':
        margin, prior = r['margin'], r['desired_prior']
        obstacle = [0, 0, prior - 100, 600] if prior > 0 else [prior + 200, 0, 1000, 600]
        font = initial(name, [2, 1, 0], [frame.SMALL, frame.SMALL, obstacle], margin)
        first_limits(font, [0 if prior > 0 else -2000, -1, 2000 if prior > 0 else 0, 1])
        action = g.attach(1) + g.set_attr(57, 0) + g.NEXT + g.set_attr(58, -1000) + g.set_attr(60, 1000) + g.NEXT + g.set_attr(57, 2)
        second_action(font, action, 1)
    else:
        font = initial(name, [0, 1, 0], [frame.SMALL] * 3, 10)
        base = g.attach(1) + g.set_attr(57, 0)
        if r['kind'] == 'structure':
            action = base if r['relation'] == 'attached' else g.set_attr(0, 0) + g.set_attr(20, 80) + g.set_attr(21, 770) + g.NEXT + g.set_attr(0, 180)
            second_action(font, action, 9)
        else:
            store = bytes([0x23, 22])
            read = bytes([0x28, 19, 0])
            target_read = bytes([0x28, 19, 1])
            action = {'baseline': base, 'constant': base + bytes([1, 123]) + store, 'before': read + store + base, 'after': base + read + store, 'target-before': target_read + store + base, 'target-after': base + target_read + store}[r['expression']]
            second_action(font, action, 9, user=True)
    output = io.BytesIO()
    font.save(output, reorderTables=True)
    return output.getvalue()

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--check', action='store_true')
    a = p.parse_args()
    def emit(path, data):
        if a.check:
            assert path.read_bytes() == data, path
        else:
            path.write_bytes(data)
    cases = []
    for r in recipes():
        name = 'collision-prior-overlap-' + r['name']
        emit(HERE / (name + '.ttf'), make(r))
        cases.append({'id': name, 'font': 'prior-overlap-audit/' + name + '.ttf', 'text': 'abc', 'direction': 'ltr', 'script': 'Latn', 'face_options': 0, 'positioning': True, 'precontext': 0, 'recipe': r})
    assert len(cases) == 42
    for mode, filename in [(0, 'cases.jsonc'), (6, 'mode6-cases.jsonc')]:
        emit(HERE / filename, (json.dumps({'schema': 1, 'cases': [dict(c, face_options=mode) for c in cases]}, indent=2) + '\n').encode())
    print('42 original prior-overlap controls ' + ('reproduced' if a.check else 'generated'))
if __name__ == '__main__':
    main()
