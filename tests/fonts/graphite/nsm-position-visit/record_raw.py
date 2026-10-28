"""Original public-C-API placement-marker observations; offline checks need no oracle."""
from pathlib import Path
import argparse,ctypes as C,hashlib,json,struct
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--cases',default='cases.jsonc');p.add_argument('--output',default='raw-records.json');args=p.parse_args()
sha=lambda b:hashlib.sha256(b).hexdigest()
canonical=lambda v:json.dumps(v,sort_keys=True,separators=(',',':')).encode()
def table(data,tag):
 for i in range(struct.unpack_from('>H',data,4)[0]):
  at=12+16*i
  if data[at:at+4]==tag.encode():
   start,size=struct.unpack_from('>II',data,at+8);assert start+size<=len(data);return data[start:start+size]
 raise AssertionError(tag)
def facts(data):
 silf=table(data,'Silf');sub=struct.unpack_from('>I',silf,12)[0];pm=sub+struct.unpack_from('>H',silf,sub+4)[0];start=sub+struct.unpack_from('>I',silf,pm)[0];end=sub+struct.unpack_from('>I',silf,pm+4)[0];act=sub+struct.unpack_from('>I',silf,start+16)[0]
 assert struct.unpack_from('>H',table(data,'hhea'),34)[0]==3 and len(table(data,'hmtx'))==12
 assert struct.unpack_from('>HHH',silf,start+40)==(1,2,0)
 assert table(data,'Glat')==struct.pack('>I',0x10000)+b''.join(bytes([1,1])+struct.pack('>h',n)for n in [0,3,16])
 return {'sfnt_sha256':sha(data),'version':struct.unpack_from('>I',silf)[0],'native':silf[sub+32],'flags':silf[start],'action_hex':silf[act:end].hex(),'advances':[struct.unpack_from('>H',table(data,'hmtx'),i*4)[0]for i in range(3)],'match_range':[1,2]}
cases=json.loads((HERE/args.cases).read_text())['cases'];target=HERE/args.output
if args.check:
 saved=json.loads(target.read_text());assert len(saved['records'])==len(cases)
 for case,record in zip(cases,saved['records']):
  f=facts((HERE/case['font']).read_bytes());assert record['id']==case['id'] and record['facts']==f
  assert record['key']==sha(canonical({'case':case,'facts':f,'library_sha256':saved['library_sha256']}))
  expected=17 if '-y17/'in case['id']else 0
  assert all(s['shift_y']==expected and not s['parent'] and not s['child']for s in record['result']['slots'])
 print(f'{len(cases)} raw placement observations and independent font facts current');raise SystemExit(0)
path=Path('/opt/homebrew/lib/libgraphite2.dylib');lib=C.CDLL(str(path));ptr=C.c_void_p

def bind(n,a,r):f=getattr(lib,n);f.argtypes=a;f.restype=r;return f
version=bind('gr_engine_version',[C.POINTER(C.c_int)]*3,None);a=C.c_int();b=C.c_int();c=C.c_int();version(C.byref(a),C.byref(b),C.byref(c));assert(a.value,b.value,c.value)==(1,3,14)
face=bind('gr_make_file_face',[C.c_char_p,C.c_uint],ptr);seg=bind('gr_make_seg',[ptr,ptr,C.c_uint,ptr,C.c_int,ptr,C.c_size_t,C.c_int],ptr);first=bind('gr_seg_first_slot',[ptr],ptr);next_=bind('gr_slot_next_in_segment',[ptr],ptr);gid=bind('gr_slot_gid',[ptr],C.c_ushort);total=bind('gr_seg_advance_X',[ptr],C.c_float);x=bind('gr_slot_origin_X',[ptr],C.c_float);y=bind('gr_slot_origin_Y',[ptr],C.c_float);attr=bind('gr_slot_attr',[ptr,ptr,C.c_int,C.c_ubyte],C.c_int);parent=bind('gr_slot_attached_to',[ptr],ptr);child=bind('gr_slot_first_attachment',[ptr],ptr);dropseg=bind('gr_seg_destroy',[ptr],None);dropface=bind('gr_face_destroy',[ptr],None)
bits=lambda value:struct.unpack('>I',struct.pack('>f',value))[0]
libsha=sha(path.read_bytes());rows=[]
for case in cases:
 fc=face(str(HERE/case['font']).encode(),6);assert fc;chars=(C.c_uint*len(case['text']))(*map(ord,case['text']));s=seg(None,fc,0,None,4,chars,len(case['text']),3 if case.get('direction')=='rtl'else 2);assert s;slots=[];slot=first(s)
 while slot:
  slots.append({'glyph':gid(slot),'position_bits':[bits(x(slot)),bits(y(slot))],'shift_y':attr(slot,s,21,0),'parent':bool(parent(slot)),'child':bool(child(slot))});slot=next_(slot)
 f=facts((HERE/case['font']).read_bytes());rows.append({'id':case['id'],'facts':f,'key':sha(canonical({'case':case,'facts':f,'library_sha256':libsha})),'result':{'advance_x_bits':bits(total(s)),'slots':slots}});dropseg(s);dropface(fc)
target.write_text(json.dumps({'engine':'Graphite2 1.3.14','face_mode':6,'segment_flags':2 if all(c.get('direction')!='rtl'for c in cases)else '2 LTR / 3 RTL','library_sha256':libsha,'records':rows},indent=2)+'\n');print(f'{len(cases)} original placement observations recorded')
