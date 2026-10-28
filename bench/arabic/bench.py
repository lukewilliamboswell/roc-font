#!/usr/bin/env python3
"""Three-size optimized Arabic fallback and Syriac stretch evidence.
Run before model activation, then after with --label after. All consumers
compile against a served bundle. Timing excludes preparation/startup.
"""
from pathlib import Path
import argparse,ctypes as C,hashlib,json,os,re,statistics,subprocess,sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
sys.path.insert(0,str(ROOT/'scripts'));import flight
parser=argparse.ArgumentParser();parser.add_argument('--font',type=Path,required=True);parser.add_argument('--script',choices=['Arab','Syrc'],required=True);parser.add_argument('--label',default='after');parser.add_argument('--output',type=Path,required=True);parser.add_argument('--reuse',action='store_true');parser.add_argument('--binary-label');parser.add_argument('--bundle',type=Path);parser.add_argument('--source-revision');args=parser.parse_args()
args.label=args.script+'-'+args.label
binary_label=args.binary_label or args.label
roc=os.environ.get('ROC','roc');work=ROOT/'.roc-font-tmp/arabic-bench';work.mkdir(parents=True,exist_ok=True)
c_source=(HERE/'bench.c').read_bytes()
if not args.reuse:
 with flight.flight(roc,bundle=args.bundle,work=work/(args.label+'-flight')) as dep:
  (work/(binary_label+'-build.json')).write_text(json.dumps({'source_git':('external immutable bundle' if args.bundle else subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()),'bundle':dep[-1].rsplit('/',1)[-1]}))
  for name in ['bench','alloc']:
   command=[roc,'build','--opt=speed',str(HERE/(name+'.roc')),f'--output={work/(binary_label+"-"+name)}',*dep]
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
fontfile=args.font;data=fontfile.read_bytes();blob=blob_create(data,len(data),0,None,None);face=face_create(blob,0);font=font_create(face);set_funcs(font)
buffer=buffer_create();set_script(buffer,int.from_bytes(args.script.encode(),'big'));set_direction(buffer,5)
source=work/(args.label+'-hb.c');source.write_bytes(c_source);library=work/(args.label+'-hb.so')
subprocess.run(['cc','-O2',*(['-dynamiclib'] if sys.platform=='darwin' else ['-shared','-fPIC']),str(source),'-o',str(library)],check=True)
measure=C.CDLL(str(library)).measure_shapes;measure.argtypes=[C.c_size_t]*6+[ptr,ptr,C.c_char_p,uint,uint,uint,C.POINTER(C.c_uint64)];measure.restype=C.c_uint64
functions=[C.cast(getattr(lib,name),ptr).value for name in ['hb_buffer_clear_contents','hb_buffer_add_utf8','hb_shape','hb_buffer_get_glyph_infos','hb_buffer_set_script','hb_buffer_set_direction']]
rows=[]
for copies in [16,64,256]:
 text=(('\u070fܐܒܕܪ ' if args.script=='Syrc' else 'ببب لاب ')*copies).encode();case=work/f'input-{copies}';case.write_bytes(str(copies).encode()+b'\n'+args.script.encode()+b'\n'+data)
 p=subprocess.run([str(work/(binary_label+'-alloc')),'replay',str(case)],capture_output=True,text=True)
 match=re.search(r'ALLOCATION_DIAGNOSTIC allocations=(\d+) leaked=(\d+)',p.stdout+p.stderr);assert p.returncode==77 and match,p.stdout+p.stderr
 times=[];hb_times=[];elapsed=C.c_uint64();repetitions=128
 digest=5381
 for byte in text:digest=(digest*33+byte)&0xFFFFFFFFFFFFFFFF
 for _ in range(5):
  p=subprocess.run([str(work/(binary_label+'-bench')),str(repetitions)],input=case.read_bytes(),capture_output=True);assert p.returncode==0,p.stderr
  result=json.loads(p.stdout);assert result['direction']=='rtl' and result['script']==args.script and result['utf8_bytes']==len(text) and result['input_checksum']==digest,result;times.append(result['elapsed_ns']/repetitions/1e9)
  measure(*functions,font,buffer,text,len(text),repetitions,int.from_bytes(args.script.encode(),'big'),C.byref(elapsed));hb_times.append(elapsed.value/repetitions/1e9)
 row={'copies':copies,'utf8_bytes':len(text),'scalar_count':len(text.decode()),'input_checksum':digest,'allocations':int(match[1]),'leaked':int(match[2]),'roc_seconds':statistics.median(times),'hb_seconds':statistics.median(hb_times),'roc_to_hb_ratio':statistics.median(times)/statistics.median(hb_times)};rows.append(row);print(row,flush=True)
build_metadata=work/(binary_label+'-build.json')
output={'label':args.label,'source_revision':args.source_revision,'bundle_archive_sha256':hashlib.sha256(args.bundle.read_bytes()).hexdigest() if args.bundle else None,'consumer_sha256':{name:hashlib.sha256((HERE/name).read_bytes()).hexdigest() for name in ['ArabicBench.roc','bench.roc','alloc.roc','bench.c']},'measurement_git':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),**(json.loads(build_metadata.read_text()) if build_metadata.exists() else {'source_git':'unknown preserved binary'}),'roc':subprocess.check_output([roc,'version'],text=True).strip(),'hb':hb.version_string(),'font_file':str(args.font),'font_sha256':hashlib.sha256(data).hexdigest(), 'binary_sha256':{name:hashlib.sha256((work/(binary_label+'-'+name)).read_bytes()).hexdigest() for name in ['bench','alloc']},'rows':rows,'notes':['Native loops, font reading/planning excluded;128 iterations and five samples per size.','Correctness is established separately by cached full-position and flag oracle matrices; ratios compare native loops on identical text/font bytes.','roc-fuzz0.4.3 exposes allocation call counts and live allocation count only; requested bytes and peak live bytes unavailable.']}
(args.output or HERE/(args.label+'-measurements.json')).write_text(json.dumps(output,indent=2)+'\n')
