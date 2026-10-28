"""Pin the narrow Graphite2 preload whole-octabox compatibility difference.

Selection uses only font bytes and independent cached references, never Roc
output. Both references stay immutable and independently verified. This script
requires no font library: it validates the specific uncompressed Glat3 shape
that the separate explicit-mode public-API audit actually distinguishes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

HERE = Path(__file__).resolve().parent


def sha(data):
    return hashlib.sha256(data).hexdigest()


def whole_only(font_bytes):
    count = struct.unpack_from('>H', font_bytes, 4)[0]
    assert 12 + 16 * count <= len(font_bytes)
    tables = {}
    for index in range(count):
        at = 12 + 16 * index
        tag = font_bytes[at:at + 4].decode('ascii')
        offset, size = struct.unpack_from('>II', font_bytes, at + 8)
        assert offset <= len(font_bytes) and size <= len(font_bytes) - offset
        tables[tag] = font_bytes[offset:offset + size]
    glat, gloc = tables['Glat'], tables['Gloc']
    assert len(glat) >= 8 and struct.unpack_from('>I', glat)[0] == 0x00030000, 'only observed Glat3 eligibility is declared'
    flags = struct.unpack_from('>I', glat, 4)[0]
    assert flags == 1, 'requires uncompressed, present whole octabox metadata'
    glyphs = struct.unpack_from('>H', tables['maxp'], 4)[0]
    gloc_flags = struct.unpack_from('>H', gloc, 4)[0]
    width = 4 if gloc_flags & 1 else 2
    assert 8 + (glyphs + 1) * width <= len(gloc)
    offsets = struct.unpack_from('>' + str(glyphs + 1) + ('I' if width == 4 else 'H'), gloc, 8)
    for start, end in zip(offsets, offsets[1:]):
        assert start <= end <= len(glat) and end - start >= 6
        assert struct.unpack_from('>H', glat, start)[0] == 0, 'any subbox anywhere, including unused glyph0, excludes this policy'
        assert glat[start + 2] <= glat[start + 3] and glat[start + 4] <= glat[start + 5], 'invalid whole diagonals are not eligible'
    return {'glat_version': 3, 'glat_flags': flags, 'glyphs': glyphs, 'subboxes_in_entire_font': 0}


def build():
    cases = json.loads((HERE / 'public-cases.jsonc').read_text())['cases']
    default = json.loads((HERE / 'public-records.json').read_text())
    independent = json.loads((HERE / 'face0-records.json').read_text())
    before = {r['id']: r for r in default['records']}
    after = {r['id']: r for r in independent['records']}
    assert default['oracle'] == json.loads((HERE / 'public-oracle.json').read_text())
    assert independent['oracle'] == json.loads((HERE / 'face0-oracle.json').read_text())
    assert default['oracle']['graphite_library_sha256'] == independent['oracle']['graphite_library_sha256']
    configuration = json.loads((HERE / 'face0-configuration.json').read_text())
    assert configuration['library_sha256'] == independent['oracle']['harfbuzz_library_sha256']
    rows = []
    for case in cases:
        key = case['id']
        data = (HERE / case['font']).read_bytes()
        for dataset, row in [(default, before[key]), (independent, after[key])]:
            canonical = json.dumps({'case': case, 'font': sha(data), 'oracle': dataset['oracle']}, sort_keys=True, separators=(',', ':')).encode()
            assert row['key'] == sha(canonical), key
        if before[key]['result'] == after[key]['result']:
            continue
        facts = whole_only(data)
        rows.append({'id': key, 'font': case['font'], 'font_sha256': sha(data), 'default_reference_key': before[key]['key'], 'independent_reference_key': after[key]['key'], 'geometry': facts, 'reason': 'Graphite2PreloadWholeOctabox'})
    evidence = ['preload-audit/cases.jsonc', 'preload-audit/records.json', 'preload-audit/traces.json', 'preload-audit/oracle-proof.json', 'face0-configuration.json']
    return {'schema': 1, 'reason': 'Graphite2PreloadWholeOctabox', 'policy': 'Preserve the font-defined whole octabox geometry. Upstream Graphite2 1.3.14 preloadGlyphs2/preloadAll6 zeros its slanted whole bounds when no glyph in the font has subboxes. The unchanged non-preloaded public reference retains the documented bounds. A part on unused glyph0 restores all modes; real-font outputs are identical across modes and receive no exception.', 'default_oracle_sha256': sha((HERE / 'public-oracle.json').read_bytes()), 'independent_oracle_sha256': sha((HERE / 'face0-oracle.json').read_bytes()), 'evidence_sha256': {name: sha((HERE / name).read_bytes()) for name in evidence}, 'cases': rows}


def check(path=HERE / 'preload-divergences.json'):
    expected = build()
    actual = json.loads(path.read_text())
    assert actual == expected, 'preload divergence registry is stale or overbroad'
    return actual


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    path = HERE / 'preload-divergences.json'
    if args.check:
        result = check(path)
    else:
        result = build()
        path.write_text(json.dumps(result, indent=2) + '\n')
    print(f"{len(result['cases'])} exact font/hash/reference-key preload differences pinned; no Roc output used")


if __name__ == '__main__':
    main()
