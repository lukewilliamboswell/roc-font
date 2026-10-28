"""Measure a caller-limit threshold through the served-bundle public query.

This diagnostic never substitutes its raised limits into a conformance gate.
Completion says nothing about agreement with the cached reference output.
The binary search reports an observed adjacent transition, not a proof that
completion is globally monotone for implementations with budget-dependent caches.
"""
from pathlib import Path
import argparse, hashlib, json, subprocess

HERE = Path(__file__).resolve().parent

def sha(data):
    return hashlib.sha256(data).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--case', default='awami/text-20/rtl/clusters-0')
    parser.add_argument('--lower', type=int, default=4096)
    parser.add_argument('--upper', type=int, default=8192)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assert 0 <= args.lower < args.upper <= 2**32 - 1
    case = next(c for c in json.loads((HERE / 'shape-cases.jsonc').read_text())['cases'] if c['id'] == args.case)
    start, end = case.get('range', [0, 2**64 - 1])
    features = ','.join(f"{f['id']}:{f['value']}" for f in case.get('features', []))
    fields = [case['id'], case.get('script', 'Latn'), case.get('language', ''), case.get('direction', 'ltr'), str(case.get('cluster_level', 0)), features, case.get('engine', 'graphite2'), str(start), str(end), case['text']]
    if case.get('variations'):
        fields.append(','.join(f"{v['tag']}:{v['value']}" for v in case['variations']))
    assert all('\t' not in f and '\n' not in f for f in fields)
    request = '\t'.join(fields) + '\n'
    binary = args.binary.resolve()
    samples = []

    def completes(factor):
        run = subprocess.run([str(binary), str(HERE / case['font']), str(factor)], input=request, text=True, capture_output=True, check=True, timeout=180)
        key, encoded = run.stdout.rstrip('\n').split('\t', 1)
        assert key == case['id']
        result = json.loads(encoded)
        assert result['abort'] == 'NoAbort'
        assert result['budgets'] in [[], ['Operations']]
        sample = {'factor': factor, 'complete': not result['budgets'], 'glyphs': len(result['glyphs']), 'budgets': result['budgets'], 'result_sha256': sha(json.dumps(result, sort_keys=True, separators=(',', ':')).encode())}
        samples.append(sample)
        print(json.dumps(sample), flush=True)
        return sample['complete']

    low, high = args.lower, args.upper
    assert not completes(low), 'lower bound already completes'
    assert completes(high), 'upper bound still exhausts Operations'
    while low + 1 < high:
        middle = low + (high - low) // 2
        if completes(middle):
            high = middle
        else:
            low = middle
    report = {'case': case['id'], 'font_sha256': sha((HERE / case['font']).read_bytes()), 'scalars': len(case['text']), 'observed_adjacent_incomplete_factor': low, 'observed_adjacent_complete_factor': high, 'binary_sha256': sha(binary.read_bytes()), 'samples': samples, 'output_agreement_claimed': False}
    args.output.write_text(json.dumps(report, indent=2) + '\n')

if __name__ == '__main__':
    main()
