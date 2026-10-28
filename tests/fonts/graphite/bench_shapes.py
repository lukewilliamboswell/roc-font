#!/usr/bin/env python3
"""Three increasing sizes of actual Graphite execution, excluding preparation."""
from pathlib import Path
import argparse, ctypes as C, hashlib, json, os, re, statistics, subprocess, sys
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'scripts')); import flight

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
 p=argparse.ArgumentParser();p.add_argument('--font',type=Path);p.add_argument('--script');p.add_argument('--direction',choices=['ltr','rtl']);p.add_argument('--text');p.add_argument('--sizes',default='16,64,256');p.add_argument('--family',choices=['charis','padauk','scheherazade','awami'],default='charis');p.add_argument('--bundle',type=Path);p.add_argument('--reuse',action='store_true');p.add_argument('--compare',type=Path);p.add_argument('--work',type=Path,default=ROOT/'.roc-font-tmp/graphite-shape-bench');p.add_argument('--output',type=Path);a=p.parse_args()
 work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);roc=os.environ.get('ROC','roc')
 if not a.reuse:
  with flight.flight(roc,bundle=a.bundle,work=work/'flight') as dep:
   mirror=flight.make_mirror(work/'mirror')
   for name in ['shape_bench','shape_alloc']:
    subprocess.run([roc,'build','--opt=speed',*(['--fuzz'] if name=='shape_alloc' else []),f'tests/fonts/graphite/{name}.roc',f'--output={work/name}',*dep],cwd=mirror,check=True)
   (work/'bundle-url.txt').write_text(dep[-1])
 file,script,direction,piece={
  'charis':('Charis5_eursub.ttf','Latn','ltr','office á Tiếng Việt '),
  'padauk':('Padauk.ttf','Mymr','ltr','မြန်မာ က္က င်္က '),
  'scheherazade':('Scheherazadegr.ttf','Arab','rtl','بسم الله الرحمن الرحيم '),
  'awami':('AwamiNastaliq-Regular.ttf','Arab','rtl','بسم الله الرحمن الرحيم '),
 }[a.family]
 if a.font:
  assert a.script and a.direction and a.text is not None,'--font requires --script, --direction and --text'
  script,direction,piece=a.script,a.direction,a.text
  assert len(script.encode())==4 and piece and all(c not in piece for c in '\t\r\n'),'four-byte script and single-line text required'
 fontpath=a.font.resolve() if a.font else HERE/file;data=fontpath.read_bytes();pin=json.loads((HERE/'shape-oracle.json').read_text())
 hbpath=Path('/private/tmp/libroc-font-hb14-graphite.dylib');assert sha(hbpath)==pin['harfbuzz_library_sha256']
 lib=C.CDLL(str(hbpath));ptr=C.c_void_p;uint=C.c_uint
 def bind(name,args,result):
  fn=getattr(lib,name);fn.argtypes=args;fn.restype=result;return fn
 assert bind('hb_version_string',[],C.c_char_p)()==b'14.6.0'
 blob=bind('hb_blob_create',[C.c_char_p,uint,C.c_int,ptr,ptr],ptr)(data,len(data),0,None,None)
 face=bind('hb_face_create',[ptr,uint],ptr)(blob,0);font=bind('hb_font_create',[ptr],ptr)(face)
 bind('hb_ot_font_set_funcs',[ptr],None)(font)
 buffer=bind('hb_buffer_create',[],ptr)()
 source=HERE/'shape_bench.c';library=work/'hb-loop.dylib'
 subprocess.run(['cc','-O2','-dynamiclib',str(source),'-o',str(library)],check=True)
 measure=C.CDLL(str(library)).measure_graphite
 measure.argtypes=[C.c_size_t]*8+[ptr,ptr,C.c_char_p,uint,uint,uint,uint,C.POINTER(C.c_uint64)];measure.restype=C.c_uint64
 functions=[C.cast(getattr(lib,n),ptr).value for n in ['hb_buffer_clear_contents','hb_buffer_add_utf8','hb_shape_full','hb_buffer_get_glyph_infos','hb_buffer_get_glyph_positions','hb_buffer_set_script','hb_buffer_set_direction','hb_glyph_info_get_glyph_flags']]
 rows=[];count=16
 sizes=[int(n) for n in a.sizes.split(',')];assert len(sizes)>=3 and all(0<n<=4096 for n in sizes) and sizes==sorted(set(sizes))
 for copies in sizes:
  text=(piece*copies).encode();case=work/f'{a.family}-{copies}.case';header=f'{script}\t{direction}\t{copies}\t{piece}\n' if a.font else f'{script} {direction} {copies}\n'
  case.write_bytes(header.encode()+data)
  run=subprocess.run([str(work/'shape_alloc'),'replay',str(case)],capture_output=True,text=True)
  match=re.search(r'ALLOCATION_DIAGNOSTIC allocations=(\d+) leaked=(\d+) result=ok checksum=(\d+)',run.stdout+run.stderr);assert run.returncode==77 and match,run.stdout+run.stderr
  before_counts=None
  if a.compare:
   old=subprocess.run([str(a.compare.resolve()/'shape_alloc'),'replay',str(case)],capture_output=True,text=True)
   before_counts=re.search(r'ALLOCATION_DIAGNOSTIC allocations=(\d+) leaked=(\d+) result=ok checksum=(\d+)',old.stdout+old.stderr)
   assert old.returncode==77 and before_counts and before_counts[3]==match[3],old.stdout+old.stderr
  digest=5381
  for byte in text:digest=(33*digest+byte)&(2**64-1)
  samples=[]
  for _ in range(5):
   result=json.loads(subprocess.check_output([str(work/'shape_bench'),str(count)],input=case.read_bytes()))
   assert (result['script'],result['direction'],result['utf8_bytes'],result['input_checksum'],result['successes'])==(script,direction,len(text),digest,count),result
   before_result=None
   if a.compare:
    before_result=json.loads(subprocess.check_output([str(a.compare.resolve()/'shape_bench'),str(count)],input=case.read_bytes()))
    for key in ['script','direction','utf8_bytes','input_checksum','successes','checksum']:assert before_result[key]==result[key],(key,before_result,result)
   checksum=C.c_uint64();elapsed=measure(*functions,font,buffer,text,len(text),count,int.from_bytes(script.encode(),'big'),5 if direction=='rtl' else 4,C.byref(checksum))
   assert elapsed!=2**64-1 and checksum.value==result['checksum']==(int(match[3])*count)&(2**64-1),(result,checksum.value)
   sample={'roc_ns':result['elapsed_ns']/count,'hb_graphite_ns':elapsed/count,'ratio':result['elapsed_ns']/elapsed}
   if before_result:sample.update({'before_roc_ns':before_result['elapsed_ns']/count,'before_ratio':before_result['elapsed_ns']/elapsed})
   samples.append(sample)
  row={'copies':copies,'scalars':len(text.decode()),'utf8_bytes':len(text),'input_checksum':digest,'output_checksum':int(match[3]),'allocations':int(match[1]),'leaked':int(match[2]),'samples':samples,'median_ratio':statistics.median(s['ratio'] for s in samples)};
  if before_counts:row.update({'before_allocations':int(before_counts[1]),'before_leaked':int(before_counts[2]),'before_median_ratio':statistics.median(s['before_ratio'] for s in samples)})
  rows.append(row);print(json.dumps(row),flush=True)
 report={'family':a.family if not a.font else 'caller','text_piece':piece,'font_sha256':sha(fontpath),'script':script,'direction':direction,'bundle':(work/'bundle-url.txt').read_text(),'compiler':subprocess.check_output([roc,'version'],text=True).strip(),'compiler_sha256':sha(Path(roc)),'binary_sha256':sha(work/'shape_bench'),'allocation_binary_sha256':sha(work/'shape_alloc'),'oracle':pin,'rows':rows,'requested_bytes':None,'peak_live_bytes':None,'notes':['Font read and plan excluded; five interleaved samples,16 executions each.','Actual Graphite backend asserted; identical byte input and ordered glyph/cluster/advance/offset/flag checksum asserted against HB14.6 Graphite adapter.','roc-fuzz0.4.3 does not expose requested or peak live bytes.']}
 if a.compare:report.update({'before_bundle':(a.compare/'bundle-url.txt').read_text(),'before_binary_sha256':sha(a.compare/'shape_bench'),'before_allocation_binary_sha256':sha(a.compare/'shape_alloc')})
 (a.output or work/f'{a.family}.json').write_text(json.dumps(report,indent=2)+'\n')

if __name__=='__main__':main()
