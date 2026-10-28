"""Three-size native AAT shaping timing/allocation evidence, exact checksums."""
from pathlib import Path
import argparse,ctypes as C,hashlib,json,os,re,statistics,subprocess,sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
sys.path.insert(0,str(ROOT/'scripts'));import flight
ap=argparse.ArgumentParser();ap.add_argument('--label',default='before');ap.add_argument('--reuse',action='store_true');args=ap.parse_args()
roc=os.environ.get('ROC','roc');work=ROOT/'.roc-font-tmp/aat-position-bench';work.mkdir(parents=True,exist_ok=True)
if not args.reuse:
 mirror=flight.make_mirror(work/'mirror',root=ROOT)
 with flight.flight(roc,work=work/'flight')as dep:
  (work/f'{args.label}-build.json').write_text(json.dumps({'git':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'bundle':dep[-1].rsplit('/',1)[-1],'sentinel':(mirror/'package/main.roc').read_text()}))
  for name in ['bench','alloc']:
   cmd=[roc,'build','--opt=speed',f'bench/aat-position/{name}.roc',f'--output={work/(args.label+"-"+name)}',*dep]
   if name=='alloc':cmd.insert(2,'--fuzz')
   subprocess.run(cmd,cwd=mirror,check=True)
import uharfbuzz as hb,uharfbuzz._harfbuzz as impl
lib=C.CDLL(impl.__file__);ptr=C.c_void_p;uint=C.c_uint

def define(name,arguments,result):
 f=getattr(lib,name);f.argtypes=arguments;f.restype=result;return f
blob=define('hb_blob_create',[C.c_char_p,uint,C.c_int,ptr,ptr],ptr);face=define('hb_face_create',[ptr,uint],ptr);font=define('hb_font_create',[ptr],ptr);funcs=define('hb_ot_font_set_funcs',[ptr],None);buffer=define('hb_buffer_create',[],ptr)
setlang=define('hb_buffer_set_language',[ptr,ptr],None);language=define('hb_language_from_string',[C.c_char_p,C.c_int],ptr)
subprocess.run(['cc','-O2',*(['-dynamiclib']if sys.platform=='darwin'else['-shared','-fPIC']),str(HERE/'bench.c'),'-o',str(work/'hb.so')],check=True)
measure=C.CDLL(str(work/'hb.so')).measure;measure.argtypes=[C.c_size_t]*7+[ptr,ptr,C.c_char_p,uint,uint,C.POINTER(C.c_uint64)];measure.restype=C.c_uint64
pointers=[C.cast(getattr(lib,name),ptr).value for name in ['hb_buffer_clear_contents','hb_buffer_add_utf8','hb_shape','hb_buffer_get_glyph_infos','hb_buffer_get_glyph_positions','hb_buffer_set_script','hb_buffer_set_direction']]
rows=[]
for name in ['kerx0','kerx1','kerx4-coordinate']:
 data=(ROOT/'tests/fonts/aat-position'/f'{name}.ttf').read_bytes();b=blob(data,len(data),0,None,None);f=face(b,0);h=font(f);funcs(h);buf=buffer();setlang(buf,language(b'en',-1))
 for copies in [8,64,256]:
  text=b'ab'*copies;case=work/f'{name}-{copies}.input';case.write_bytes(str(copies).encode()+b'\n'+data)
  p=subprocess.run([str(work/(args.label+'-alloc')),'replay',str(case)],capture_output=True,text=True)
  m=re.search(r'ALLOCATION_DIAGNOSTIC allocations=(\d+) leaked=(\d+) checksum=(\d+)',p.stdout+p.stderr);assert p.returncode==77 and m,(p.returncode,p.stdout+p.stderr)
  times=[];refs=[];elapsed=C.c_uint64();reps=128
  for _ in range(5):
   q=subprocess.run([str(work/(args.label+'-bench')),str(reps)],input=case.read_bytes(),capture_output=True,check=True);r=json.loads(q.stdout);assert r['checksum']==int(m[3])*reps&0xffffffffffffffff
   times.append(r['elapsed_ns']/reps);checksum=measure(*pointers,h,buf,text,len(text),reps,C.byref(elapsed));assert checksum==r['checksum'],(name,copies,checksum,r);refs.append(elapsed.value/reps)
  row={'font':name,'copies':copies,'scalars':len(text),'font_sha256':hashlib.sha256(data).hexdigest(),'allocations':int(m[1]),'leaked':int(m[2]),'requested_bytes':None,'peak_live_bytes':None,'roc_ns':statistics.median(times),'hb_ns':statistics.median(refs),'roc_to_hb':statistics.median(times)/statistics.median(refs)};rows.append(row);print(row,flush=True)
output={'build':json.loads((work/f'{args.label}-build.json').read_text()),'roc':subprocess.check_output([roc,'version'],text=True).strip(),'hb':hb.version_string(),'hb_binary_sha256':hashlib.sha256(Path(impl.__file__).read_bytes()).hexdigest(),'rows':rows,'notes':['Native loops exclude font preparation and planning; five samples and128 repetitions per size, exact full-position/cluster/glyph checksums guarded.','roc-fuzz0.4.3 exposes allocation calls/live allocation count only. Requested and peak-live bytes unavailable, not estimated.']}
(HERE/f'{args.label}.json').write_text(json.dumps(output,indent=2)+'\n')
