"""Replay cached MATH query oracles through the optimized native bundle consumer.

Run: ROC=/path/to/roc python3 tests/fonts/math/verify.py
No HarfBuzz, fontTools or network access is needed beyond the served bundle
and compiler platform cache. Case data and oracle records are never used to
generate Roc source. In all_tests.py's mirror, the bundle remains mandatory.
"""
from pathlib import Path
import argparse, difflib, hashlib, json, os, subprocess, sys, tempfile

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
import flight
from _common import load_jsonc


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--full',action='store_true',help='replay local .roc-font-tmp/math/oracle-full.jsonl; generate with oracle.py --full first')
    args=parser.parse_args()
    cases=load_jsonc(HERE/'cases.jsonc')['cases']
    record_path=ROOT/'.roc-font-tmp/math/oracle-full.jsonl' if args.full else HERE/'oracle.jsonl'
    if not record_path.is_file():
        raise SystemExit(f'Missing {record_path}; generate full records with oracle.py --full')
    records=[json.loads(line) for line in record_path.read_text().splitlines() if line]
    indexed={r['id']:r for r in records}
    if len(indexed)!=len(records) or set(indexed)!={c['id'] for c in cases}:
        raise SystemExit('MATH oracle case ids differ from cases.jsonc')
    for c in cases:
        record=indexed[c['id']]
        case_hash=hashlib.sha256(json.dumps(c,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        selection='all-glyphs' if args.full else 'checkpoints'
        if record.get('case_sha256')!=case_hash or record.get('selection')!=selection:
            raise SystemExit(f"MATH case or selection changed: {c['id']}; regenerate this oracle mode")
        if not args.full and record.get('glyphs')!=c['glyphs']:
            raise SystemExit(f"MATH checkpoint ids changed: {c['id']}")
        actual=hashlib.sha256((HERE/c['font']).read_bytes()).hexdigest()
        if actual!=indexed[c['id']]['font_sha256']:
            raise SystemExit(f"MATH font changed: {c['font']}")
    roc=os.environ.get('ROC','roc')
    temp=ROOT/'.roc-font-tmp/math';temp.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='math-',dir=temp) as directory:
        work=Path(directory);binary=work/'math-queries'
        with flight.flight(roc,work=work) as dep:
            subprocess.run([roc,'build','--opt=speed',str(HERE/'query.roc'),f'--output={binary}',*dep],cwd=ROOT,check=True)
        requests=''.join(f"{c['id']}\t{HERE/c['font']}\t{c.get('request',c['weight'])}\t"+
                         ('*' if args.full else ','.join(map(str,c['glyphs'])))+'\n' for c in cases)
        result=subprocess.run([str(binary)],input=requests,text=True,capture_output=True,cwd=ROOT,timeout=120,check=True)
        expected=[f"{c['id']}\t{fact}" for c in cases for fact in indexed[c['id']]['facts']]
        actual=result.stdout.splitlines()
        if actual!=expected:
            diff=list(difflib.unified_diff(expected,actual,fromfile='recorded MATH oracle',tofile='native bundle queries',n=2))
            print('\n'.join(diff[:160]),file=sys.stderr)
            return 1
        print(f'MATH: {len(cases)} cases, {len(expected)} native font-fact records agree ({"all glyphs" if args.full else "selected glyph checkpoints"}, all constants, corners, threshold neighbours and constructions).')
    return 0


if __name__=='__main__':
    raise SystemExit(main())
