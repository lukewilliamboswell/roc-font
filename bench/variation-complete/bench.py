"""Three-size native metric/normalization measurements with exact checksums.
Binaries are built sequentially against an immutable served bundle in a
source-sentinel mirror. --reuse uses those prepared binaries.
"""
from pathlib import Path
import argparse,ctypes as C,hashlib,json,os,re,statistics,subprocess,sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
sys.path.insert(0,str(ROOT/'scripts'));import flight
ap=argparse.ArgumentParser();ap.add_argument('--reuse',action='store_true');args=ap.parse_args()
roc=os.environ.get('ROC','roc');work=ROOT/'.roc-font-tmp/variation-final';work.mkdir(parents=True,exist_ok=True)
if not args.reuse:
 mirror=flight.make_mirror(work/'mirror',root=ROOT)
 with flight.flight(roc,work=work/'flight')as dep:
  (work/'build.json').write_text(json.dumps({'bundle':dep[-1].rsplit('/',1)[-1],'git':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'source_sentinel':(mirror/'package/main.roc').read_text()}))
  for name in ['bench','alloc']:
   cmd=[roc,'build','--opt=speed',str(mirror/'bench/variation-complete'/f'{name}.roc'),f'--output={work/name}',*dep]
   if name=='alloc':cmd.insert(2,'--fuzz')
   subprocess.run(cmd,cwd=mirror,check=True)
import uharfbuzz as hb,uharfbuzz._harfbuzz as impl
lib=C.CDLL(impl.__file__);ptr=C.c_void_p;uint=C.c_uint
class Variation(C.Structure):_fields_=[('tag',uint),('value',C.c_float)]
def define(name,arguments,result):
 f=getattr(lib,name);f.argtypes=arguments;f.restype=result;return f
blob=define('hb_blob_create',[C.c_char_p,uint,C.c_int,ptr,ptr],ptr)
face=define('hb_face_create',[ptr,uint],ptr);font=define('hb_font_create',[ptr],ptr)
funcs=define('hb_ot_font_set_funcs',[ptr],None);setvar=define('hb_font_set_variations',[ptr,C.POINTER(Variation),uint],None)
destroyfont=define('hb_font_destroy',[ptr],None);destroyface=define('hb_face_destroy',[ptr],None);destroyblob=define('hb_blob_destroy',[ptr],None)
subprocess.run(['cc','-O2',*(['-dynamiclib']if sys.platform=='darwin'else['-shared','-fPIC']),str(HERE/'bench.c'),'-o',str(work/'hb.so')],check=True)
measure=C.CDLL(str(work/'hb.so')).measure;measure.argtypes=[C.c_size_t]*3+[ptr,uint,uint,C.POINTER(C.c_uint64)];measure.restype=C.c_uint64
pointers=[C.cast(getattr(lib,n),ptr).value for n in ['hb_font_get_glyph_h_advance','hb_font_set_variations','hb_font_get_var_coords_normalized']]
rows=[]
for kind,sizes in [('sparse',[4,64,512]),('all',[4,64,512]),('axes',[8,32,128]),('avar',[8,32,128])]:
 for size in sizes:
  path=ROOT/'tests/fonts/variation-complete'/f'{"axes"if kind=="axes"else"avar-regions"if kind=="avar"else"phantom-"+kind}-{size}.ttf';data=path.read_bytes();b=blob(data,len(data),0,None,None);f=face(b,0);h=font(f);funcs(h)
  axis=kind in ['axes','avar'];v=Variation(0x30303030 if kind=='axes'else int.from_bytes(b'wght','big'),.5 if axis else 1);setvar(h,C.byref(v),1)
  case=work/f'{kind}-{size}.input';case.write_bytes((b'axis'if kind=='axes'else b'avar'if kind=='avar'else b'phantom')+b'\n'+data)
  p=subprocess.run([str(work/'alloc'),'replay',str(case)],capture_output=True,text=True)
  m=re.search(r'ALLOCATION_DIAGNOSTIC allocations=(\d+) leaked=(\d+) checksum=(\d+)',p.stdout+p.stderr);assert p.returncode==77 and m,(p.returncode,p.stdout+p.stderr)
  target=16384+size*16 if kind=='avar'else 8192 if axis else 610;assert int(m[3])==target
  times=[];refs=[];elapsed=C.c_uint64();reps=10000 if axis else 100000
  for _ in range(5):
   q=subprocess.run([str(work/'bench'),str(reps)],input=case.read_bytes(),capture_output=True,check=True);result=json.loads(q.stdout);assert result['checksum']==target*reps
   times.append(result['elapsed_ns']/reps)
   check=measure(*pointers,h,2 if kind=='avar'else int(axis),reps,C.byref(elapsed));assert check==target*reps,(check,target,reps);refs.append(elapsed.value/reps)
  row={'kind':kind,'size':size,'font_sha256':hashlib.sha256(data).hexdigest(),'iterations':reps,'samples':5,'checksum_per_call':target,'allocations':int(m[1]),'leaked':int(m[2]),'requested_bytes':None,'peak_live_bytes':None,'roc_ns':statistics.median(times),'hb_ns':statistics.median(refs),'roc_to_hb':statistics.median(times)/statistics.median(refs)}
  rows.append(row);print(row,flush=True);destroyfont(h);destroyface(f);destroyblob(b)
output={'build':json.loads((work/'build.json').read_text()),'roc':subprocess.check_output([roc,'version'],text=True).strip(),'hb':hb.version_string(),'oracle_binary_sha256':hashlib.sha256(Path(impl.__file__).read_bytes()).hexdigest(),'rows':rows,'notes':['Native loops time only querying/prepared-location changes. Font reading/startup excluded. Five samples per size, exact checksums guarded.','No previous correct public noHVAR gvar metric fallback or avar2 API existed; compare with pinned HB and enforce scaling rather than compare incorrect previous output.','roc-fuzz0.4.3 reports allocation call/live counts only; requested bytes and peak live bytes are unavailable, not estimated.']}
(HERE/'native.json').write_text(json.dumps(output,indent=2)+'\n')
