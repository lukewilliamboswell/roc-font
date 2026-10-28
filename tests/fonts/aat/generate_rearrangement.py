"""Original UPL programs covering every Apple rearrangement verb and size edge."""
from pathlib import Path
import argparse, io, json, struct
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE = Path(__file__).resolve().parent
ap = argparse.ArgumentParser(); ap.add_argument('--check', action='store_true'); args = ap.parse_args()
u16 = lambda *xs: struct.pack('>' + 'H' * len(xs), *xs)
u32 = lambda *xs: struct.pack('>' + 'I' * len(xs), *xs)
def emit(name, data):
    p = HERE / name
    if args.check: assert p.read_bytes() == data, f'stale {p}'
    else: p.write_bytes(data)
cases = []
for verb in range(16):
    classes = u16(8, 1, 2, 4, 5)
    rows = [[0, 0, 0, 0, 1, 0]] * 2 + [[0, 3, 3, 3, 1, 2]]
    states = u16(*(v for row in rows for v in row))
    entries = u16(0, 0, 2, 0x8000, 0, 0x2000 | verb, 2, 0)
    program = u32(6, 16, 16 + len(classes), 16 + len(classes) + len(states)) + classes + states + entries
    sub = u32(12 + len(program), 0x30000000, 1) + program
    chain = u32(1, 16 + len(sub), 0, 1) + sub
    chain += bytes(-len(chain) % 4); chain = chain[:4] + u32(len(chain)) + chain[8:]
    font = TTFont(HERE / 'direct-logical.ttf', recalcTimestamp=False)
    morx = DefaultTable('morx'); morx.data = u32(0x00020000, 1) + chain; font['morx'] = morx
    output = io.BytesIO(); font.save(output, reorderTables=True); name = f'rearrange-verb-{verb}.ttf'; emit(name, output.getvalue())
    for text in ['ab', 'acb', 'accb', 'accccb', 'aab', 'abacb', 'a' + 'c' * 61 + 'b', 'a' + 'c' * 62 + 'b', 'a' + 'c' * 63 + 'b', 'a' + 'c' * 254 + 'b']:
        for direction in ['ltr', 'rtl', 'ttb', 'btt']:
            cases.append({'id': str(len(cases)), 'font': name, 'text': text,
                          'options': {'script': 'Latn', 'direction': direction, 'hb_options': ['--show-flags']}, 'expected': 'oracle'})
emit('rearrangement-cases.jsonc', (json.dumps({'schema': 1, 'cases': cases}, ensure_ascii=False, indent=2) + '\n').encode())
