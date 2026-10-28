"""Record original Graphite program abort witnesses through the public C API.
--check verifies cached keys without loading Graphite2. Runtime code is original;
only documented ABI calls enter the separately installed reference library.
"""
from pathlib import Path
import argparse,ctypes as C,hashlib,json,struct
HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');parser.add_argument('--library',type=Path,default=Path('/opt/homebrew/lib/libgraphite2.dylib'));parser.add_argument('--cases',default='abort-cases.jsonc');parser.add_argument('--output',default='abort-records.json');args=parser.parse_args()
def digest(data):return hashlib.sha256(data).hexdigest()
def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':')).encode()
cases=json.loads((HERE/args.cases).read_text())['cases']
pin=json.loads((HERE/'oracle.json').read_text()) if (HERE/'oracle.json').exists() else None
if args.check:
 assert pin is not None
 records={r['id']:r for r in json.loads((HERE/args.output).read_text())['records']}
 for case in cases:
  sha=digest((HERE/case['font']).read_bytes());key=digest(canonical({'case':case,'font':sha,'oracle':pin}))
  assert records[case['id']]['key']==key,case['id']
 print(f'{len(cases)} Graphite2 abort/control records current')
 raise SystemExit(0)
library=C.CDLL(str(args.library));ptr=C.c_void_p;uint=C.c_uint;floating=C.c_float
def bind(name,arguments,result):
 f=getattr(library,name);f.argtypes=arguments;f.restype=result;return f
version=bind('gr_engine_version',[C.POINTER(C.c_int)]*3,None);major=C.c_int();minor=C.c_int();patch=C.c_int();version(C.byref(major),C.byref(minor),C.byref(patch))
pin={'engine':'Graphite2','version':f'{major.value}.{minor.value}.{patch.value}','library_sha256':digest(args.library.read_bytes()),'extractor':1}
assert pin['version']=='1.3.14',pin
make_face=bind('gr_make_file_face',[C.c_char_p,uint],ptr);drop_face=bind('gr_face_destroy',[ptr],None)
feature_values=bind('gr_face_featureval_for_lang',[ptr,uint],ptr);drop_values=bind('gr_featureval_destroy',[ptr],None)
find_feature=bind('gr_face_find_fref',[ptr,uint],ptr);set_feature=bind('gr_fref_set_feature_value',[ptr,C.c_ushort,ptr],C.c_int);get_feature=bind('gr_fref_feature_value',[ptr,ptr],C.c_ushort)
make_segment=bind('gr_make_seg',[ptr,ptr,uint,ptr,C.c_int,ptr,C.c_size_t,C.c_int],ptr);drop_segment=bind('gr_seg_destroy',[ptr],None)
first=bind('gr_seg_first_slot',[ptr],ptr);next_slot=bind('gr_slot_next_in_segment',[ptr],ptr)
gid=bind('gr_slot_gid',[ptr],C.c_ushort);before=bind('gr_slot_before',[ptr],C.c_int);after=bind('gr_slot_after',[ptr],C.c_int)
x=bind('gr_slot_origin_X',[ptr],floating);y=bind('gr_slot_origin_Y',[ptr],floating);advance_x=bind('gr_slot_advance_X',[ptr,ptr,ptr],floating);advance_y=bind('gr_slot_advance_Y',[ptr,ptr,ptr],floating)
segment_x=bind('gr_seg_advance_X',[ptr],floating);segment_y=bind('gr_seg_advance_Y',[ptr],floating)
records=[]
for case in cases:
 path=HERE/case['font'];face=make_face(str(path).encode(),0);result={'face_accepted':bool(face),'features':[],'segment':False,'slots':[]}
 if face:
  values=feature_values(face,0)
  try:
   for setting in case.get('features',[]):
    ref=find_feature(face,setting['id']);accepted=bool(ref and set_feature(ref,setting['value']&65535,values));result['features'].append({**setting,'accepted':accepted,'effective':get_feature(ref,values) if ref else None})
   chars=(uint*len(case['text']))(*map(ord,case['text']))
   segment=make_segment(None,face,0,values,4,chars,len(case['text']),2)
   result['segment']=bool(segment)
   if segment:
    try:
     result['advance']={'x':segment_x(segment),'y':segment_y(segment)};slot=first(segment)
     while slot:
      result['slots'].append({'glyph':gid(slot),'before':before(slot),'after':after(slot),'x':x(slot),'y':y(slot),'advance_x':advance_x(slot,face,None),'advance_y':advance_y(slot,face,None)});slot=next_slot(slot)
    finally:drop_segment(segment)
   else:result['abort']='ProgramAbort'
  finally:drop_values(values);drop_face(face)
 records.append({'id':case['id'],'font_sha256':digest(path.read_bytes()),'key':digest(canonical({'case':case,'font':digest(path.read_bytes()),'oracle':pin})),'result':result})
(HERE/'oracle.json').write_text(json.dumps(pin,indent=2)+'\n')
(HERE/args.output).write_text(json.dumps({'oracle':pin,'records':records},indent=2)+'\n')
print(f'{len(records)} Graphite2 abort/control records recorded')
