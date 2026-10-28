"""Before/after native context fanout benchmark, same warm batches and HB14.6.

Pass optimized generic bench/roc/font.roc and alloc.roc binaries. Keeping
building separate lets the integrator reuse its exact checked artifact.
"""
from pathlib import Path
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
 ap.add_argument('--output',type=Path,default=ROOT/'.roc-font-tmp/bench/context-budget.json')
 args=ap.parse_args();version=subprocess.check_output([str(args.harfbuzz),'--version'],text=True).strip()
 assert version=='14.6.0',version
 binaries={k:getattr(args,k.replace('-','_')).resolve() for k in ['before','after','before-alloc','after-alloc','harfbuzz']}
 result={'harfbuzz':version,'binaries':{k:{'path':str(p),'sha256':sha(p)} for k,p in binaries.items()},'requested_bytes':None,'peak_live_bytes':None,'unavailable_reason':'roc-fuzz0.4.3 exposes allocation counts, not allocator byte sizes; RSS is reported separately','cases':[]}
 with tempfile.TemporaryDirectory(prefix='context-bench-') as tmp:
  for n in [256,2048,8192]:
   font=ROOT/f'tests/fonts/positioning/context-budget/many-{n}.ttf';raw=font.read_bytes();data=b'shape\n'+str(len(raw)).encode()+b'\n'+raw+b'a'
   path=Path(tmp)/f'{n}.case';path.write_bytes(data)
   entry={'records':n,'font_sha256':sha(font),'timing':{k:measure(binaries[k],data) for k in ['before','after','harfbuzz']},'allocation':{k:bench.count_allocations(binaries[k],path,180) for k in ['before-alloc','after-alloc']}}
   assert len({t['checksum'] for t in entry['timing'].values()})==1
   entry['after_before_ratio']=entry['timing']['after']['median_ns']/entry['timing']['before']['median_ns']
   entry['after_harfbuzz_ratio']=entry['timing']['after']['median_ns']/entry['timing']['harfbuzz']['median_ns']
   result['cases'].append(entry)
   print(n,entry['allocation'],entry['after_before_ratio'],entry['after_harfbuzz_ratio'],flush=True)
 args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(result,indent=2)+'\n')
if __name__=='__main__':main()
