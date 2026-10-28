"""Ratchet narrow native feature costs in bench/baseline.json.

Standard library only. Every allocation consumer imports the served bundle
in a source-sentinel mirror. Timing/reference evidence is recorded by the
adjacent benchmark runners; this check measures allocation calls and leaks.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import flight

ROOT = Path(__file__).resolve().parents[1]
WORK = flight.TMP_ROOT / 'feature-allocations'
SOURCES = {
    'cff': 'tests/fonts/cff/alloc.roc',
    'variation': 'bench/variation-complete/alloc.roc',
    'vertical': 'bench/vertical/alloc.roc',
    'aat-position': 'bench/aat-position/alloc.roc',
    'aat-morx': 'bench/aat-morx/alloc.roc',
    'aat-mort': 'tests/fonts/aat-mort/alloc.roc',
    'graphite-read': 'tests/fonts/graphite/read_alloc.roc',
    'graphite-shape': 'tests/fonts/graphite/shape_alloc.roc',
}

def graphite_cases():
    directory = ROOT / 'tests/fonts/graphite-geometry/benchmark'
    reference = json.loads((directory / 'allocation-baseline.json').read_text())
    for case in reference['cases']:
        path = str((directory / case['font']).resolve().relative_to(ROOT))
        for row in case['rows']:
            key = f'graphite/{case["id"]}/{row["copies"]}'
            header = f'{case["script"]}\t{case["direction"]}\t{row["copies"]}\t{case["text"]}\n'.encode()
            yield key, path, header, {**row, 'font_sha256': case['font_sha256']}

def cases():
    """The exact inputs used by the independently referenced benchmarks."""
    for key, path, header, _ in graphite_cases():
        yield 'graphite-shape', key, path, header
    for size in [16, 64, 192]:
        for mode, operation in enumerate(['read', 'shape']):
            yield 'aat-mort', f'aat-mort/{operation}/{size}', f'tests/fonts/aat-mort/scaling-{size}.ttf', bytes([mode, size // 256, size % 256])
    for size in [64, 256, 1024]:
        yield 'graphite-read', f'graphite-read/shared/{size}', f'tests/fonts/graphite/overlap-{size}.ttf', b''
    for kind in ['lines', 'blends']:
        for size in [16, 64, 256]:
            path = f'tests/fonts/cff/{kind}-{size}-cff{1 if kind == "lines" else 2}.otf'
            for mode, operation in enumerate(['read', 'extents', 'outline']):
                yield 'cff', f'cff/{kind}/{operation}/{size}', path, bytes([mode])
    for kind, sizes in [('sparse', [4, 64, 512]), ('all', [4, 64, 512]), ('axes', [8, 32, 128]), ('avar', [8, 32, 128])]:
        for size in sizes:
            prefix = 'axes' if kind == 'axes' else 'avar-regions' if kind == 'avar' else 'phantom-' + kind
            header = b'axis\n' if kind == 'axes' else b'avar\n' if kind == 'avar' else b'phantom\n'
            yield 'variation', f'variation/{kind}/{size}', f'tests/fonts/variation-complete/{prefix}-{size}.ttf', header
    for mode, name, path in [(0, 'jp', 'tests/fonts/vertical/VerticalSansJP.ttf'),
                             (1, 'positioning', 'tests/fonts/vertical/gpos.ttf'),
                             (2, 'mong', 'tests/fonts/shaping/use-joining/UseMongolianSans.ttf')]:
        for copies in [16, 64, 256]:
            yield 'vertical', f'vertical/{name}/{copies}', path, f'{mode}{copies}\n'.encode()
    for name in ['kerx0', 'kerx1', 'kerx4-coordinate']:
        for copies in [8, 64, 256]:
            yield 'aat-position', f'aat-position/{name}/{copies}', f'tests/fonts/aat-position/{name}.ttf', f'{copies}\n'.encode()
    for mode, name in enumerate(['direct', 'context', 'ligature', 'insertion', 'rearrange', 'tracking', 'tamil']):
        file = {'tracking': 'tracking-1--65536.ttf', 'tamil': 'NotoSansTamilMN.ttf'}.get(name, name + '-logical.ttf')
        for copies in [16, 64, 256]:
            yield 'aat-morx', f'aat-morx/{name}/{copies}', f'tests/fonts/aat/{file}', f'{mode}{copies}\n'.encode()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--update', action='store_true', help='explicitly record current counts and input hashes')
    parser.add_argument('--no-build', action='store_true', help='reuse binaries from the preceding invocation')
    parser.add_argument('--only', choices=tuple(SOURCES), action='append')
    args = parser.parse_args()
    roc = os.environ.get('ROC', 'roc')
    WORK.mkdir(parents=True, exist_ok=True)
    selected = set(args.only or SOURCES)
    baseline_path = ROOT / 'bench/baseline.json'
    baseline = json.loads(baseline_path.read_text())
    expected = baseline.setdefault('feature_cases', {})
    actual = {}
    failures = []
    graphite_reference = {key: row for key, _, _, row in graphite_cases()}
    mirror = ROOT if (ROOT / 'package/main.roc').read_text() == flight.SENTINEL else flight.make_mirror(WORK / 'mirror')
    with flight.flight(roc, work=WORK / 'flight') as dep:
        metadata = {'bundle': dep[-1].rsplit('/', 1)[-1], 'source_sentinel': True,
                    'roc': subprocess.check_output([roc, 'version'], text=True).strip(),
                    'reused_binaries': args.no_build, 'requested_bytes': None, 'peak_live_bytes': None}
        for group, source in SOURCES.items():
            if group not in selected:
                continue
            binary = WORK / group
            build_record = WORK / (group + '.build.json')
            if not args.no_build:
                command = [roc, 'build', '--fuzz', '--opt=speed', source, f'--output={binary}', *dep]
                done = subprocess.run(command, cwd=mirror, capture_output=True, text=True)
                if done.returncode:
                    failures.append(f'{group}: build failed\n{done.stdout}\n{done.stderr}')
                    continue
                build_record.write_text(json.dumps({'bundle': metadata['bundle'], 'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest()}) + '\n')
            else:
                built = json.loads(build_record.read_text()) if build_record.exists() else {}
                if built.get('bundle') != metadata['bundle'] or built.get('binary_sha256') != hashlib.sha256(binary.read_bytes()).hexdigest():
                    failures.append(f'{group}: reused binary does not identify the current immutable bundle; rebuild')
                    continue
            for kind, key, path, header in cases():
                if kind != group:
                    continue
                font = (ROOT / path).read_bytes()
                data = header + font
                file = WORK / (key.replace('/', '-') + '.input')
                file.write_bytes(data)
                done = subprocess.run([str(binary), 'replay', str(file)], capture_output=True, text=True, timeout=120)
                output = done.stdout + done.stderr
                diagnostic = re.search(r'ALLOCATION_DIAGNOSTIC allocations=(\d+)(?: leaked=(\d+))?.*?checksum=([^\s]+)', output)
                if done.returncode != 77 or diagnostic is None or (group not in ('cff', 'aat-mort') and diagnostic[2] is None):
                    failures.append(f'{key}: invalid diagnostic (exit {done.returncode})\n{output[-2000:]}')
                    continue
                # The CFF transport traps a leak before emitting its marker;
                # other transports include the live-allocation difference.
                row = {'allocations': int(diagnostic[1]), 'leaked': int(diagnostic[2] or 0),
                       'checksum': diagnostic[3], 'font_sha256': hashlib.sha256(font).hexdigest(),
                       'case_sha256': hashlib.sha256(data).hexdigest()}
                actual[key] = row
                if group == 'graphite-shape' and row['font_sha256'] != graphite_reference[key]['font_sha256']:
                    failures.append(f'{key}: input font differs from the independently referenced fixture')
                elif group == 'graphite-shape' and row['checksum'] != str(graphite_reference[key]['output_checksum']):
                    failures.append(f'{key}: output differs from the cached independent reference checksum')
                elif row['leaked']:
                    failures.append(f'{key}: leaked {row["leaked"]} allocations')
                elif args.update:
                    if expected.get(key) != row:
                        print(f'{key}: {expected.get(key, {}).get("allocations", "new")} -> {row["allocations"]}', flush=True)
                    expected[key] = row
                elif expected.get(key) != row:
                    failures.append(f'{key}: allocation contract changed; expected {expected.get(key)}, got {row}. Record an explicit baseline update.')
        (WORK / 'report.json').write_text(json.dumps({'metadata': metadata, 'cases': actual, 'failures': failures}, indent=2) + '\n')
    if args.update and not failures:
        baseline_path.write_text(json.dumps(baseline, indent=2, sort_keys=True) + '\n')
    for failure in failures:
        print(failure)
    print(f'{len(actual)} feature allocation cases; {len(failures)} failures; report {WORK / "report.json"}')
    return bool(failures)

if __name__ == '__main__':
    raise SystemExit(main())
