"""Pin original fixture acceptance by OTS, or check cached keys offline."""
import argparse,hashlib,json,subprocess,tempfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
sha=lambda data:hashlib.sha256(data).hexdigest()
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--ots',type=Path,default=Path('/private/tmp/roc-font-ots-build/ots-sanitize'));args=p.parse_args()
fonts=sorted([*HERE.glob('*.ttf'),*HERE.glob('*.otf')]);output=HERE/'ots.json'
if args.check:
    saved=json.loads(output.read_text());assert saved['oracle']['version']=='9.3.0'
    assert {r['font']:r['sha256']for r in saved['fonts']}=={f.name:sha(f.read_bytes())for f in fonts}
    assert all(r['accepted']for r in saved['fonts']if not r['diagnostic']);print(len(fonts),'cached OTS acceptance hashes current');raise SystemExit(0)
version=subprocess.run([str(args.ots),'--version'],capture_output=True,text=True,check=True).stdout.strip();assert '9.3.0'in version
rows=[]
with tempfile.TemporaryDirectory()as tmp:
    for font in fonts:
        done=subprocess.run([str(args.ots),str(font),str(Path(tmp)/font.name)],capture_output=True,text=True)
        rows.append({'font':font.name,'sha256':sha(font.read_bytes()),'accepted':done.returncode==0,'diagnostic':font.name.startswith(('maxp-matrix-','cache-'))or'-maxp1-diagnostic'in font.name,'stdout':done.stdout,'stderr':done.stderr})
assert all(row['accepted']for row in rows if not row['diagnostic'])
output.write_text(json.dumps({'oracle':{'version':'9.3.0','binary_sha256':sha(args.ots.read_bytes()),'source_commit':'884861e0103b41d7e9845fdaf9fd1e3c12819103'},'fonts':rows},indent=2)+'\n')
print(sum(r['accepted']for r in rows),'/',len(rows),'OTS accepted; all nondiagnostic fonts accepted')
