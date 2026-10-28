"""Original UPL language-selection fixture; derived from our direct program."""
from pathlib import Path
import argparse, io, json, struct
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
u16 = lambda *v: struct.pack('>' + 'H' * len(v), *v)
u32 = lambda *v: struct.pack('>' + 'I' * len(v), *v)

def emit(name, data):
    path = HERE / name
    if args.check:
        assert path.read_bytes() == data, f'stale {path}'
    else:
        path.write_bytes(data)

font = TTFont(HERE / 'direct-logical.ttf', recalcTimestamp=False)
first = u16(8, 1, 2, 5, 6)
second = u16(8, 1, 8, 7, 8, 3, 4, 6, 7, 7, 8)
subs = u32(12 + len(first), 0x30000004, 1) + first
subs += u32(12 + len(second), 0x30000004, 2) + second
features = b''.join(u16(39, selector) + u32(flags, 0xFFFFFFFF)
                    for selector, flags in [(1, 1), (2, 2), (3, 2)])
chain = u32(0, 16 + len(features) + len(subs), 3, 2) + features + subs
chain += bytes(-len(chain) % 4)
chain = chain[:4] + u32(len(chain)) + chain[8:]
morx = DefaultTable('morx')
morx.data = u32(0x00020000, 1) + chain
font['morx'] = morx
ltag = DefaultTable('ltag')
ltag.data = u32(1, 0, 3) + u16(24, 2, 26, 5, 31, 2) + b'enen-USfr'
font['ltag'] = ltag
output = io.BytesIO()
font.save(output, reorderTables=True)
emit('language.ttf', output.getvalue())
cases = []
for language in ['en', 'EN_us', 'en-US', 'en-US-x-test', 'en-GB', 'eng', 'fr', 'fr-CA', 'de', 'en_US.utf8']:
    for text in ['', 'a', 'b', 'ab', 'aab', 'a\u0301b']:
        for direction in ['ltr', 'rtl', 'ttb', 'btt']:
            cases.append({'id': language + '-' + direction + '-' + text.encode().hex(),
                          'font': 'language.ttf', 'text': text,
                          'options': {'script': 'Latn', 'language': language,
                                      'direction': direction, 'hb_options': ['--show-flags']},
                          'expected': 'oracle'})
emit('language-cases.jsonc', (json.dumps({'schema': 1, 'cases': cases}, indent=2) + '\n').encode())
