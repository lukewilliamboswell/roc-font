"""Pin OTS acceptance and byte-identical retained Graphite tables."""
import argparse,hashlib,json,os,struct,subprocess,tempfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
def tables(data):
 out={}
 for i in range(struct.unpack_from('>H',data,4)[0]):
  p=12+16*i;tag=data[p:p+4].decode('ascii');start,size=struct.unpack_from('>II',data,p+8);assert start+size<=len(data);out[tag]=data[start:start+size]
 return out
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--ots',type=Path,default=Path(os.environ.get('OTS_SANITIZE','/private/tmp/roc-font-ots-build/ots-sanitize')));a=p.parse_args();cases=json.loads((HERE/'cases.jsonc').read_text())['cases'];output=HERE/'ots-records.json'
if a.check:
 rows=json.loads(output.read_text())['records'];assert len(rows)==len(cases)
 for case,row in zip(cases,rows):
  data=(HERE/Path(case['font']).name).read_bytes();assert row['id']==case['id']and row['font_sha256']==sha(data)and row['accepted']
  assert row['graphite_tables']=={k:sha(v)for k,v in tables(data).items()if k in ['Silf','Glat','Gloc','Feat','Sill']}
  assert row['graphite_retained_identically']
 print('22 cached OTS acceptance/table-retention records current');raise SystemExit(0)
version=subprocess.run([str(a.ots),'--version'],capture_output=True,text=True,check=True).stdout.strip();assert '9.3.0'in version,version
records=[]
with tempfile.TemporaryDirectory(prefix='roc-font-kern-eligibility-ots-')as temp:
 for case in cases:
  source=HERE/Path(case['font']).name;dest=Path(temp)/source.name;run=subprocess.run([str(a.ots),str(source),str(dest)],capture_output=True,text=True);data=source.read_bytes();before={k:sha(v)for k,v in tables(data).items()if k in ['Silf','Glat','Gloc','Feat','Sill']};after=tables(dest.read_bytes())if run.returncode==0 else{};retained=all(k in after and sha(after[k])==v for k,v in before.items());assert run.returncode==0 and retained,(case['id'],run.stdout,run.stderr)
  records.append({'id':case['id'],'font_sha256':sha(data),'accepted':True,'graphite_tables':before,'graphite_retained_identically':retained,'stdout':run.stdout,'stderr':run.stderr})
output.write_text(json.dumps({'oracle':{'engine':'OTS','version':version,'binary_sha256':sha(a.ots.read_bytes()),'source_commit':'884861e'},'records':records},indent=2)+'\n');print('22 OTS accepted fonts; all Graphite tables retained identically')
