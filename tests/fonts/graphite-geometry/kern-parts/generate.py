"""Original UPL phase3 subbox controls from documented Glat3 fields."""
import argparse
import importlib.util
import io
import json
from pathlib import Path
import struct
from fontTools.ttLib import TTFont

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('original_kerning', HERE.parent / 'kerning-audit/generate.py')
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
PARTS = {
    'full': [[0,255,0,255,0,255,0,255]],
    'left': [[0,127,0,255,0,255,0,255]],
    'right': [[127,255,0,255,0,255,0,255]],
    'bottom': [[0,255,0,127,0,255,0,255]],
    'top': [[0,255,127,255,0,255,0,255]],
    'split': [[0,100,0,255,0,255,0,255], [155,255,0,255,0,255,0,255]],
}


def make(label, rtl, parts_by_glyph):
    data, programs = base.make(label, {}, rtl)
    font = TTFont(io.BytesIO(data), recalcTimestamp=False)
    glat, gloc = font.getTableData('Glat'), font.getTableData('Gloc')
    offsets = struct.unpack_from('>4H', gloc, 8)
    prepared, starts = bytearray(glat[:8]), []
    for glyph in range(3):
        starts.append(len(prepared))
        parts = parts_by_glyph.get(glyph, [])
        prepared += struct.pack('>H', (1 << len(parts)) - 1) + bytes([0,255,0,255])
        for part in parts:
            prepared += bytes(part)
        prepared += glat[offsets[glyph] + 6:offsets[glyph + 1]]
    starts.append(len(prepared))
    base.raw(font, 'Glat', prepared)
    base.raw(font, 'Gloc', gloc[:8] + struct.pack('>4H', *starts))
    output = io.BytesIO()
    font.save(output, reorderTables=True)
    return output.getvalue(), programs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    cases = []
    for rtl in (False, True):
        for glyph in range(3):
            for label, parts in PARTS.items():
                key = f'collision-kern-parts-g{glyph}-{label}-' + ('rtl' if rtl else 'ltr')
                data, programs = make(key, rtl, {glyph: parts})
                path = HERE / (key + '.ttf')
                if args.check:
                    assert path.read_bytes() == data, path
                else:
                    path.write_bytes(data)
                cases.append({'id': key, 'font': 'kern-parts/' + path.name, 'text': 'ab', 'direction': 'rtl' if rtl else 'ltr', 'script': 'Arab' if rtl else 'Latn', 'action': list(programs[0]), 'parts_by_glyph': {str(glyph): parts}})
    text = json.dumps({'schema': 1, 'cases': cases}, indent=2) + '\n'
    path = HERE / 'cases.jsonc'
    if args.check:
        assert path.read_text() == text
    else:
        path.write_text(text)
    print(f'{len(cases)} phase3 part controls reproduce')


if __name__ == '__main__':
    main()
