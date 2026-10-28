"""Replay cached HB14.6/Graphite2 runs through the optimized public bundle.
No reference library or fontTools is needed for this gate. Compilation takes
place in a source-sentinel mirror; each native process prepares one font once.
"""
from pathlib import Path
import argparse,collections,hashlib,json,os,subprocess,sys
from limitations import PolicyError,load as load_limits,classify as classify_limit
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'scripts'));import flight

def main():
 p=argparse.ArgumentParser();p.add_argument('--cases',type=Path,default=HERE/'shape-cases.jsonc');p.add_argument('--records',type=Path,default=HERE/'shape-records.json');p.add_argument('--oracle',type=Path,default=HERE/'shape-oracle.json');p.add_argument('--font-root',type=Path,default=HERE);p.add_argument('--divergences',type=Path);p.add_argument('--engine-expectations',type=Path);p.add_argument('--known-limitations',type=Path,help='Explicit per-case observed implementation limits; never counted as reference agreement');p.add_argument('--limitation-set',default='',help='Named matrix in --known-limitations');p.add_argument('--binary',type=Path);p.add_argument('--bundle',type=Path);p.add_argument('--dev',action='store_true');p.add_argument('--operations-factor',type=int,help='Explicit caller limit for a separately labelled diagnostic; default package limits remain unchanged');p.add_argument('--only',default='');p.add_argument('--output',type=Path);args=p.parse_args()
 subprocess.run([sys.executable,str(HERE/'record_shapes.py'),'--check','--cases',str(args.cases.resolve()),'--output',str(args.records.resolve()),'--oracle',str(args.oracle.resolve()),'--font-root',str(args.font_root.resolve())],check=True)
 cases=json.loads(args.cases.read_text())['cases'];records={r['id']:r for r in json.loads(args.records.read_text())['records']}
 selected=[c for c in cases if args.only in c['id']];assert selected,'empty Graphite replay selection'
 try:known,policy=load_limits(args.known_limitations,args.limitation_set,cases,records)
 except PolicyError as error:raise SystemExit(str(error))
 work=ROOT/'.roc-font-tmp/graphite-replay';work.mkdir(parents=True,exist_ok=True);binary=args.binary.resolve() if args.binary else work/'query';provenance={}
 if not args.binary:
  roc=os.environ.get('ROC','roc')
  with flight.flight(roc,bundle=args.bundle,work=work/'flight') as dep:
   mirror=flight.make_mirror(work/'mirror')
   command=[roc,'build',*(['--opt=dev'] if args.dev else ['--opt=speed']),'tests/fonts/graphite/query.roc',f'--output={binary}',*dep]
   built=subprocess.run(command,cwd=mirror,text=True,capture_output=True)
   if built.returncode:sys.stderr.write(built.stdout+built.stderr);return 1
   provenance={'bundle':dep[-1].split('/')[-1],'compiler_sha256':hashlib.sha256(Path(roc).read_bytes()).hexdigest(),'optimized':not args.dev}
 if args.operations_factor is not None:
  assert 0<=args.operations_factor<=2**32-1
  provenance['diagnostic_operations_factor']=args.operations_factor
 provenance['binary_sha256']=hashlib.sha256(binary.read_bytes()).hexdigest()
 grouped=collections.defaultdict(list)
 for case in selected:grouped[case['font']].append(case)
 actual={};reader_failures=[];availability_probes={}
 engine_expectations=json.loads(args.engine_expectations.read_text())['expected_primary_engines'] if args.engine_expectations else {}
 for font,items in grouped.items():
  requests=[]
  for case in items:
   start,end=case.get('range',[0,2**64-1]);settings=','.join(f"{f['id']}:{f['value']}" for f in case.get('features',[]))
   fields=[case['id'],case.get('script','Latn'),case.get('language',''),case.get('direction','ltr'),str(case.get('cluster_level',0)),settings,case.get('engine','graphite2'),str(start),str(end),case['text']]
   if case.get('variations'):fields.append(','.join(f"{v['tag']}:{v['value']}" for v in case['variations']))
   assert all('\t' not in f and '\n' not in f for f in fields)
   requests.append('\t'.join(fields))
  if any('graphite_face_available' in records[c['id']]['result'] for c in items):
   probe='__availability_'+hashlib.sha256(font.encode()).hexdigest()[:16];assert probe not in records
   availability_probes[font]=probe;requests.append('\t'.join([probe,'Latn','','ltr','0','','auto','0','0','']))
  run=subprocess.run([str(binary),str(args.font_root/font),*([str(args.operations_factor)] if args.operations_factor is not None else [])],input='\n'.join(requests)+'\n',text=True,capture_output=True,cwd=ROOT,timeout=180)
  if run.returncode:reader_failures.append(font);print(font,run.stdout,run.stderr,file=sys.stderr);continue
  for line in run.stdout.splitlines():
   key,value=line.split('\t',1);assert key not in actual,key;actual[key]=json.loads(value)
 failures=[];exact=0;normative=0;known_ids=[];limitation_errors=[]
 divergences={r['id']:r for r in json.loads(args.divergences.read_text())['cases']} if args.divergences else {}
 if set(known)&set(divergences):raise SystemExit('implementation limits and normative divergences must not overlap')
 for case in selected:
  key=case['id'];got=actual.get(key);raw=records[key]['result'];expected=raw
  if key in divergences:
   divergence=divergences[key];assert divergence['reference_key']==records[key]['key'],key
   expected=divergence['expected'];assert expected!=raw,key
  if case.get('engine')=='auto':assert key in engine_expectations,'auto requires an explicit primary-engine expectation: '+key
  engine=engine_expectations.get(key,'OpenType' if case.get('engine')=='ot' else 'Graphite')
  if got is not None and 'graphite_face_available' in raw:
   probe=actual.get(availability_probes[case['font']]);assert probe is not None and not probe['budgets'] and not probe['glyphs']
   got['graphite_face_available']=probe['engine']=='Graphite'
  agrees=got is not None and not got.get('budgets') and got.get('engine')==engine and {k:got.get(k)for k in expected}==expected
  if key in known:
   problem=classify_limit(known[key],got,agrees)
   if problem:
    failures.append(key);limitation_errors.append({'id':key,'problem':problem});print('LIMIT POLICY FAILURE',key,problem,'actual',got,file=sys.stderr)
   else:known_ids.append(key)
  elif not agrees:
   failures.append(key);print('DIFFER',key,'expected',expected,'actual',got,file=sys.stderr)
  elif key in divergences:normative+=1
  else:exact+=1
 report={'cases':len(selected),'agree':exact,'normative':normative,'known_limitations':len(known_ids),'known_limitation_ids':known_ids,'limitation_policy_errors':limitation_errors,'failures':failures,'reader_failures':reader_failures,'provenance':provenance}
 if policy:report['implementation_limit_policy']=policy
 if args.output:args.output.write_text(json.dumps(report,indent=2)+'\n')
 print(f"{report['agree']} exact, {normative} declared normative, {len(known_ids)} known implementation limits, {len(failures)} failures / {len(selected)} cached HB14.6/Graphite2 public runs")
 return bool(failures or reader_failures)
if __name__=='__main__':raise SystemExit(main())
