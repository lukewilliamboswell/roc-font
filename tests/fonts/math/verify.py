"""Replay cached MATH query oracles through the optimized native bundle consumer.

Run: ROC=/path/to/roc python3 tests/fonts/math/verify.py
No HarfBuzz, fontTools or network access is needed beyond the served bundle
and compiler platform cache. Case data and oracle records are never used to
generate Roc source. In all_tests.py's mirror, the bundle remains mandatory.
"""
from pathlib import Path
import difflib, hashlib, json, os, subprocess, sys, tempfile

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
import flight
from _common import load_jsonc


def main():
    cases=load_jsonc(HERE/'cases.jsonc')['cases']
    records=[json.loads(line) for line in (HERE/'oracle.jsonl').read_text().splitlines() if line]
    indexed={r['id']:r for r in records}
    if len(indexed)!=len(records) or set(indexed)!={c['id'] for c in cases}:
        raise SystemExit('MATH oracle case ids differ from cases.jsonc')
    for c in cases:
        actual=hashlib.sha256((HERE/c['font']).read_bytes()).hexdigest()
        if actual!=indexed[c['id']]['font_sha256']:
            raise SystemExit(f"MATH font changed: {c['font']}")
    roc=os.environ.get('ROC','roc')
    temp=ROOT/'.roc-font-tmp';temp.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='math-',dir=temp) as directory:
        work=Path(directory);binary=work/'math-queries'
        with flight.flight(roc,work=work) as dep:
            subprocess.run([roc,'build','--opt=speed',str(HERE/'query.roc'),f'--output={binary}',*dep],cwd=ROOT,check=True)
        requests=''.join(f"{c['id']}\t{HERE/c['font']}\t{c['weight']}\n" for c in cases)
        result=subprocess.run([str(binary)],input=requests,text=True,capture_output=True,cwd=ROOT,timeout=120,check=True)
        expected=[f"{c['id']}\t{fact}" for c in cases for fact in indexed[c['id']]['facts']]
        actual=result.stdout.splitlines()
        if actual!=expected:
            diff=list(difflib.unified_diff(expected,actual,fromfile='recorded MATH oracle',tofile='native bundle queries',n=2))
            print('\n'.join(diff[:160]),file=sys.stderr)
            return 1
        print(f'MATH: {len(cases)} cases, {len(expected)} native font-fact records agree (all constants, glyphs, corners, threshold neighbours and constructions).')
    return 0


if __name__=='__main__':
    raise SystemExit(main())
