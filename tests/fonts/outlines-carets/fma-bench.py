"""Native timing of varied composite extents at three increasing sizes.
Requires the pinned HarfBuzz oracle Python environment and a C compiler.
A previous served-bundle artifact can be supplied with --before-bundle;
current package source is always compiled through flight's served bundle.
No Roc code is generated. See the recorded JSON for measurement limits.
"""
from pathlib import Path
import sys,subprocess,time,statistics,ctypes as C,json,os,argparse,hashlib
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'scripts'));import flight
parser=argparse.ArgumentParser(description='Native composite query timing against the pinned HarfBuzz oracle')
parser.add_argument('--roc',default=os.environ.get('ROC','roc'))
parser.add_argument('--before-bundle',type=Path)
parser.add_argument('--after-bundle',type=Path)
parser.add_argument('--output',type=Path)
args=parser.parse_args()
roc=args.roc
query=HERE/'fma-bench.roc'
fontfile=HERE.parent/'variable'/'var-outlines.ttf'
work=ROOT/'.roc-font-tmp'/'fma-bench';work.mkdir(parents=True,exist_ok=True)
labels=['before','after'] if args.before_bundle else ['after']
for label in labels:
 bundle=args.before_bundle if label=='before' else args.after_bundle
 with flight.flight(roc,bundle=bundle,work=work/(label+'-flight')) as dep:
  p=subprocess.run([roc,'build','--opt=speed',str(query),f'--output={work/(label+"-timing")}',*dep],text=True,capture_output=True,cwd=ROOT);print(p.stdout,p.stderr);assert p.returncode in (0,2)
rows=[]
# The pinned oracle Python environment supplies HarfBuzz. This script is
# run there; all timing loops below are native C or native Roc binaries.
import uharfbuzz as hb,uharfbuzz._harfbuzz as impl
lib=C.CDLL(impl.__file__);ptr=C.c_void_p;uint=C.c_uint

def define(name,args,result):
 f=getattr(lib,name);f.argtypes=args;f.restype=result;return f
blob_create=define('hb_blob_create',[C.c_char_p,uint,C.c_int,ptr,ptr],ptr)
face_create=define('hb_face_create',[ptr,uint],ptr)
font_create=define('hb_font_create',[ptr],ptr)
set_funcs=define('hb_ot_font_set_funcs',[ptr],None)
set_scale=define('hb_font_set_scale',[ptr,C.c_int,C.c_int],None)
set_variations=define('hb_font_set_variations',[ptr,ptr,uint],None)
class Variation(C.Structure):_fields_=[('tag',uint),('value',C.c_float)]
data=fontfile.read_bytes();blob=blob_create(data,len(data),0,None,None);face=face_create(blob,0);font=font_create(face);set_funcs(font);set_scale(font,1000,1000)
vs=(Variation*2)(Variation(int.from_bytes(b'wght','big'),650),Variation(int.from_bytes(b'wdth','big'),87.5));set_variations(font,vs,2)
source=HERE/'fma-bench.c';so=str(work/'harfbuzz-comparator.so')
p=subprocess.run(['cc','-O2',*(['-dynamiclib'] if sys.platform=='darwin' else ['-shared','-fPIC']),str(source),'-o',so],capture_output=True,text=True);assert p.returncode==0,p.stderr
helper=C.CDLL(so).measure_extents;helper.argtypes=[C.c_size_t,ptr,C.c_uint64,C.POINTER(C.c_uint64)];helper.restype=C.c_int64
function=C.cast(lib.hb_font_get_glyph_extents,ptr).value
elapsed=C.c_uint64();helper(function,font,10,C.byref(elapsed))
for n in [1000,4000,16000]:
 hb_times=[]
 for _ in range(7):
  total=helper(function,font,n,C.byref(elapsed));assert total==156262*n,(n,total);hb_times.append(elapsed.value/1e9)
 row={'queries':n,'hb_seconds':statistics.median(hb_times)}
 for label in labels:
  times=[]
  for _ in range(7):
   start=time.perf_counter();p=subprocess.run([str(work/(label+'-timing')),str(fontfile),str(n)],text=True,capture_output=True);times.append(time.perf_counter()-start);assert p.returncode==0,p.stderr;assert int(p.stdout)==156262*n
  row[label+'_seconds_including_startup']=statistics.median(times)
  row[label+'_to_hb_ratio']=statistics.median(times)/statistics.median(hb_times)
 rows.append(row)
 print(row,flush=True)
result={'roc':subprocess.check_output([roc,'version'],text=True).strip(),'font_sha256':hashlib.sha256(fontfile.read_bytes()).hexdigest(),'harfbuzz':hb.version_string(),'rows':rows,'note':'Native optimized Roc timings include process startup,font reading,location preparation and stdout. HarfBuzz is a warmed native C inner loop from the pinned wheel. Ratios are therefore upper bounds on the prepared-query time ratio, not a strictly equivalent microbenchmark. Use increasing-size slope and largest size; do not infer general shaping speed.'}
if args.output:args.output.write_text(json.dumps(result,indent=2)+'\n')
else:print(json.dumps(result,indent=2))
