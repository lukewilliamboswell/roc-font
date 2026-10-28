"""Select accepted original geometry fonts for the public HB14.6 oracle.

Raw-slot records retain rejected-face and collision-attribute witnesses. This
matrix compares the positioned glyph runs exposed by roc-font's public API.
"""
import argparse
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
SETS = [
    ('geometry-cases.jsonc', 'geometry-records.json'),
    ('collision-cases.jsonc', 'collision-records.json'),
    ('collision-box-cases.jsonc', 'collision-box-records.json'),
    ('kerning-audit/cases.jsonc', 'kerning-audit/records.json'),
    ('sequencing-audit/cases.jsonc', 'sequencing-audit/records.json'),
    ('retry-audit/cases.jsonc', 'retry-audit/records.json'),
    ('association-audit/cases.jsonc', 'association-audit/records.json'),
    ('broad-audit/cases.jsonc', 'broad-audit/records.json'),
    ('child-advance/cases.jsonc', 'child-advance/records.json'),
    ('attachment-state/cases.jsonc', 'attachment-state/records.json'),
    ('kern-parts/cases.jsonc', 'kern-parts/records.json'),
    ('segment-origin/cases.jsonc', 'segment-origin/records.json'),
    ('benchmark/cases.jsonc', 'benchmark/records.json'),
    ('first-cell-audit/cases.jsonc', 'first-cell-audit/records.json'),
    ('phase3-space-audit/cases.jsonc', 'phase3-space-audit/records.json'),
    ('benchmark-shift/cases.jsonc', 'benchmark-shift/records.json'),
    ('benchmark-sequence/cases.jsonc', 'benchmark-sequence/records.json'),
    ('benchmark-prefix/cases.jsonc', 'benchmark-prefix/records.json'),
    ('negative-window-audit/cases.jsonc', 'negative-window-audit/records.json'),
    ('kern-frame-audit/cases.jsonc', 'kern-frame-audit/records.json'),
    ('attachment-lifetime-audit/cases.jsonc', 'attachment-lifetime-audit/records.json'),
    ('prior-overlap-audit/cases.jsonc', 'prior-overlap-audit/records.json'),
    ('deleted-leaf-audit/cases.jsonc', 'deleted-leaf-audit/records.json'),
    ('deleted-sibling-audit/cases.jsonc', 'deleted-sibling-audit/records.json'),
    ('deleted-metric-audit/cases.jsonc', 'deleted-metric-audit/records.json'),
    ('downstream-gap-audit/cases.jsonc', 'downstream-gap-audit/records.json'),
    ('benchmark-deleted-attachment/cases.jsonc', 'benchmark-deleted-attachment/records.json'),
    ('kern-eligibility-audit/cases.jsonc', 'kern-eligibility-audit/records.json'),
    ('benchmark-kern-frame/cases.jsonc', 'benchmark-kern-frame/records.json'),
    ('target-occupancy-audit/cases.jsonc', 'target-occupancy-audit/records.json'),
    ('rightup-audit/cases.jsonc', 'rightup-audit/records.json'),
    ('broad-extra-audit/cases.jsonc', 'broad-extra-audit/records.json'),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    cases, rejected = [], []
    seen = set()
    for case_path, record_path in SETS:
        records = {r['id']: r for r in json.loads((HERE / record_path).read_text())['records']}
        for original in json.loads((HERE / case_path).read_text())['cases']:
            key = original['id']
            assert key not in seen, key
            seen.add(key)
            if not records[key]['result']['face_accepted']:
                rejected.append({'id': key, 'source': case_path, 'font': original['font']})
                continue
            cases.append({
                'id': key,
                'font': original['font'],
                'text': original['text'],
                'direction': original['direction'],
                'script': original.get('script', 'Latn'),
                'source': case_path,
            })
    output = {'schema': 1, 'about': 'Original geometry fonts, accepted reference faces; public HB14.6 Graphite2 glyph-run oracle.', 'cases': cases, 'raw_reader_witnesses': rejected}
    text = json.dumps(output, ensure_ascii=False, indent=2) + '\n'
    path = HERE / 'public-cases.jsonc'
    if args.check:
        assert path.read_text() == text, 'public case selection is stale'
    else:
        path.write_text(text)
    print(f'{len(cases)} public geometry cases; {len(rejected)} rejected reference faces retained as raw reader witnesses')


if __name__ == '__main__':
    main()
