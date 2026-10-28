#!/usr/bin/env python3
"""Three-size optimized Devanagari timing/allocation evidence.
Run before model activation, then after with --label after. All consumers
compile against a served bundle. Timing excludes preparation/startup.
"""
from pathlib import Path
import argparse,ctypes as C,hashlib,json,os,re,statistics,subprocess,sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'scripts'));import flight
parser=argparse.ArgumentParser();parser.add_argument('--model',choices=['indic','khmer'],default='indic');parser.add_argument('--label',default='before');parser.add_argument('--output',type=Path);parser.add_argument('--reuse',action='store_true');args=parser.parse_args()
if args.model=='khmer':args.label='khmer-'+args.label
roc=os.environ.get('ROC','roc');work=ROOT/'.roc-font-tmp/complex-bench';work.mkdir(parents=True,exist_ok=True)
c_source=(HERE/'bench.c').read_bytes()
if not args.reuse:
 with flight.flight(roc,work=work/(args.label+'-flight')) as dep:
  (work/(args.label+'-build.json')).write_text(json.dumps({'source_git':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'bundle':dep[-1].rsplit('/',1)[-1]}))
  for name in ['bench','alloc']:
   command=[roc,'build','--opt=speed',str(HERE/(name+'.roc')),f'--output={work/(args.label+"-"+name)}',*dep]
   if name=='alloc':command.insert(2,'--fuzz')
   p=subprocess.run(command,cwd=ROOT,capture_output=True,text=True);print(p.stdout,p.stderr);assert p.returncode==0
import uharfbuzz as hb,uharfbuzz._harfbuzz as implementation
lib=C.CDLL(implementation.__file__);ptr=C.c_void_p;uint=C.c_uint

def define(name,arguments,result):
 fn=getattr(lib,name);fn.argtypes=arguments;fn.restype=result;return fn
blob_create=define('hb_blob_create',[C.c_char_p,uint,C.c_int,ptr,ptr],ptr)
face_create=define('hb_face_create',[ptr,uint],ptr);font_create=define('hb_font_create',[ptr],ptr)
set_funcs=define('hb_ot_font_set_funcs',[ptr],None);buffer_create=define('hb_buffer_create',[],ptr)
set_script=define('hb_buffer_set_script',[ptr,uint],None);set_direction=define('hb_buffer_set_direction',[ptr,C.c_int],None)
fontfile=HERE/('ComplexKhmerSans.ttf' if args.model=='khmer' else 'ComplexDevaSans.ttf');data=fontfile.read_bytes();blob=blob_create(data,len(data),0,None,None);face=face_create(blob,0);font=font_create(face);set_funcs(font)
buffer=buffer_create();set_script(buffer,int.from_bytes(b'Deva','big'));set_direction(buffer,4)
source=work/(args.label+'-hb.c');source.write_bytes(c_source);library=work/(args.label+'-hb.so')
subprocess.run(['cc','-O2',*(['-dynamiclib'] if sys.platform=='darwin' else ['-shared','-fPIC']),str(source),'-o',str(library)],check=True)
measure=C.CDLL(str(library)).measure_shapes;measure.argtypes=[C.c_size_t]*6+[ptr,ptr,C.c_char_p,uint,uint,uint,C.POINTER(C.c_uint64)];measure.restype=C.c_uint64
functions=[C.cast(getattr(lib,name),ptr).value for name in ['hb_buffer_clear_contents','hb_buffer_add_utf8','hb_shape','hb_buffer_get_glyph_infos','hb_buffer_set_script','hb_buffer_set_direction']]
rows=[]
for copies in [16,64,256]:
 text=(('ខ្មែរ ក្រុម ក្រិ ' if args.model=='khmer' else 'र्कि क्षिं हिन्दी ')*copies).encode();case=work/f'input-{copies}';case.write_bytes(str(copies).encode()+b'\n'+data)
 p=subprocess.run([str(work/(args.label+'-alloc')),'replay',str(case)],capture_output=True,text=True)
 match=re.search(r'ALLOCATION_DIAGNOSTIC allocations=(\d+) leaked=(\d+)',p.stdout+p.stderr);assert p.returncode==77 and match,p.stdout+p.stderr
 times=[];hb_times=[];elapsed=C.c_uint64();repetitions=128
 for _ in range(5):
  p=subprocess.run([str(work/(args.label+'-bench')),str(repetitions)],input=case.read_bytes(),capture_output=True);assert p.returncode==0,p.stderr
  result=json.loads(p.stdout);times.append(result['elapsed_ns']/repetitions/1e9)
  measure(*functions,font,buffer,text,len(text),repetitions,int.from_bytes(b'Khmr' if args.model=='khmer' else b'Deva','big'),C.byref(elapsed));hb_times.append(elapsed.value/repetitions/1e9)
 row={'copies':copies,'utf8_bytes':len(text),'scalar_count':len(text.decode()),'allocations':int(match[1]),'leaked':int(match[2]),'roc_seconds':statistics.median(times),'hb_seconds':statistics.median(hb_times),'roc_to_hb_ratio':statistics.median(times)/statistics.median(hb_times)};rows.append(row);print(row,flush=True)
build_metadata=work/(args.label+'-build.json')
output={'label':args.label,'measurement_git':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),**(json.loads(build_metadata.read_text()) if build_metadata.exists() else {'source_git':'unknown preserved binary'}),'roc':subprocess.check_output([roc,'version'],text=True).strip(),'hb':hb.version_string(),'font_sha256':hashlib.sha256(data).hexdigest(),'rows':rows,'notes':['Native loops, font reading/planning excluded;128 iterations and five samples per size.','Before model activation generic shaping differs from HB; ratios compare cost on identical inputs. After-model correctness is established separately by the cached oracle matrix.','roc-fuzz0.4.3 exposes allocation call counts and live allocation count only; requested bytes and peak live bytes unavailable.']}
(args.output or HERE/(args.label+'-measurements.json')).write_text(json.dumps(output,indent=2)+'\n')
