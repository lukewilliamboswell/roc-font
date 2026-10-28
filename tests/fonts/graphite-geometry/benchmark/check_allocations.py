"""Exact feature allocation ratchet for an artifact-built public shape_alloc.

The caller supplies the native binary built through the served dependency in a
source-sentinel mirror. This checker never compiles package source or loads an
oracle library. Cached checksums came from paired pinned-HB measurements.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
HERE = Path(__file__).resolve().parent

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', required=True, type=Path)
    parser.add_argument('--baseline', type=Path, default=HERE/'allocation-baseline.json')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve()
    baseline = json.loads(args.baseline.read_text())
    rows = []
    with tempfile.TemporaryDirectory(prefix='roc-graphite-alloc-') as temp:
        for case in baseline['cases']:
            data = (HERE/case['font']).read_bytes()
            assert hashlib.sha256(data).hexdigest() == case['font_sha256'], case['id']
            for expected in case['rows']:
                name = f"{case['id']}-{expected['copies']}"
                path = Path(temp)/(name+'.case')
                header = f"{case['script']}\t{case['direction']}\t{expected['copies']}\t{case['text']}\n"
                path.write_bytes(header.encode()+data)
                run = subprocess.run([str(binary),'replay',str(path)],capture_output=True,text=True,timeout=180)
                match = re.search(r'ALLOCATION_DIAGNOSTIC allocations=(\d+) leaked=(\d+) result=ok checksum=(\d+)',run.stdout+run.stderr)
                assert run.returncode == 77 and match, (name,run.returncode,run.stdout,run.stderr)
                actual = {'allocations':int(match[1]),'leaked':int(match[2]),'output_checksum':int(match[3])}
                wanted = {key:expected[key] for key in actual}
                rows.append({'id':name,**actual,'passed':actual == wanted})
    report = {'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'baseline_sha256':hashlib.sha256(args.baseline.read_bytes()).hexdigest(),'rows':rows,'passed':all(row['passed'] for row in rows),'requested_bytes':None,'peak_live_bytes':None}
    if args.output:
        args.output.write_text(json.dumps(report,indent=2)+'\n')
    for row in rows:
        if not row['passed']:
            print('CHANGED',row)
    print(f"{sum(row['passed'] for row in rows)}/{len(rows)} exact allocation/checksum ratchets pass")
    return 0 if report['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
