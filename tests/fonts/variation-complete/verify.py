"""Replay pinned reference facts against the served Roc bundle, without oracles."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'scripts'));import flight
from _common import load_jsonc

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--binary',type=Path);args=ap.parse_args()
 data=load_jsonc(HERE/'cases.jsonc');cases=data['cases'];roc=os.environ.get('ROC','roc')
 binary=args.binary or ROOT/'.roc-font-tmp/variation-complete/query'
 if not args.binary:
  binary.parent.mkdir(parents=True,exist_ok=True)
  with flight.flight(roc,work=binary.parent)as dep:
   subprocess.run([roc,'build','--opt=speed',str(HERE/'query.roc'),f'--output={binary}',*dep],cwd=ROOT,check=True)
 requests=[]
 for c in cases:
  assert hashlib.sha256((HERE/c['font']).read_bytes()).hexdigest()==c['font_sha256']
  settings=';'.join(f'{tag}={value:.18f}'for tag,value in c['settings'])
  requests.append('\t'.join([c['id'],str(HERE/c['font']),settings,','.join(map(str,c['glyphs'])),'v'if c['vertical']else'h',c['direction'],c['text']])+'\n')
 request=''.join(requests);p=subprocess.run([str(binary)],input=request,text=True,capture_output=True,check=True,timeout=120)
 actual={id:json.loads(row)for id,row in(s.split('\t',1)for s in p.stdout.splitlines())};errors=[]
 for c in cases:
  got=actual[c['id']]
  if got!=c['hb']:errors.append((c['id'],c['hb'],got))
  if 'freetype_metrics'in c:assert got['metrics']==c['freetype_metrics'],(c['id'],'independent FreeType disagreement')
  n=len(got['glyphs']);assert all(len(got[k])==n for k in ['advances','offsets','clusters'])
 for id,expected,got in errors[:12]:
  differences={k:{'expected':expected[k][:12],'got':got[k][:12]}for k in expected if expected[k]!=got.get(k)}
  print(json.dumps({'id':id,'differences':differences},ensure_ascii=False))
 if errors:raise SystemExit(f'{len(errors)} variation mismatches')
 repeated=subprocess.run([str(binary)],input=request,text=True,capture_output=True,check=True,timeout=120);assert repeated.stdout==p.stdout,'nondeterministic results'
 print(f"Variation completion: {len(cases)} native HB14.6 cases PASS; repeated output identical.")
if __name__=='__main__':main()
