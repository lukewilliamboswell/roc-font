"""Record tracking through unmodified HarfBuzz14.6 OT font functions."""
from pathlib import Path
import hashlib, json
import uharfbuzz as hb
HERE = Path(__file__).resolve().parent
assert hb.version_string() == '14.6.0'
data = json.loads((HERE / 'tracking-requests.jsonc').read_text())
for case in data['cases']:
    raw = (HERE / case['font']).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == case['sha256']
    font = hb.Font(hb.Face(raw)); hb.ot_font_set_funcs(font)
    font.scale = (1000, 1000); font.ptem = case['size']
    buffer = hb.Buffer(); buffer.add_codepoints(list(map(ord, case['text'])))
    buffer.direction = case['direction']; buffer.script = 'Latn'
    hb.shape(font, buffer)
    offsets = [0]
    for char in case['text']:
        offsets.append(offsets[-1] + len(char.encode('utf-8')))
    case['expected'] = {
        'glyphs': [g.codepoint for g in (buffer.glyph_infos or [])],
        'advances': [[p.x_advance, p.y_advance] for p in (buffer.glyph_positions or [])],
        'offsets': [[p.x_offset, p.y_offset] for p in (buffer.glyph_positions or [])],
        'clusters': [offsets[g.cluster] for g in (buffer.glyph_infos or [])],
    }
data['oracle'] = {'harfbuzz': hb.version_string(), 'uharfbuzz': hb.__version__,
                  'functions': 'OpenType', 'scale': [1000, 1000], 'ptem': 'case size',
                  'clusters': 'codepoint indices converted to UTF-8 byte offsets'}
(HERE / 'tracking-cases.jsonc').write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
print(len(data['cases']), 'tracking records')
