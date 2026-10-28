"""Four original GTF Glat3 flag/header controls, UPL; no engine source."""
import argparse
import io
import json
from pathlib import Path
import struct
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import generate as geometry
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    cases = []
    for flag in (0, 1):
        for header in (False, True):
            key = f'glat3-flag{flag}-header{int(header)}'
            # Documented PushGlyphAttr1(offset0), set advanceX.
            action = bytes([0x29, 1, 0, 0x23, 0])
            font = TTFont(io.BytesIO(geometry.font(key, action, True, False, 2, False)), recalcTimestamp=False)
            prefix = bytes([0, 0, 0, 255, 0, 255]) if header else b''
            entry = prefix + struct.pack('>HHhhhh', 0, 4, 0, 1, 1, 0)
            data = struct.pack('>II', 3 << 16, flag) + entry * 3
            offsets = [8 + len(entry) * i for i in range(4)]
            for tag, value in [('Glat', data), ('Gloc', struct.pack('>IHH4I', 1 << 16, 1, 4, *offsets))]:
                table = DefaultTable(tag)
                table.data = value
                font[tag] = table
            result = io.BytesIO()
            font.save(result, reorderTables=True)
            path = HERE / (key + '.ttf')
            if args.check:
                assert path.read_bytes() == result.getvalue(), path
            else:
                path.write_bytes(result.getvalue())
            cases.append({'id': key, 'font': 'glat-flags/' + path.name, 'text': 'ab', 'direction': 'ltr', 'flag': flag, 'header': header, 'authored_prefix_matches_flag': bool(flag) == header, 'action': list(action)})
    text = json.dumps({'schema': 1, 'cases': cases}, indent=2) + '\n'
    path = HERE / 'cases.jsonc'
    if args.check:
        assert path.read_text() == text
    else:
        path.write_text(text)
    print('4 Glat3 header/flag controls reproduce')


if __name__ == '__main__':
    main()
