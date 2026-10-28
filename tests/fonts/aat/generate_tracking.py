"""Original UPL Apple tracking fixtures with independently cached HB output."""
from pathlib import Path
import argparse, hashlib, io, json, struct
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE = Path(__file__).resolve().parent
ap = argparse.ArgumentParser(); ap.add_argument('--check', action='store_true'); args = ap.parse_args()
u16 = lambda *xs: struct.pack('>' + 'H' * len(xs), *xs)
u32 = lambda *xs: struct.pack('>' + 'I' * len(xs), *xs)
i16 = lambda *xs: struct.pack('>' + 'h' * len(xs), *xs)

def emit(name, data):
    p = HERE / name
    if args.check: assert p.read_bytes() == data, f'stale {p}'
    else: p.write_bytes(data)

fonts = []
for modern in [False, True]:
    for tracks in [[0], [-65536, 65536], [65536, 131072], [-131072, -65536]]:
        font = TTFont(HERE / 'direct-logical.ttf', recalcTimestamp=False)
        del font['morx']
        name = f'tracking-{int(modern)}-{tracks[0]}.ttf'
        if modern:
            table = DefaultTable('STAT')
            table.data = u32(0x00010001) + u16(8, 1) + u32(20) + u16(0) + u32(0) + u16(2) + b'opsz' + u16(256, 0)
            font['STAT'] = table
        block = 8 + len(tracks) * 8
        h = 12; v = h + block; sizes = v + block; values = sizes + 12
        body = b''; data = b''
        for direction in [0, 1]:
            body += u16(len(tracks), 3) + u32(sizes)
            for index, track in enumerate(tracks):
                body += struct.pack('>iHH', track, 256, values + len(data))
                base = index * 30 + direction * 5
                data += i16(base - 10, base + 10, base + 40)
        table = DefaultTable('trak')
        table.data = u32(0x10000) + u16(0, h, v, 0) + body + u32(6 * 65536, 18 * 65536, 36 * 65536) + data
        font['trak'] = table
        out = io.BytesIO(); font.save(out, reorderTables=True); emit(name, out.getvalue())
        fonts.append(name)
requests = []
for name in fonts:
    for size in [0, -1, 3, 6, 9, 12, 18, 24, 36, 48]:
        for text in ['', 'a', 'ab', 'a\u0301b', 'a b']:
            for direction in ['ltr', 'rtl', 'ttb', 'btt']:
                requests.append({'id': str(len(requests)), 'font': name, 'size': size,
                                 'direction': direction, 'text': text,
                                 'sha256': hashlib.sha256((HERE / name).read_bytes()).hexdigest()})
emit('tracking-requests.jsonc', (json.dumps({'cases': requests}, indent=2, ensure_ascii=False) + '\n').encode())
