"""Pin public Graphite2 no-op positions and independent SFNT facts."""
from pathlib import Path
import argparse,ctypes as C,hashlib,json,struct
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args()
def sha(b):return hashlib.sha256(b).hexdigest()
def table(data,tag):
 n=struct.unpack_from('>H',data,4)[0]
 for i in range(n):
  entry=12+16*i
  if data[entry:entry+4]==tag.encode():
   at,size=struct.unpack_from('>II',data,entry+8);assert at+size<=len(data);return data[at:at+size]
 raise AssertionError(tag)
def facts(data):
 hhea=table(data,'hhea');hmtx=table(data,'hmtx');silf=table(data,'Silf');sub=struct.unpack_from('>I',silf,12)[0];passmap=sub+struct.unpack_from('>H',silf,sub+4)[0];start=sub+struct.unpack_from('>I',silf,passmap)[0];end=sub+struct.unpack_from('>I',silf,passmap+4)[0];action=sub+struct.unpack_from('>I',silf,start+16)[0]
 assert silf[action:end]==bytes([0x1b,0x31]) and struct.unpack_from('>H',silf,start+4)[0]==1
 assert struct.unpack_from('>H',hhea,34)[0]==3 and len(hmtx)==12
 return {'sfnt_sha256':sha(data),'silf_version':struct.unpack_from('>I',silf)[0],'pass_flags':silf[start],'only_action_hex':silf[action:end].hex(),'glyph1_advance':struct.unpack_from('>H',hmtx,4)[0],'glyph2_advance':struct.unpack_from('>H',hmtx,8)[0],'full_long_metric_count':3}
files=[HERE/f'noop-{n}.ttf'for n in [0,32]]
if a.check:
 saved=json.loads((HERE/'raw-records.json').read_text())
 for path,row in zip(files,saved['records']):assert row['font']==path.name and row['facts']==facts(path.read_bytes())
 print('2 no-op raw records and unchanged table facts current');raise SystemExit(0)
path=Path('/opt/homebrew/lib/libgraphite2.dylib');lib=C.CDLL(str(path));ptr=C.c_void_p;uint=C.c_uint
def bind(name,args,result):fn=getattr(lib,name);fn.argtypes=args;fn.restype=result;return fn
face=bind('gr_make_file_face',[C.c_char_p,uint],ptr);dropface=bind('gr_face_destroy',[ptr],None);seg=bind('gr_make_seg',[ptr,ptr,uint,ptr,C.c_int,ptr,C.c_size_t,C.c_int],ptr);dropseg=bind('gr_seg_destroy',[ptr],None);first=bind('gr_seg_first_slot',[ptr],ptr);next_=bind('gr_slot_next_in_segment',[ptr],ptr);gid=bind('gr_slot_gid',[ptr],C.c_ushort);x=bind('gr_slot_origin_X',[ptr],C.c_float);ax=bind('gr_slot_advance_X',[ptr,ptr,ptr],C.c_float);total=bind('gr_seg_advance_X',[ptr],C.c_float);parent=bind('gr_slot_attached_to',[ptr],ptr);child=bind('gr_slot_first_attachment',[ptr],ptr);attr=bind('gr_slot_attr',[ptr,ptr,C.c_int,C.c_ubyte],C.c_int)
records=[]
for file in files:
 f=face(str(file).encode(),6);assert f;chars=(uint*2)(97,98);s=seg(None,f,0,None,4,chars,2,2);assert s;slots=[];slot=first(s)
 while slot:
  slots.append({'glyph':gid(slot),'origin_x':x(slot),'authored_advance_x':ax(slot,f,None),'slot_attr_advance_x':attr(slot,s,0,0),'has_parent':bool(parent(slot)),'has_child':bool(child(slot)),'shift_x':attr(slot,s,20,0),'shift_y':attr(slot,s,21,0),'justify_width':attr(slot,s,29,0),'collision_flags':attr(slot,s,57,0)});slot=next_(slot)
 records.append({'font':file.name,'facts':facts(file.read_bytes()),'face_mode':6,'segment_flags':2,'segment_advance_x':total(s),'slots':slots});dropseg(s);dropface(f)
(HERE/'raw-records.json').write_text(json.dumps({'engine':'Graphite2 1.3.14','library_sha256':sha(path.read_bytes()),'api':'public gr_make_file_face/gr_make_seg and slot accessors','records':records},indent=2)+'\n');print('2 no-op public C API records recorded')
