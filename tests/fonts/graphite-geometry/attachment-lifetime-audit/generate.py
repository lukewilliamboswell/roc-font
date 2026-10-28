"""Original UPL attachment lifetime controls; public formats, no engine source."""
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
def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result
frame = module('original_frame', HERE.parent / 'kern-frame-audit/generate.py')
two = module('original_two_pass', HERE.parent / 'kerning-audit/generate.py')
geometry = frame.base.geo

def recipes():
    for relation in ['descendant', 'descendant-ignore', 'ancestor', 'siblings', 'siblings-ignore', 'two-level', 'two-level-ignore-middle']:
        yield {'name': relation, 'kind': 'family', 'relation': relation}
    for deleted in [False, True]:
        for ignored in [False, True]:
            yield {'name': f'pre-delete{int(deleted)}-ignore{int(ignored)}', 'kind': 'pre', 'deleted': deleted, 'ignored': ignored}
    for kind in ['metrics', 'left']:
        for active_advance in [0, 1]:
            for dead_advance in ([-5000, 0, 5000] if kind == 'metrics' else [-1, 0, 1]):
                yield {'name': f'{kind}-a{active_advance}-d{dead_advance}', 'kind': kind, 'deleted': True, 'active_advance': active_advance, 'dead_advance': dead_advance}

def raw(font, tag, data):
    table = DefaultTable(tag)
    table.data = bytes(data)
    font[tag] = table

def base_font(name, flags):
    data, _ = frame.make({'name': name, 'flags': flags, 'boxes': [frame.SMALL] * len(flags), 'promotion': 0, 'rtl': False})
    return TTFont(io.BytesIO(data), recalcTimestamp=False)

def replace_second(font, action, count):
    silf = bytearray(font.getTableData('Silf'))
    sub = struct.unpack_from('>I', silf, 12)[0]
    offsets = sub + struct.unpack_from('>H', silf, sub + 4)[0]
    second = struct.unpack_from('>I', silf, offsets + 4)[0]
    payload = bytearray(geometry.program(action + bytes([0x32]), True, tuple(range(1, count + 1)))[84:])
    payload[0] = 1
    for at in [8, 12, 16]:
        struct.pack_into('>I', payload, at, struct.unpack_from('>I', payload, at)[0] + second - 68)
    silf = silf[:sub + second] + payload
    struct.pack_into('>I', silf, offsets + 8, len(silf) - sub)
    raw(font, 'Silf', silf)

def make(recipe):
    name = 'attachment-lifetime-' + recipe['name']
    if recipe['kind'] == 'family':
        relation = recipe['relation']
        count = 4 if relation.startswith('two-level') else 3
        font = base_font(name, [0, 0, 1, 0] if count == 4 else [0, 1, 0])
        action = {
            'descendant': geometry.attach(1) + geometry.set_attr(57, 0),
            'descendant-ignore': geometry.attach(1) + geometry.set_attr(57, 2),
            'ancestor': geometry.NEXT + geometry.attach(-1),
            'siblings': geometry.attach(2) + geometry.NEXT + geometry.attach(1),
            'siblings-ignore': geometry.attach(2) + geometry.set_attr(57, 2) + geometry.NEXT + geometry.attach(1),
            'two-level': geometry.attach(1) + geometry.NEXT + geometry.attach(1),
            'two-level-ignore-middle': geometry.attach(1) + geometry.NEXT + geometry.attach(1) + geometry.set_attr(57, 2),
        }[relation]
        replace_second(font, action, count)
    else:
        metric = recipe['kind'] in ['metrics', 'left']
        deleted = recipe['deleted']
        font = base_font(name, [2 if metric or recipe['ignored'] else 0, 0, 1, 0])
        action = (geometry.set_attr(0, recipe['active_advance']) if metric else b'') + geometry.attach(1) + geometry.NEXT + geometry.attach(1)
        if recipe['kind'] == 'left':
            # WithX stays20: -60-20=-80. A's100-20=+80 cancels it.
            action += geometry.set_attr(3, -60)
        if metric:
            action += geometry.set_attr(0, recipe['dead_advance'])
        action += bytes([0x20]) if deleted else b''
        first = bytearray(geometry.program(action + bytes([0x32]), False, (1, 2, 3, 4)))
        first[24:26] = struct.pack('>H', 4)
        first[35] = 32
        first[49] = 1
        second = bytearray(geometry.program(bytes([0x32]), True, (1, 3, 4) if deleted else (1, 2, 3, 4)))
        second[84] = 1
        for a, b in [(24, 26), (35, 36), (48, 50)]:
            second[a:b] = first[a:b]
        silf = bytearray(two.two_pass(first, second))
        silf[32] = 1  # Pass0 substitution, pass1 positioning: DELETE is legal.
        raw(font, 'Silf', silf)
        count = 4
    output = io.BytesIO()
    font.save(output, reorderTables=True)
    return output.getvalue(), count

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    cases = []
    def emit(path, data):
        if args.check:
            assert path.read_bytes() == data, path
        else:
            path.write_bytes(data)
    for recipe in recipes():
        data, count = make(recipe)
        name = 'collision-attachment-lifetime-' + recipe['name']
        emit(HERE / (name + '.ttf'), data)
        cases.append({'id': name, 'font': 'attachment-lifetime-audit/' + name + '.ttf', 'text': 'abcd'[:count], 'direction': 'ltr', 'script': 'Latn', 'face_options': 0, 'positioning': True, 'precontext': 0, 'recipe': recipe})
    for mode, filename in [(0, 'cases.jsonc'), (6, 'mode6-cases.jsonc')]:
        emit(HERE / filename, (json.dumps({'schema': 1, 'cases': [dict(c, face_options=mode) for c in cases]}, indent=2) + '\n').encode())
    print('23 original attachment lifetime fonts ' + ('reproduced' if args.check else 'generated'))
if __name__ == '__main__':
    main()
