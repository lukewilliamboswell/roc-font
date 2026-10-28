"""Replay actual cached AAT positioning outputs through an optimized bundle."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'scripts'));import flight
from _common import load_jsonc

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--binary',type=Path);args=ap.parse_args();roc=os.environ.get('ROC','roc')
 cases=load_jsonc(HERE/'cases.jsonc')['cases'];work=ROOT/'.roc-font-tmp/aat-position';work.mkdir(parents=True,exist_ok=True)
 binary=args.binary or work/'query'
 if not args.binary:
  mirror=flight.make_mirror(work/'mirror',root=ROOT)
  with flight.flight(roc,work=work/'flight')as dep:
   subprocess.run([roc,'build','--opt=speed','tests/fonts/aat-position/query.roc',f'--output={binary}',*dep],cwd=mirror,check=True)
 requests=[]
 for c in cases:
  assert hashlib.sha256((HERE/c['font']).read_bytes()).hexdigest()==c['font_sha256']
  requests.append('\t'.join([c['id'],str(HERE/c['font']),c['direction'],str(int(c['kern'])),str(c['weight']),c['text']])+'\n')
 request=''.join(requests);p=subprocess.run([str(binary)],input=request,text=True,capture_output=True,timeout=120)
 if p.returncode:print(p.stderr);raise SystemExit(p.returncode)
 actual={id:json.loads(data)for id,data in(row.split('\t',1)for row in p.stdout.splitlines())};errors=[]
 for c in cases:
  if actual[c['id']]!=c['oracle']:errors.append((c,actual[c['id']]))
 for c,got in errors[:16]:print(json.dumps({'id':c['id'],'font':c['font'],'text':c['text'],'direction':c['direction'],'kern':c['kern'],'expected':c['oracle'],'got':got},ensure_ascii=False))
 if errors:
  by={}
  for c,_ in errors:by[c['font']]=by.get(c['font'],0)+1
  print(by);raise SystemExit(f'{len(errors)}/{len(cases)} AAT mismatches')
 repeated=subprocess.run([str(binary)],input=request,text=True,capture_output=True,timeout=120,check=True);assert repeated.stdout==p.stdout
 print(f'AAT positioning: {len(cases)} cached native cases PASS; repeated output identical.')
if __name__=='__main__':main()
