"""Cache HB14.6's Graphite2 adapter through its public C API.
--check validates cached keys using only Python's standard library.
The reference dylib is separately built from pinned upstream MIT source;
no Graphite2 implementation code is linked into the Roc package.
"""
from pathlib import Path
import argparse,ctypes as C,hashlib,json
HERE=Path(__file__).resolve().parent.parent
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--oracle',default='downstream-gap-audit/hb-oracle.json');p.add_argument('--cases',default='downstream-gap-audit/cases.jsonc');p.add_argument('--output',default='downstream-gap-audit/hb-records.json');p.add_argument('--library',type=Path,default=Path('/private/tmp/libroc-font-hb14-graphite.dylib'));p.add_argument('--graphite-library',type=Path,default=Path('/opt/homebrew/lib/libgraphite2.dylib'));args=p.parse_args()
def sha(data):return hashlib.sha256(data).hexdigest()
def canonical(v):return json.dumps(v,sort_keys=True,separators=(',',':')).encode()
cases=json.loads((HERE/args.cases).read_text())['cases'];pin_path=HERE/args.oracle
if args.check:
 pin=json.loads(pin_path.read_text());records=json.loads((HERE/args.output).read_text())['records'];assert len(records)==len(cases)
 for case,record in zip(cases,records):
  assert record['id']==case['id']
  key=sha(canonical({'case':case,'font':sha((HERE/case['font']).read_bytes()),'oracle':pin}))
  assert record['key']==key,case['id']
 print(f'{len(cases)} HB14.6/Graphite2 shape records current');raise SystemExit(0)
hb=C.CDLL(str(args.library));ptr=C.c_void_p;uint=C.c_uint32

def bind(name,types,result):
 fn=getattr(hb,name);fn.argtypes=types;fn.restype=result;return fn
version=bind('hb_version_string',[],C.c_char_p)().decode();assert version=='14.6.0',version
list_shapers=bind('hb_shape_list_shapers',[],C.POINTER(C.c_char_p));ordered=list_shapers();priority=[];index=0
while ordered[index]:priority.append(ordered[index].decode());index+=1
graphite_face=bind('hb_graphite2_face_get_gr_face',[ptr],ptr)
class Feature(C.Structure):_fields_=[('tag',uint),('value',uint),('start',uint),('end',uint)]
class Info(C.Structure):_fields_=[('glyph',uint),('mask',uint),('cluster',uint),('var1',uint),('var2',uint)]
class Position(C.Structure):_fields_=[('ax',C.c_int32),('ay',C.c_int32),('dx',C.c_int32),('dy',C.c_int32),('var',uint)]
blob=bind('hb_blob_create',[ptr,uint,C.c_int,ptr,ptr],ptr);blob_drop=bind('hb_blob_destroy',[ptr],None)
face_make=bind('hb_face_create',[ptr,uint],ptr);face_drop=bind('hb_face_destroy',[ptr],None);upem=bind('hb_face_get_upem',[ptr],uint)
font_make=bind('hb_font_create',[ptr],ptr);font_drop=bind('hb_font_destroy',[ptr],None);font_scale=bind('hb_font_set_scale',[ptr,C.c_int,C.c_int],None);font_funcs=bind('hb_ot_font_set_funcs',[ptr],None)
make_buffer=bind('hb_buffer_create',[],ptr);drop_buffer=bind('hb_buffer_destroy',[ptr],None);add=bind('hb_buffer_add',[ptr,uint,uint],None);content=bind('hb_buffer_set_content_type',[ptr,C.c_int],None)
script=bind('hb_script_from_string',[C.c_char_p,C.c_int],uint);set_script=bind('hb_buffer_set_script',[ptr,uint],None)
direction=bind('hb_direction_from_string',[C.c_char_p,C.c_int],C.c_int);set_direction=bind('hb_buffer_set_direction',[ptr,C.c_int],None)
language=bind('hb_language_from_string',[C.c_char_p,C.c_int],ptr);set_language=bind('hb_buffer_set_language',[ptr,ptr],None);set_level=bind('hb_buffer_set_cluster_level',[ptr,C.c_int],None)
shape=bind('hb_shape_full',[ptr,ptr,C.POINTER(Feature),uint,C.POINTER(C.c_char_p)],C.c_int)
infos=bind('hb_buffer_get_glyph_infos',[ptr,C.POINTER(uint)],C.POINTER(Info));positions=bind('hb_buffer_get_glyph_positions',[ptr,C.POINTER(uint)],C.POINTER(Position))
get_flags=bind('hb_glyph_info_get_glyph_flags',[C.POINTER(Info)],uint)
graphite=C.CDLL(str(args.graphite_library));gv=graphite.gr_engine_version;gv.argtypes=[C.POINTER(C.c_int)]*3;gv.restype=None;a=C.c_int();b=C.c_int();c=C.c_int();gv(C.byref(a),C.byref(b),C.byref(c));gversion=f'{a.value}.{b.value}.{c.value}';assert gversion=='1.3.14'
pin={'harfbuzz':version,'graphite2':gversion,'shaper_priority':priority,'harfbuzz_library_sha256':sha(args.library.read_bytes()),'graphite_library_sha256':sha(args.graphite_library.read_bytes()),'extractor':2,'variations':'explicit hb_font_set_variations before shaping; captures OT glyph2 advance independently','harfbuzz_build':'clang++ -O2 -std=c++17 -fPIC -dynamiclib -DHAVE_GRAPHITE2 -I/opt/homebrew/include src/harfbuzz.cc -L/opt/homebrew/lib -lgraphite2','harfbuzz_source':'https://github.com/harfbuzz/harfbuzz/releases/tag/14.6.0'}
class Variation(C.Structure):_fields_=[('tag',uint),('value',C.c_float)]
set_variations=bind('hb_font_set_variations',[ptr,C.POINTER(Variation),uint],None)
get_advance=bind('hb_font_get_glyph_h_advance',[ptr,uint],C.c_int32)
records=[]
for case in cases:
 data=(HERE/case['font']).read_bytes();storage=C.create_string_buffer(data);bl=blob(storage,len(data),0,None,None);face=face_make(bl,0);font=font_make(face);font_funcs(font);font_scale(font,upem(face),upem(face));buf=make_buffer()
 try:
  settings_var=case.get('variations',[]);variations=(Variation*len(settings_var))(*(Variation(int.from_bytes(v['tag'].encode(),'big'),v['value'])for v in settings_var));set_variations(font,variations,len(settings_var))
  content(buf,1);offset=0;start,end=case.get('range',[0,2**64-1])
  for char in case['text']:
   if start<=offset<end:add(buf,ord(char),offset)
   offset+=len(char.encode())
  set_script(buf,script(case.get('script','Latn').encode(),-1));set_direction(buf,direction(case.get('direction','ltr').encode(),-1));set_language(buf,language(case.get('language','').encode(),-1));set_level(buf,case.get('cluster_level',0))
  settings=case.get('features',[]);features=(Feature*len(settings))(*(Feature(f['id'],f['value']&65535,0,2**32-1) for f in settings));shapers=(C.c_char_p*2)(case.get('engine','graphite2').encode(),None)
  success=bool(shape(font,buf,features,len(settings),None if case.get('engine')=='auto'else shapers));run=[]
  if success:
   n=uint();ii=infos(buf,C.byref(n));pp=positions(buf,C.byref(n))
   for index in range(n.value):
    info=ii[index];pos=pp[index];run.append({'glyph':info.glyph,'cluster':info.cluster,'advance':[pos.ax,pos.ay],'offset':[pos.dx,pos.dy],'flags':get_flags(C.byref(ii[index]))&1})
  result={'success':success,'abort':'NoAbort' if success else 'ProgramAbort','glyphs':run,'ot_glyph2_advance':get_advance(font,2),'graphite_face_available':bool(graphite_face(face))}
 finally:drop_buffer(buf);font_drop(font);face_drop(face);blob_drop(bl)
 records.append({'id':case['id'],'key':sha(canonical({'case':case,'font':sha(data),'oracle':pin})),'result':result})
pin_path.write_text(json.dumps(pin,indent=2)+'\n');(HERE/args.output).write_text('{\n\"oracle\":'+json.dumps(pin,sort_keys=True)+',\n\"records\":[\n'+',\n'.join(json.dumps(r,ensure_ascii=False,separators=(',',':')) for r in records)+'\n]\n}\n');print(f'{len(records)} HB14.6/Graphite2 shape records recorded')
