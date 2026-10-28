#!/usr/bin/env python3
"""Measure real Myanmar shaping and bounded CCMP/reorder stress at3sizes.

Preparation is outside the timed/allocation region, and Myanmar is explicit
in the Roc plan. Native HarfBuzz guesses Myanmar from the same input. Both
consume identical font/text bytes, run in the same session, and must agree
on full checksums. Requested/peak live bytes are unavailable in roc-fuzz0.4.3;
allocation calls, timings and reference ratios are reported independently.
"""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import bench,flight
FONT=ROOT/'tests/fonts/shaping/myanmar'

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--roc',default=os.environ.get('ROC','roc'));p.add_argument('--harfbuzz',type=Path,required=True);p.add_argument('--harfbuzz-version',help='optional expected native reference version');p.add_argument('--harfbuzz-library',type=Path,required=True,help='the linked pinned HarfBuzz shared library');p.add_argument('--binary',type=Path);p.add_argument('--alloc',type=Path);p.add_argument('--output',type=Path,required=True);args=p.parse_args()
 actual_version=subprocess.check_output([str(args.harfbuzz),'--version'],text=True,timeout=5).strip()
 if args.harfbuzz_version:assert actual_version==args.harfbuzz_version,(actual_version,args.harfbuzz_version)
 with tempfile.TemporaryDirectory(prefix='myanmar-bench-') as directory:
  work=Path(directory);binary=args.binary or work/'myanmar';alloc=args.alloc or work/'myanmar-alloc'
  if args.binary is None or args.alloc is None:
   with flight.flight(args.roc,work=work) as dep:
    if args.binary is None:subprocess.run([args.roc,'build','--opt=speed',str(ROOT/'bench/roc/myanmar.roc'),f'--output={binary}',*dep],cwd=ROOT,check=True)
    if args.alloc is None:subprocess.run([args.roc,'build','--fuzz',str(ROOT/'bench/roc/myanmar-alloc.roc'),f'--output={alloc}',*dep],cwd=ROOT,check=True)
  results=[]
  for family,file,word in [('real','NotoSansMyanmar-Regular.ttf','င်္ကြွှေိံ '),('ccmp-reorder','sort-32.ttf','က'+'ေ'*31+' ')]:
   raw=(FONT/file).read_bytes()
   for count in [8,64,256]:
    text=(word*count).encode();case=b'shape\n'+str(len(raw)).encode()+b'\n'+raw+text;path=work/f'{family}-{count}.case';path.write_bytes(case)
    allocation=bench.count_allocations(alloc,path,120);assert allocation.get('result')=='ok',allocation
    times={};checksums={}
    for name,command in [('roc',binary),('harfbuzz',args.harfbuzz)]:
     first=bench.run_once([str(command)],case,1,120);checksums[name]=first['checksum']
     warm=bench.run_once([str(command)],case,10,120)
     iterations=max(1,min(100,int(100_000_000/max(1,warm['elapsed_ns']/10))))
     samples=[bench.run_once([str(command)],case,iterations,120)['elapsed_ns']/iterations for _ in range(3)]
     times[name]=bench.summarize(samples)
    assert checksums['roc']==checksums['harfbuzz'],(family,count,checksums)
    row=dict(family=family,repetitions=count,text_bytes=len(text),font_sha256=hashlib.sha256(raw).hexdigest(),allocation=allocation,times_ns=times,checksums=checksums,roc_over_harfbuzz=times['roc']['median_ns']/times['harfbuzz']['median_ns']);results.append(row);print(json.dumps(row),flush=True)
  args.output.parent.mkdir(parents=True,exist_ok=True)
  args.output.write_text(json.dumps(dict(cases=results,memory_bytes='requested/peak-live unavailable in roc-fuzz0.4.3',reference=dict(version=actual_version,binary_sha256=hashlib.sha256(args.harfbuzz.read_bytes()).hexdigest(),library_sha256=hashlib.sha256(args.harfbuzz_library.read_bytes()).hexdigest())),indent=2)+'\n')
 return 0
if __name__=='__main__':raise SystemExit(main())
