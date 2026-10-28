"""Record public gr_start_logging JSON data, without inspecting engine code.
The release reference must have GRAPHITE2_NTRACING=OFF. Output pointers are
renamed by initial slot order so cached observations remain reproducible.
"""
from pathlib import Path
import argparse,ctypes as C,hashlib,json,tempfile
HERE=Path(__file__).resolve().parent
def sha(data):return hashlib.sha256(data).hexdigest()
def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':')).encode()

def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--library',type=Path,default=Path('/private/tmp/graphite-geometry-reference/src/libgraphite2.dylib'));args=p.parse_args()
 cases=json.loads((HERE/'collision-cases.jsonc').read_text())['cases'];target=HERE/'collision-traces.json'
 if args.check:
  saved=json.loads(target.read_text());records={r['id']:r for r in saved['records']};assert len(records)==len(cases)
  for case in cases:
   key=sha(canonical({'case':case,'font':sha((HERE/case['font']).read_bytes()),'oracle':saved['oracle']}));assert records[case['id']]['key']==key,case['id']
  print(len(cases),'cached public trace keys current');return
 lib=C.CDLL(str(args.library));ptr=C.c_void_p;uint=C.c_uint
 def bind(name,inputs,result):f=getattr(lib,name);f.argtypes=inputs;f.restype=result;return f
 version=bind('gr_engine_version',[C.POINTER(C.c_int)]*3,None);v=[C.c_int()for _ in range(3)];version(*(C.byref(n)for n in v))
 oracle={'engine':'Graphite2','version':'.'.join(str(n.value)for n in v),'library_sha256':sha(args.library.read_bytes()),'source_archive_sha256':'7a3b342c5681921ce2e0c2496509d30b5b078399d5a7bd2358f95166d57d91df','build':'Release AppleClang17, GRAPHITE2_NTRACING=OFF, file-face enabled, direct VM','api':'gr_start_logging public JSON trace','extractor':1}
 assert oracle['version']=='1.3.14'
 make_face=bind('gr_make_file_face',[C.c_char_p,uint],ptr);drop_face=bind('gr_face_destroy',[ptr],None)
 make_seg=bind('gr_make_seg',[ptr,ptr,uint,ptr,C.c_int,ptr,C.c_size_t,C.c_int],ptr);drop_seg=bind('gr_seg_destroy',[ptr],None)
 start=bind('gr_start_logging',[ptr,C.c_char_p],C.c_bool);stop=bind('gr_stop_logging',[ptr],None)
 records=[]
 with tempfile.TemporaryDirectory(prefix='roc-graphite-public-trace-')as tmp:
  output=Path(tmp)/'trace.json'
  for case in cases:
   font=HERE/case['font'];face=make_face(str(font).encode(),0);assert face,case['id']
   try:
    assert start(face,str(output).encode()),'public logging is disabled in this reference build'
    chars=(uint*len(case['text']))(*map(ord,case['text']));segment=make_seg(None,face,0,None,4,chars,len(case['text']),3 if case['direction']=='rtl'else 2);assert segment,case['id'];drop_seg(segment);stop(face)
   finally:drop_face(face)
   trace=json.loads(output.read_text());assert len(trace)==1
   names={}
   for rendering_pass in trace[0]['passes']:
    for slot in rendering_pass.get('slots',[]):
     if slot['id']not in names:names[slot['id']]='slot-'+str(len(names)+1)
   def normalize(value):
    if isinstance(value,str):return names.get(value,value)
    if isinstance(value,list):return [normalize(v)for v in value]
    if isinstance(value,dict):return {k:normalize(v)for k,v in value.items()}
    return value
   observations=[normalize(item.get('collisions',[]))for item in trace[0]['passes']]
   records.append({'id':case['id'],'key':sha(canonical({'case':case,'font':sha(font.read_bytes()),'oracle':oracle})),'collisions':observations})
 target.write_text(json.dumps({'oracle':oracle,'records':records},indent=2)+'\n');print(len(records),'public collision traces cached')

if __name__=='__main__':main()
