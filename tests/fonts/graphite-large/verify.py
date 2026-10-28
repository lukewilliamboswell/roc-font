"""Compare every native row with compact full-reference SHA256 records."""
from pathlib import Path
import argparse,hashlib,json,struct,subprocess,sys
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--binary',type=Path,required=True);p.add_argument('--output',type=Path);a=p.parse_args()
subprocess.run([sys.executable,str(HERE/'record.py'),'--check'],check=True)
cached=json.loads((HERE/'records.json').read_text());requests=[]
for case in cached['results']:requests.append(f"{case['n']}\tLatn\t\tltr\t0\t\tgraphite2\t0\t{2**64-1}\t"+'b'*case['n'])
run=subprocess.run([str(a.binary.resolve()),str(HERE/'large-advance.ttf')],input='\n'.join(requests)+'\n',capture_output=True,text=True,timeout=180)
assert run.returncode==0,run.stderr
actual={int(k):json.loads(v) for k,v in (line.split('\t',1) for line in run.stdout.splitlines())};failures=[]
for expected in cached['results']:
 n=expected['n'];value=actual[n];digest=hashlib.sha256();flag_digest=hashlib.sha256();total=0;samples=[]
 for i,glyph in enumerate(value['glyphs']):
  row=[glyph['glyph'],glyph['cluster'],*glyph['advance'],*glyph['offset']];digest.update(struct.pack('>IIiiii',*row));flag_digest.update(bytes([glyph['flags']]));total+=glyph['advance'][0]
  if i<3 or i>=len(value['glyphs'])-3:samples.append({'index':i,'row':row})
 if value['budgets'] or value['engine']!='Graphite' or value['abort']!='NoAbort' or len(value['glyphs'])!=expected['count'] or total!=expected['sum_advances_i64'] or digest.hexdigest()!=expected['rows_sha256_be_IIiiii'] or flag_digest.hexdigest()!=expected['flags_sha256'] or samples!=expected['samples']:
  failures.append(n);print('DIFFER large cumulative advance',n,'hash',digest.hexdigest(),'samples',samples,file=sys.stderr)
report={'cases':5,'agree':5-len(failures),'failures':failures,'binary_sha256':hashlib.sha256(a.binary.read_bytes()).hexdigest(),'reference_sha256':hashlib.sha256((HERE/'records.json').read_bytes()).hexdigest()}
if a.output:a.output.write_text(json.dumps(report,indent=2)+'\n')
print(f"{report['agree']}/5 compact full-run Graphite conversion controls agree");raise SystemExit(bool(failures))
