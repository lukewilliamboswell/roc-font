"""Isolate each PUBLIC logging query; retain reference crashes explicitly."""
import argparse,hashlib,json,re,subprocess,sys,tempfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
canonical=lambda v:json.dumps(v,sort_keys=True,separators=(',',':')).encode()
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--library',type=Path,default=Path('/private/tmp/graphite-geometry-reference/src/libgraphite2.dylib'));a=p.parse_args();cases=json.loads((HERE/'mode6-cases.jsonc').read_text())['cases'];output=HERE/'logging-outcomes.json'
if a.check:
 saved=json.loads(output.read_text());assert len(saved['records'])==len(cases)
 for case,row in zip(cases,saved['records']):assert row['id']==case['id']and row['key']==sha(canonical({'case':case,'font':sha((HERE/Path(case['font']).name).read_bytes()),'oracle':saved['oracle']}))
 print('18 isolated public logging outcome keys current');raise SystemExit(0)
oracle={'engine':'Graphite2','version':'1.3.14','api':'public gr_start_logging plus public C ABI; one subprocess per original font','library_sha256':sha(a.library.read_bytes()),'face_options':6,'extractor':1};records=[]
with tempfile.TemporaryDirectory(prefix='roc-font-deleted-leaf-logging-')as temp:
 for case in cases:
  folder=Path(temp)/case['id'];folder.mkdir();one=folder/'case.jsonc';one.write_text(json.dumps({'cases':[case]}));result=folder/'result.json';logs=folder/'logs'
  run=subprocess.run([sys.executable,str(HERE/'record.py'),'--cases',str(one),'--output',str(result),'--library',str(a.library),'--log-dir',str(logs)],capture_output=True,text=True)
  row={'id':case['id'],'font_sha256':sha((HERE/Path(case['font']).name).read_bytes()),'key':sha(canonical({'case':case,'font':sha((HERE/Path(case['font']).name).read_bytes()),'oracle':oracle})),'returncode':run.returncode,'stdout':run.stdout,'stderr':run.stderr,'status':'Completed'if run.returncode==0 else'ReferenceProcessFailure'}
  trace_path=logs/(case['id']+'.json')
  if trace_path.exists():
   text=trace_path.read_text();names={}
   def norm(match):
    value=match.group(0)
    if value not in names:names[value]='public-id-'+str(len(names)+1)
    return names[value]
   normalized=re.sub(r'\b[0-9a-f]{4}-[0-9a-f]{2}-[0-9a-f]{4}\b',norm,text)
   row['observed_trace_text']=normalized
   try:json.loads(text);row['trace_complete_json']=True
   except json.JSONDecodeError:row['trace_complete_json']=False
  if run.returncode==0:row['result']=json.loads(result.read_text())['records'][0]['result']
  records.append(row)
output.write_text(json.dumps({'oracle':oracle,'records':records},indent=2)+'\n');print('18 isolated logging queries:',sum(r['returncode']==0 for r in records),'completed,',sum(r['returncode']!=0 for r in records),'reference process failures')
