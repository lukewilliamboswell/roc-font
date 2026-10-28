#!/usr/bin/env python3
"""Measure format-3 GPOS anchor preparation at three increasing sizes.

Uses the standard optimized public-bundle read benchmark, allocation counter,
and native HarfBuzz comparator. The generated fonts differ only in glyph/mark
count. Run once before and once after a preparation change. Requested/peak
allocation bytes are unavailable in roc-fuzz 0.4.3.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import bench
import flight


def font(count):
    from fontTools.ttLib import TTFont
    names = ['.notdef', 'base'] + [f'm{i}' for i in range(count)]
    marks = ' '.join(names[2:])
    features = f'markClass [{marks}] <anchor 0 0> @M; feature mark {{ pos base base <anchor 100 600> mark @M; }} mark;'
    raw = bench._build_font(names, {97: 'base'} | {0x300+i: name for i, name in enumerate(names[2:])}, features)
    parsed = TTFont(io.BytesIO(raw))
    sub = parsed['GPOS'].table.LookupList.Lookup[0].SubTable[0]
    anchors = [m.MarkAnchor for m in sub.MarkArray.MarkRecord]
    anchors += [a for b in sub.BaseArray.BaseRecord for a in b.BaseAnchor if a]
    for anchor in anchors:
        anchor.Format = 3
        anchor.XDeviceTable = None
        anchor.YDeviceTable = None
    parsed.recalcTimestamp = False
    out = io.BytesIO()
    parsed.save(out)
    return out.getvalue()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--roc', default=os.environ.get('ROC', 'roc'))
    ap.add_argument('--harfbuzz', type=Path, required=True)
    ap.add_argument('--alloc', type=Path, required=True)
    ap.add_argument('--binary', type=Path, help='reuse an optimized bundle benchmark already built')
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    assert bench.fonttools_version() == bench.FONTTOOLS_PIN, "use pinned fontTools"
    with tempfile.TemporaryDirectory(prefix='position-prep-') as temp:
        work = Path(temp)
        binary = args.binary or work / 'roc-font'
        if args.binary is None:
            with flight.flight(args.roc, work=work) as dep:
                subprocess.run([args.roc, 'build', '--opt=speed', str(ROOT/'bench/roc/font.roc'), f'--output={binary}', *dep], cwd=ROOT, check=True)
        results = []
        for count in (8, 64, 256):
            raw = font(count)
            case = b'read\n' + str(len(raw)).encode() + b'\n' + raw
            path = work / f'{count}.case'
            path.write_bytes(case)
            allocation = bench.count_allocations(args.alloc, path, 120)
            assert allocation.get('result') == 'ok', allocation
            times = {}
            for name, command in [('roc', binary), ('harfbuzz', args.harfbuzz)]:
                bench.run_once([str(command)], case, 50, 120)
                samples = [bench.run_once([str(command)], case, 200, 120)['elapsed_ns']/200 for _ in range(3)]
                times[name] = bench.summarize(samples)
            results.append({'marks': count, 'font_sha256': hashlib.sha256(raw).hexdigest(), 'allocation': allocation, 'times_ns': times, 'roc_over_harfbuzz': times['roc']['median_ns']/times['harfbuzz']['median_ns']})
            print(json.dumps(results[-1]), flush=True)
        args.output.write_text(json.dumps({'cases': results, 'compiler': subprocess.check_output([args.roc, 'version'], text=True).strip(), 'native_binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(), 'allocation_binary_sha256': hashlib.sha256(args.alloc.read_bytes()).hexdigest(), 'reference_binary_sha256': hashlib.sha256(args.harfbuzz.read_bytes()).hexdigest(), 'memory_bytes': 'unavailable in roc-fuzz 0.4.3'}, indent=2)+'\n')


if __name__ == '__main__':
    main()
