#!/usr/bin/env python3
"""Benchmark shared Sill spans through optimized, served public consumers.

Input I/O is outside both timers. --reuse retains immutable native artifacts;
--compare WORK interleaves their before measurements with this run.
"""
from pathlib import Path
import argparse, ctypes as C, hashlib, json, os, re, statistics, subprocess, sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import flight

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--work', type=Path, default=ROOT / '.roc-font-tmp/graphite-reader-bench')
    parser.add_argument('--bundle', type=Path)
    parser.add_argument('--reuse', action='store_true')
    parser.add_argument('--compare', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    work = args.work.resolve(); work.mkdir(parents=True, exist_ok=True)
    roc = os.environ.get('ROC', 'roc')
    if not args.reuse:
        with flight.flight(roc, bundle=args.bundle, work=work / 'flight') as dep:
            mirror = flight.make_mirror(work / 'mirror')
            for name in ['read_bench', 'read_alloc']:
                subprocess.run([roc, 'build', '--opt=speed', *(['--fuzz'] if name == 'read_alloc' else []),
                                f'tests/fonts/graphite/{name}.roc', f'--output={work/name}', *dep],
                               cwd=mirror, check=True)
            (work / 'bundle-url.txt').write_text(dep[-1] + '\n')
    library = work / 'reference.dylib'
    subprocess.run(['cc', '-O2', '-dynamiclib', '-I/opt/homebrew/include', str(HERE/'read_bench.c'),
                    '-L/opt/homebrew/lib', '-lgraphite2', '-o', str(library)], check=True)
    measure = C.CDLL(str(library)).graphite_read_elapsed
    measure.argtypes = [C.c_void_p, C.c_size_t, C.c_uint, C.POINTER(C.c_uint64)]
    measure.restype = C.c_uint64
    rows = []
    for size in [64, 256, 1024]:
        font = HERE / f'overlap-{size}.ttf'; data = font.read_bytes()
        count = 16; checksum = C.c_uint64(); samples = []
        for _ in range(5):
            sample = {}
            for label, binary in [('after', work/'read_bench'),
                                  *([('before', args.compare/'read_bench')] if args.compare else [])]:
                result = json.loads(subprocess.check_output([str(binary), str(font), str(count)], text=True))
                assert result['iterations'] == count and result['checksum'] == 3*count, result
                sample[label+'_ns'] = result['elapsed_ns']/count
            elapsed = measure(data, len(data), count, C.byref(checksum))
            assert elapsed != 2**64-1 and checksum.value == 3*count
            sample['graphite2_ns'] = elapsed/count
            for label in ['after', *(['before'] if args.compare else [])]:
                sample[label+'_ratio'] = sample[label+'_ns']/sample['graphite2_ns']
            samples.append(sample)
        run = subprocess.run([str(work/'read_alloc'), 'replay', str(font)], capture_output=True, text=True)
        match = re.search(r'ALLOCATION_DIAGNOSTIC allocations=(\d+) leaked=(\d+)', run.stdout+run.stderr)
        assert run.returncode == 77 and match, run.stdout+run.stderr
        row = {'languages': size, 'settings_each': size, 'font_bytes': len(data), 'font_sha256': digest(font),
               'allocations': int(match[1]), 'leaked': int(match[2]), 'samples': samples,
               'after_ratio': statistics.median(s['after_ratio'] for s in samples)}
        if args.compare:
            row['before_ratio'] = statistics.median(s['before_ratio'] for s in samples)
        rows.append(row); print(json.dumps(row), flush=True)
    report = {'measurement_git': subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
              'compiler': subprocess.check_output([roc,'version'],text=True).strip(),
              'compiler_sha256': digest(Path(roc)), 'bundle': (work/'bundle-url.txt').read_text().strip(),
              'binary_sha256': digest(work/'read_bench'), 'allocation_binary_sha256': digest(work/'read_alloc'),
              'graphite2_library_sha256': digest(Path('/opt/homebrew/lib/libgraphite2.dylib')),
              'rows': rows, 'requested_bytes': None, 'peak_live_bytes': None,
              'notes': ['Whole strict font preparation, including Graphite; input byte I/O excluded in both engines.',
                        'Five interleaved native samples,16 preparations each; cost and acceptance compared separately.',
                        'Pinned roc-fuzz0.4.3 exposes allocation/live call counts, not requested/peak bytes.']}
    if args.compare:
        report['before_binary_sha256'] = digest(args.compare/'read_bench')
        report['before_bundle'] = (args.compare/'bundle-url.txt').read_text().strip()
    (args.output or work/'results.json').write_text(json.dumps(report,indent=2)+'\n')

if __name__ == '__main__':
    main()
