"""Cache compact full-run hashes through the pinned public HB Graphite API."""
from pathlib import Path
import argparse,ctypes as C,hashlib,json,struct
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--library',type=Path,default=Path('/private/tmp/libroc-font-hb14-graphite.dylib'));a=p.parse_args()
def sha(data):return hashlib.sha256(data).hexdigest()
fontpath=HERE/'large-advance.ttf';data=fontpath.read_bytes();target=HERE/'records.json'
if a.check:
 cached=json.loads(target.read_text());assert cached['font_sha256']==sha(data)
 assert [r['n'] for r in cached['results']]==[32767,32768,32769,32770,32771]
 for row in cached['results']:
  assert row['count']==row['n'] and row['success'] and row['input_sha256']==sha(b'b'*row['n'])
  assert len(row['rows_sha256_be_IIiiii'])==64 and len(row['flags_sha256'])==64
 print('5 compact full-run conversion records current');raise SystemExit(0)
pin=json.loads((HERE.parent/'graphite/shape-oracle.json').read_text());assert sha(a.library.read_bytes())==pin['harfbuzz_library_sha256']
hb=C.CDLL(str(a.library));ptr=C.c_void_p;u=C.c_uint
def bind(name,args,result):
 fn=getattr(hb,name);fn.argtypes=args;fn.restype=result;return fn
assert bind('hb_version_string',[],C.c_char_p)()==b'14.6.0'
class Info(C.Structure):_fields_=[('glyph',u),('mask',u),('cluster',u),('a',u),('b',u)]
class Position(C.Structure):_fields_=[('ax',C.c_int32),('ay',C.c_int32),('dx',C.c_int32),('dy',C.c_int32),('var',u)]
storage=C.create_string_buffer(data);blob=bind('hb_blob_create',[ptr,u,C.c_int,ptr,ptr],ptr)(storage,len(data),0,None,None)
face=bind('hb_face_create',[ptr,u],ptr)(blob,0);font=bind('hb_font_create',[ptr],ptr)(face)
bind('hb_ot_font_set_funcs',[ptr],None)(font);bind('hb_font_set_scale',[ptr,C.c_int,C.c_int],None)(font,1000,1000)
make=bind('hb_buffer_create',[],ptr);add=bind('hb_buffer_add_utf8',[ptr,C.c_char_p,C.c_int,u,C.c_int],None);guess=bind('hb_buffer_guess_segment_properties',[ptr],None)
shape=bind('hb_shape_full',[ptr,ptr,ptr,u,C.POINTER(C.c_char_p)],C.c_int);infos=bind('hb_buffer_get_glyph_infos',[ptr,C.POINTER(u)],C.POINTER(Info));positions=bind('hb_buffer_get_glyph_positions',[ptr,C.POINTER(u)],C.POINTER(Position));flags=bind('hb_glyph_info_get_glyph_flags',[C.POINTER(Info)],u)
drop=bind('hb_buffer_destroy',[ptr],None);results=[]
for n in [32767,32768,32769,32770,32771]:
 text=b'b'*n;buffer=make();add(buffer,text,len(text),0,len(text));guess(buffer);shapers=(C.c_char_p*2)(b'graphite2',None);success=bool(shape(font,buffer,None,0,shapers));count=u();ii=infos(buffer,C.byref(count));pp=positions(buffer,C.byref(count));digest=hashlib.sha256();flag_digest=hashlib.sha256();total=0;samples=[]
 for i in range(count.value):
  row=[ii[i].glyph,ii[i].cluster,pp[i].ax,pp[i].ay,pp[i].dx,pp[i].dy];digest.update(struct.pack('>IIiiii',*row));flag_digest.update(bytes([flags(C.byref(ii[i]))&1]));total+=pp[i].ax
  if i<3 or i>=count.value-3:samples.append({'index':i,'row':row})
 results.append({'n':n,'input_sha256':sha(text),'success':success,'count':count.value,'sum_advances_i64':total,'rows_sha256_be_IIiiii':digest.hexdigest(),'flags_sha256':flag_digest.hexdigest(),'samples':samples});drop(buffer)
bind('hb_font_destroy',[ptr],None)(font);bind('hb_face_destroy',[ptr],None)(face);bind('hb_blob_destroy',[ptr],None)(blob)
target.write_text(json.dumps({'oracle':pin,'font_sha256':sha(data),'results':results},indent=2)+'\n');print('5 compact full-run conversion records recorded')
