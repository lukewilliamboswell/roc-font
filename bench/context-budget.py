"""Before/after native context fanout benchmark, same warm batches and HB 14.6.

Pass optimized generic bench/roc/font.roc and alloc.roc binaries. Keeping
building separate lets the integrator reuse its exact checked artifact.
"""
from pathlib import Path
from datetime import datetime,timezone
import argparse,hashlib,json,statistics,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
import bench

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def measure(binary,data):
 first=bench.run_once([str(binary)],data,1,180)
 count=bench.calibrate(first['elapsed_ns'],100_000_000,10000)
 bench.run_once([str(binary)],data,count,180)
 samples=[bench.run_once([str(binary)],data,count,180) for _ in range(5)]
 return {'median_ns':statistics.median(s['elapsed_ns']/count for s in samples),'iterations':count,'checksum':first['checksum'],'samples':samples,'peak_rss_bytes':max(s.get('peak_rss_bytes') or 0 for s in samples)}
def main():
 ap=argparse.ArgumentParser()
 for key in ['before','after','before-alloc','after-alloc','harfbuzz']:ap.add_argument('--'+key,type=Path,required=True)
 ap.add_argument('--harfbuzz-library',type=Path)
 ap.add_argument('--output',type=Path,default=ROOT/'.roc-font-tmp/bench/context-budget.json')
 args=ap.parse_args();bench._install_wait_hook();version=subprocess.check_output([str(args.harfbuzz),'--version'],text=True).strip()
 assert version=='14.6.0',version
 binaries={k:getattr(args,k.replace('-','_')).resolve() for k in ['before','after','before-alloc','after-alloc','harfbuzz']}
 result={'date':datetime.now(timezone.utc).isoformat(),'machine':bench.machine(),'harfbuzz':version,'binaries':{k:{'path':str(p),'sha256':sha(p)} for k,p in binaries.items()},'requested_bytes':None,'peak_live_bytes':None,'unavailable_reason':'roc-fuzz0.4.3 exposes allocation counts, not allocator byte sizes; RSS is reported separately','peak_rss_source':bench.RSS_SOURCE,'cases':[]}
 with tempfile.TemporaryDirectory(prefix='context-bench-') as tmp:
  for n in [256,2048,8192]:
   font=ROOT/f'tests/fonts/positioning/context-budget/many-{n}.ttf';raw=font.read_bytes();data=b'shape\n'+str(len(raw)).encode()+b'\n'+raw+b'a'
   path=Path(tmp)/f'{n}.case';path.write_bytes(data)
   entry={'records':n,'font_sha256':sha(font),'timing':{k:measure(binaries[k],data) for k in ['before','after','harfbuzz']},'allocation':{k:bench.count_allocations(binaries[k],path,180) for k in ['before-alloc','after-alloc']}}
   assert len({t['checksum'] for t in entry['timing'].values()})==1
   old=entry['allocation']['before-alloc'];new=entry['allocation']['after-alloc']
   assert old['leaked']==0 and new['leaked']==0
   assert new['allocations']<=old['allocations'],(n,old,new)
   entry['after_before_ratio']=entry['timing']['after']['median_ns']/entry['timing']['before']['median_ns']
   entry['after_harfbuzz_ratio']=entry['timing']['after']['median_ns']/entry['timing']['harfbuzz']['median_ns']
   result['cases'].append(entry)
   print(n,entry['allocation'],entry['after_before_ratio'],entry['after_harfbuzz_ratio'],flush=True)
 if args.harfbuzz_library:result['harfbuzz_library']={'path':str(args.harfbuzz_library.resolve()),'sha256':sha(args.harfbuzz_library)}
 result['adversarial']=[]
 for stem in ['cycle-8192','fanout-8192']:
  font=ROOT/f'tests/fonts/positioning/context-budget/{stem}.ttf';raw=font.read_bytes();data=b'shape\n'+str(len(raw)).encode()+b'\n'+raw+b'a'
  with tempfile.NamedTemporaryFile() as file:
   file.write(data);file.flush()
   allocation={k:bench.count_allocations(binaries[k],Path(file.name),180) for k in ['before-alloc','after-alloc']}
  times={k:measure(binaries[k],data) for k in ['before','after']}
  try:
   reference=measure(binaries['harfbuzz'],data)
   if stem.startswith('cycle'):reference={'reference_failure':'Pinned Python oracle reports MemoryError; native C comparator does not check buffer successful. Its timing is not a successful shape oracle.','native_timing_only':reference}
  except bench.RunError as error:reference={'reference_failure':str(error)}
  result['adversarial'].append({'font':font.name,'sha256':sha(font),'timing':times,'reference':reference,'allocation':allocation,'comparison_caveat':'Before has 16384 minimum operations; after and HB 14.6 have 65536. Timing ratios do not compare equal allowed work.'})
  print(stem,allocation,{k:t['median_ns'] for k,t in times.items()},flush=True)
 result['mixed_attachment_scaling']=[]
 for n in [8,64,256]:
  font=ROOT/'tests/fonts/positioning/context-budget/attachment-mixed-advances.ttf';raw=font.read_bytes();text=('a\u0301'+' '*n).encode();data=b'shape\n'+str(len(raw)).encode()+b'\n'+raw+text
  times={k:measure(binaries[k],data) for k in ['after','harfbuzz']}
  assert times['after']['checksum']==times['harfbuzz']['checksum']
  with tempfile.NamedTemporaryFile() as file:
   file.write(data);file.flush();allocation=bench.count_allocations(binaries['after-alloc'],Path(file.name),180)
  assert allocation['leaked']==0
  if result['mixed_attachment_scaling']:assert allocation['allocations']<=result['mixed_attachment_scaling'][-1]['allocation']['allocations']+32
  result['mixed_attachment_scaling'].append({'padding_glyphs':n,'font_sha256':sha(font),'timing':times,'allocation':allocation,'after_harfbuzz_ratio':times['after']['median_ns']/times['harfbuzz']['median_ns']})
  print('mixed',n,allocation,flush=True)
 args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(result,indent=2)+'\n')
if __name__=='__main__':main()
