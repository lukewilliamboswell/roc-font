"""Reproduce original UPL class/applicability regressions and real-family cases."""
from pathlib import Path
import argparse, io, json, struct
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE = Path(__file__).resolve().parent
ap = argparse.ArgumentParser(); ap.add_argument('--check', action='store_true'); args = ap.parse_args()
u16 = lambda *xs: struct.pack('>' + 'H' * len(xs), *xs)

def emit(name, data):
    p = HERE / name
    if args.check: assert p.read_bytes() == data, f'stale {p}'
    else: p.write_bytes(data)

def save(name, font):
    output = io.BytesIO(); font.save(output, reorderTables=True); emit(name, output.getvalue())

font = TTFont(HERE / 'direct-logical.ttf', recalcTimestamp=False)
table = DefaultTable('GDEF'); table.data = u16(1, 0, 12, 0, 0, 0) + u16(2, 2, 1, 2, 1, 5, 6, 3)
font['GDEF'] = table; save('gdef-classes.ttf', font)
font = TTFont(HERE / 'insertion-logical.ttf', recalcTimestamp=False)
raw = bytearray(font.getTableData('morx')); base = 36
states = base + struct.unpack_from('>I', raw, base + 8)[0]
for row in [0, 1]:
    for column in range(6): struct.pack_into('>H', raw, states + row * 12 + column * 2, 1 if column == 0 else 0)
table = DefaultTable('morx'); table.data = bytes(raw); font['morx'] = table; save('eot-only.ttf', font)

for label, name, texts in [
    ('gdef', 'gdef-classes.ttf', ['a', 'ab', 'a\u0301b', 'aba', 'aa', 'a b']),
    ('applicability', 'eot-only.ttf', ['', 'a', 'b', 'ab', 'aab', 'a\u0301b', 'a b']),
]:
    cases = []
    for text in texts:
        for direction in ['ltr', 'rtl', 'ttb', 'btt']:
            cases.append({'id': str(len(cases)), 'font': name, 'text': text,
                          'options': {'script': 'Latn', 'direction': direction, 'hb_options': ['--show-flags']},
                          'expected': 'oracle'})
    emit(label + '-cases.jsonc', (json.dumps({'schema': 1, 'cases': cases}, ensure_ascii=False, indent=2) + '\n').encode())
cases = []
for text in ['', 'தமிழ்', 'வணக்கம்', 'கா', 'கி', 'கீ', 'கு', 'கூ', 'கெ', 'கே', 'கொ', 'கோ', 'கௌ', 'க்ஷ', 'ஸ்ரீ', 'தமிழ் மொழி', 'க\u0301']:
    for language in ['ta', 'en', 'ta-IN']:
        for direction in ['ltr', 'rtl', 'ttb', 'btt']:
            cases.append({'id': str(len(cases)), 'font': 'NotoSansTamilMN.ttf', 'text': text,
                          'options': {'script': 'Taml', 'language': language, 'direction': direction, 'hb_options': ['--show-flags']},
                          'expected': 'oracle'})
emit('real-cases.jsonc', (json.dumps({'schema': 1, 'cases': cases}, ensure_ascii=False, indent=2) + '\n').encode())
