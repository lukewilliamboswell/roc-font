"""Replay every cached color-image fact through an optimized native bundle consumer.
Uses standard-library Python only; --record requires the pinned oracle env.
"""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,sys
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
import flight

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--roc',default=os.environ.get('ROC','roc'));parser.add_argument('--record',action='store_true');parser.add_argument('--dev',action='store_true');args=parser.parse_args()
    if args.record:
        from oracle import record
        (HERE/'oracle.json').write_text(json.dumps(record(),ensure_ascii=False,indent=2)+'\n')
    cases=json.loads((HERE/'cases.jsonc').read_text())['cases']
    cached=json.loads((HERE/'oracle.json').read_text())
    records={r['id']:r for r in cached['records']}
    assert set(records)=={c['id'] for c in cases},'stale or missing oracle ids'
    expected={};requests=[]
    for case in cases:
        path=HERE/case['font'];record=records[case['id']]
        assert hashlib.sha256(path.read_bytes()).hexdigest()==record['font_sha256'],f'{case["id"]}: font changed'
        expected.update({(case['id'],key):value for key,value in record['expected'].items()})
        requests.append('\t'.join([case['id'],str(path),case['kind'],case.get('text','')]))
    work=ROOT/'.roc-font-tmp'/'color-images';work.mkdir(parents=True,exist_ok=True)
    binary=work/'queries'
    with flight.flight(args.roc,work=work/'flight') as dep:
        command=[args.roc,'build',str(HERE/'query.roc'),f'--output={binary}',*dep]
        if not args.dev:command.insert(2,'--opt=speed')
        built=subprocess.run(command,cwd=ROOT,text=True,capture_output=True)
        if built.returncode != 0 or not binary.is_file():
            sys.stderr.write(built.stdout+built.stderr);return 1
        run=subprocess.run([str(binary)],input='\n'.join(requests)+'\n',text=True,capture_output=True,cwd=ROOT)
        if run.returncode:
            sys.stderr.write(run.stdout+run.stderr);return 1
    actual={}
    for line in run.stdout.splitlines():
        tag,key,value=line.split('\t')
        assert (tag,key) not in actual,'duplicate query answer'
        actual[tag,key]=value
    differences=[]
    for key in sorted(expected.keys()|actual.keys()):
        if expected.get(key)!=actual.get(key):
            differences.append(key)
            print(f'DIFFER {key}: expected {expected.get(key)!r}, actual {actual.get(key)!r}',file=sys.stderr)
    if differences:return 1
    print(f'{len(cases)} cases: {len(expected)} exact color-container/metric/payload/shape facts agree; native {"dev" if args.dev else "optimized"}, served bundle')
    return 0
if __name__=='__main__':raise SystemExit(main())
