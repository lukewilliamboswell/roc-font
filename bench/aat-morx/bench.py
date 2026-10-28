#!/usr/bin/env python3
"""Three-size optimized Apple timing/allocation evidence.
Use --model jp|positioning|mong; --reuse-from jp-after reuses both native apps. All consumers
compile against a served bundle. Timing excludes preparation/startup.
"""
from pathlib import Path
import argparse,ctypes as C,hashlib,json,os,re,statistics,subprocess,sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
sys.path.insert(0,str(ROOT/'scripts'));import flight
parser=argparse.ArgumentParser();parser.add_argument('--model',choices=['direct','context','ligature','insertion','rearrange','tracking','tamil'],default='direct');parser.add_argument('--label',default='after');parser.add_argument('--output',type=Path);parser.add_argument('--reuse',action='store_true');parser.add_argument('--reuse-from');parser.add_argument('--bundle',type=Path);parser.add_argument('--check',action='store_true');args=parser.parse_args()
args.label=args.model+'-'+args.label
artifact_label=args.reuse_from or args.label
if args.reuse_from:args.reuse=True
roc=os.environ.get('ROC','roc');work=ROOT/'.roc-font-tmp/aat-morx-bench';work.mkdir(parents=True,exist_ok=True)
c_source=(HERE/'bench.c').read_bytes()
if not args.reuse:
 with flight.flight(roc,bundle=args.bundle,work=work/(args.label+'-flight')) as dep:
  (work/(args.label+'-build.json')).write_text(json.dumps({'source_git':('external immutable bundle' if args.bundle else subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()),'bundle':dep[-1].rsplit('/',1)[-1]}))
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
models=['direct','context','ligature','insertion','rearrange','tracking','tamil']
fontfile=ROOT/'tests/fonts/aat'/({'tamil':'NotoSansTamilMN.ttf','tracking':'tracking-1--65536.ttf'}.get(args.model,args.model+'-logical.ttf'));data=fontfile.read_bytes();blob=blob_create(data,len(data),0,None,None);face=face_create(blob,0);font=font_create(face);set_funcs(font)
buffer=buffer_create();set_script(buffer,int.from_bytes(b'Deva','big'));set_direction(buffer,4)
source=work/(args.label+'-hb.c');source.write_bytes(c_source);library=work/(args.label+'-hb.so')
subprocess.run(['cc','-O2',*(['-dynamiclib'] if sys.platform=='darwin' else ['-shared','-fPIC']),str(source),'-o',str(library)],check=True)
measure=C.CDLL(str(library)).measure_shapes;measure.argtypes=[C.c_size_t]*7+[ptr,ptr,C.c_char_p,uint,uint,uint,C.POINTER(C.c_uint64)];measure.restype=C.c_uint64
functions=[C.cast(getattr(lib,name),ptr).value for name in ['hb_buffer_clear_contents','hb_buffer_add_utf8','hb_shape','hb_buffer_get_glyph_infos','hb_buffer_get_glyph_positions','hb_buffer_set_script','hb_buffer_set_direction']]
reference_font=hb.Font(hb.Face(data));hb.ot_font_set_funcs(reference_font);reference_font.ptem=24
set_ptem=define('hb_font_set_ptem',[ptr,C.c_float],None);set_ptem(font,24)
rows=[]
for copies in [16,64,256]:
 text=(('தமிழ் மொழி' if args.model=='tamil' else 'a\u0301b' if args.model=='tracking' else 'ab')*copies).encode();case=work/f'input-{copies}';case.write_bytes((str(models.index(args.model))+str(copies)).encode()+b'\n'+data)
 p=subprocess.run([str(work/(artifact_label+'-alloc')),'replay',str(case)],capture_output=True,text=True)
 match=re.search(r'ALLOCATION_DIAGNOSTIC allocations=(\d+) leaked=(\d+)',p.stdout+p.stderr);assert p.returncode==77 and match,p.stdout+p.stderr
 times=[];hb_times=[];elapsed=C.c_uint64();repetitions=128
 reference_buffer=hb.Buffer();reference_buffer.add_utf8(text);reference_buffer.direction='ltr';reference_buffer.script='Taml' if args.model=='tamil' else 'Latn';hb.shape(reference_font,reference_buffer)
 reference_checksum=sum(info.codepoint+info.cluster+pos.x_advance+pos.y_advance+pos.x_offset+pos.y_offset for info,pos in zip(reference_buffer.glyph_infos,reference_buffer.glyph_positions))&0xFFFFFFFFFFFFFFFF
 digest=5381
 for byte in text:digest=(digest*33+byte)&0xFFFFFFFFFFFFFFFF
 for _ in range(5):
  p=subprocess.run([str(work/(artifact_label+'-bench')),str(repetitions)],input=case.read_bytes(),capture_output=True);assert p.returncode==0,p.stderr
  result=json.loads(p.stdout);assert result['script']==('Taml' if args.model=='tamil' else 'Latn') and result['direction']=='ltr' and result['utf8_bytes']==len(text) and result['input_checksum']==digest and result['successes']==repetitions and result['checksum']==((reference_checksum*repetitions)&0xFFFFFFFFFFFFFFFF),result;times.append(result['elapsed_ns']/repetitions/1e9)
  observed=measure(*functions,font,buffer,text,len(text),repetitions,int.from_bytes(b'Taml' if args.model=='tamil' else b'Latn','big'),C.byref(elapsed));assert observed==((reference_checksum*repetitions)&0xFFFFFFFFFFFFFFFF);hb_times.append(elapsed.value/repetitions/1e9)
 row={'case_sha256':hashlib.sha256(case.read_bytes()).hexdigest(),'copies':copies,'utf8_bytes':len(text),'scalar_count':len(text.decode()),'input_checksum':digest,'output_checksum':reference_checksum,'requested_bytes':None,'peak_live_bytes':None,'allocations':int(match[1]),'leaked':int(match[2]),'roc_seconds':statistics.median(times),'hb_seconds':statistics.median(hb_times),'roc_to_hb_ratio':statistics.median(times)/statistics.median(hb_times)};rows.append(row);print(row,flush=True)
if args.check:
 baseline=json.loads((ROOT/'bench/baseline.json').read_text()).get('feature_cases',{})
 for row in rows:
  key=f"aat-morx/{args.model}/{row['copies']}"
  expected=baseline.get(key)
  assert expected is not None, f"missing allocation baseline {key}"
  assert expected['font_sha256']==hashlib.sha256(data).hexdigest() and expected['case_sha256']==row['case_sha256'], f"allocation input changed {key}"
  assert row['allocations']==expected['allocations'] and row['leaked']==0, f"allocation count changed {key}: {expected['allocations']} -> {row['allocations']}; record an explicit baseline update"
build_metadata=work/(artifact_label+'-build.json')
output={'label':args.label,'measurement_git':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),**(json.loads(build_metadata.read_text()) if build_metadata.exists() else {'source_git':'unknown preserved binary'}),'roc':subprocess.check_output([roc,'version'],text=True).strip(),'hb':hb.version_string(),'font_sha256':hashlib.sha256(data).hexdigest(),'rows':rows,'notes':['Native loops, font reading/planning excluded;128 iterations and five samples per size.','Correctness is checked separately through cached Apple oracle matrices; inputs, script and horizontal direction are guarded in both native loops.','roc-fuzz0.4.3 exposes allocation call counts and live allocation count only; requested bytes and peak live bytes unavailable.']}
(args.output or HERE/(args.label+'-measurements.json')).write_text(json.dumps(output,indent=2)+'\n')
