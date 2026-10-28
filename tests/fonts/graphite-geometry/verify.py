"""Replay original geometry fonts through the served public package.

The generic native query uses only Font. Expected runs are direct pinned
HB14.6/Graphite2 results, distinct from the raw public Graphite2 slot traces.
"""
import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import flight


def sha(data):
    return hashlib.sha256(data).hexdigest()


def check_records(records_path, oracle_path):
    subprocess.run([sys.executable, str(HERE / 'public_cases.py'), '--check'], check=True)
    cases = json.loads((HERE / 'public-cases.jsonc').read_text())['cases']
    cached = json.loads(records_path.read_text())
    pin = json.loads(oracle_path.read_text())
    assert cached['oracle'] == pin
    assert len(cases) == len(cached['records'])
    for case, record in zip(cases, cached['records']):
        payload = {'case': case, 'font': sha((HERE / case['font']).read_bytes()), 'oracle': pin}
        key = sha(json.dumps(payload, sort_keys=True, separators=(',', ':')).encode())
        assert record['id'] == case['id'] and record['key'] == key, case['id']
    return cases, {r['id']: r['result'] for r in cached['records']}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--binary', type=Path)
    parser.add_argument('--bundle', type=Path)
    parser.add_argument('--dev', action='store_true')
    parser.add_argument('--only', default='')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--records', type=Path, default=HERE / 'public-records.json')
    parser.add_argument('--oracle', type=Path, default=HERE / 'public-oracle.json')
    parser.add_argument('--divergences', type=Path)
    args = parser.parse_args()
    cases, records = check_records(args.records, args.oracle)
    declared = {}
    independent_records = {}
    if args.divergences:
        assert args.records.resolve() == (HERE / 'public-records.json').resolve(), 'independent face0 replay must remain strict'
        assert args.oracle.resolve() == (HERE / 'public-oracle.json').resolve()
        import preload_policy
        registry = preload_policy.check(args.divergences)
        declared = {row['id']: row for row in registry['cases']}
        _, independent_records = check_records(HERE / 'face0-records.json', HERE / 'face0-oracle.json')
    if args.check:
        print(f'{len(cases)} direct public HB14.6/Graphite2 geometry records current ({args.records.name})')
        return 0
    selected = [c for c in cases if args.only in c['id']]
    assert selected, 'empty geometry selection'
    work = ROOT / '.roc-font-tmp/graphite-geometry-replay'
    work.mkdir(parents=True, exist_ok=True)
    binary = args.binary.resolve() if args.binary else work / 'query'
    provenance = {'oracle_records': args.records.name, 'oracle_sha256': sha(args.oracle.read_bytes())}
    if not args.binary:
        roc = os.environ.get('ROC', 'roc')
        with flight.flight(roc, bundle=args.bundle, work=work / 'flight') as dep:
            mirror = flight.make_mirror(work / 'mirror')
            command = [roc, 'build', *([] if args.dev else ['--opt=speed']), 'tests/fonts/graphite/query.roc', f'--output={binary}', *dep]
            built = subprocess.run(command, cwd=mirror, text=True, capture_output=True)
            if built.returncode:
                sys.stderr.write(built.stdout + built.stderr)
                return 1
            provenance.update({'bundle': dep[-1].split('/')[-1], 'compiler_sha256': sha(Path(roc).read_bytes()), 'optimized': not args.dev, 'source_sentinel': True})
    provenance['binary_sha256'] = sha(binary.read_bytes())
    grouped = collections.defaultdict(list)
    for case in selected:
        grouped[case['font']].append(case)
    actual, process_failures = {}, []
    for font, items in grouped.items():
        requests = []
        for case in items:
            fields = [case['id'], case.get('script', 'Latn'), '', case['direction'], '0', '', 'graphite2', '0', str(2**64 - 1), case['text']]
            assert all('\t' not in f and '\n' not in f for f in fields)
            requests.append('\t'.join(fields))
        run = subprocess.run([str(binary), str(HERE / font)], input='\n'.join(requests) + '\n', text=True, capture_output=True, cwd=ROOT, timeout=180)
        if run.returncode:
            process_failures.append(font)
            print('PROCESS FAILURE', font, run.stdout, run.stderr, file=sys.stderr)
            continue
        for line in run.stdout.splitlines():
            key, value = line.split('\t', 1)
            assert key not in actual, key
            actual[key] = json.loads(value)
    failures = []
    declared_cases = []
    raw_default_agree = 0
    for case in selected:
        key = case['id']
        got, raw_expected = actual.get(key), records[key]
        expected = independent_records[key] if key in declared else raw_expected
        if key in declared:
            declared_cases.append(key)
        # A NULL reference segment exposes no partial geometry. Program abort
        # agreement checks its explicit result; the query separately checks
        # determinism/alignment of Roc's returned bounded partial work.
        comparable = {k: got.get(k) for k in expected} if got else None
        if got and not expected['success']:
            comparable = {'success': got.get('success'), 'abort': got.get('abort'), 'glyphs': []}
        raw_comparable = {k: got.get(k) for k in raw_expected} if got else None
        if got and not raw_expected['success']:
            raw_comparable = {'success': got.get('success'), 'abort': got.get('abort'), 'glyphs': []}
        if raw_comparable == raw_expected:
            raw_default_agree += 1
        if got is None or got.get('budgets') or got.get('engine') != 'Graphite' or comparable != expected:
            failures.append(key)
            print('DIFFER', key, 'expected', expected, 'actual', got, file=sys.stderr)
    report = {'cases': len(selected), 'agree': len(selected) - len(failures), 'failures': failures, 'process_failures': process_failures, 'provenance': provenance, 'raw_reference_agree': raw_default_agree, 'declared_preload_cases': declared_cases}
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(f"{report['agree']}/{len(selected)} exact public geometry runs agree; {len(process_failures)} process failures; {len(declared_cases)} declared preload cases checked against independent cached facts")
    return bool(failures or process_failures)


if __name__ == '__main__':
    raise SystemExit(main())
