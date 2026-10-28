#!/usr/bin/env python3
"""Build one optimized public query and replay every independent Graphite matrix.

All reference answers are cached; no oracle library is loaded. Compilation uses
the served package in a source-sentinel mirror. Each delegated verifier retains
its own exact record/exception contract and receives the same native binary.
"""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'scripts'));import flight

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
 p=argparse.ArgumentParser();p.add_argument('--bundle',type=Path);p.add_argument('--binary',type=Path);p.add_argument('--metrics-root',type=Path,default=HERE.parent/'graphite-metrics');p.add_argument('--geometry-root',type=Path,default=HERE.parent/'graphite-geometry');p.add_argument('--output',type=Path);p.add_argument('--work',type=Path,default=ROOT/'.roc-font-tmp/graphite-all');a=p.parse_args()
 work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);roc=os.environ.get('ROC','roc');binary=a.binary.resolve() if a.binary else work/'query';provenance={'reused_binary':bool(a.binary)}
 if not a.binary:
  binary.unlink(missing_ok=True)
  with flight.flight(roc,bundle=a.bundle,work=work/'flight') as dep:
   mirror=flight.make_mirror(work/'mirror')
   command=[roc,'build','--opt=speed','tests/fonts/graphite/query.roc',f'--output={binary}',*dep]
   result=subprocess.run(command,cwd=mirror,text=True,capture_output=True)
   (work/'build.log').write_text(result.stdout+result.stderr)
   if result.returncode:
    sys.stderr.write(result.stdout+result.stderr);return result.returncode
   provenance.update({'bundle':dep[-1].rsplit('/',1)[-1],'compiler_sha256':sha(Path(roc)),'optimized':True,'source_sentinel':True})
 provenance['binary_sha256']=sha(binary)
 (work/'build-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
 print(f'Graphite shared optimized query ready: {binary}',flush=True)
 commands=[]
 for name in ['shape','feature','direction','association','progress','width']:
  options=['--binary',str(binary),'--cases',str(HERE/f'{name}-cases.jsonc'),'--records',str(HERE/f'{name}-records.json'),'--oracle',str(HERE/f'{name}-oracle.json')]
  if name=='feature':options+=['--divergences',str(HERE/'feature-divergences.json')]
  commands.append((name,[sys.executable,str(HERE/'verify.py'),*options]))
 metrics=a.metrics_root.resolve()
 commands.append(('metrics',[sys.executable,str(HERE/'verify.py'),'--binary',str(binary),'--cases',str(metrics/'hb-cases.jsonc'),'--records',str(metrics/'hb-records.json'),'--oracle',str(metrics/'hb-oracle.json'),'--font-root',str(metrics)]))
 geometry=a.geometry_root.resolve()
 for name in ['geometry-default','geometry-face0']:
  command=[sys.executable,str(geometry/'verify.py'),'--binary',str(binary)]
  if name=='geometry-face0':command+=['--records',str(geometry/'face0-records.json'),'--oracle',str(geometry/'face0-oracle.json')]
  commands.append((name,command))
 reports=[];failed=False
 for name,command in commands:
  report=work/f'{name}.json';report.unlink(missing_ok=True);command+=['--output',str(report)]
  with (work/f'{name}.log').open('w') as log:
   result=subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
  data=json.loads(report.read_text()) if report.exists() else None
  reports.append({'matrix':name,'exit_code':result.returncode,'report':data});failed|=result.returncode!=0
  print(f'{name}: exit={result.returncode}; report={report}',flush=True)
 output={'provenance':provenance,'matrices':reports,'passed':not failed}
 (a.output or work/'report.json').write_text(json.dumps(output,indent=2)+'\n')
 return int(failed)

if __name__=='__main__':raise SystemExit(main())
