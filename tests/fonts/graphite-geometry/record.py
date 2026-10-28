"""Cache public Graphite2 C-API geometry, never implementation internals."""
from pathlib import Path
import argparse,ctypes as C,hashlib,json,struct
HERE=Path(__file__).resolve().parent
def sha(data):return hashlib.sha256(data).hexdigest()
def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':')).encode()
def bits(value):return struct.unpack('>I',struct.pack('>f',value))[0]

def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--cases',default='geometry-cases.jsonc');p.add_argument('--output',default='geometry-records.json');p.add_argument('--library',type=Path,default=Path('/opt/homebrew/lib/libgraphite2.dylib'));p.add_argument('--slot-insertion',action='store_true');args=p.parse_args()
 cases=json.loads((HERE/args.cases).read_text())['cases'];output=HERE/args.output
 if args.check:
  saved=json.loads(output.read_text());records={r['id']:r for r in saved['records']}
  assert len(records)==len(cases)
  for case in cases:
   font_sha=sha((HERE/case['font']).read_bytes())
   assert records[case['id']]['key']==sha(canonical({'case':case,'font':font_sha,'oracle':saved['oracle']})),case['id']
  print(f'{len(cases)} cached Graphite geometry keys current');return
 lib=C.CDLL(str(args.library));ptr=C.c_void_p;uint=C.c_uint;floating=C.c_float
 def bind(name,inputs,result):f=getattr(lib,name);f.argtypes=inputs;f.restype=result;return f
 version=bind('gr_engine_version',[C.POINTER(C.c_int)]*3,None);v=[C.c_int()for _ in range(3)];version(*(C.byref(n)for n in v))
 oracle={'engine':'Graphite2','version':'.'.join(str(n.value)for n in v),'library_sha256':sha(args.library.read_bytes()),'api':'public C ABI, gr_nobidi, native font direction','extractor':1}
 assert oracle['version']=='1.3.14',oracle
 if args.slot_insertion:oracle['slot_insertion']=True
 face_new=bind('gr_make_file_face',[C.c_char_p,uint],ptr);face_drop=bind('gr_face_destroy',[ptr],None)
 seg_new=bind('gr_make_seg',[ptr,ptr,uint,ptr,C.c_int,ptr,C.c_size_t,C.c_int],ptr);seg_drop=bind('gr_seg_destroy',[ptr],None)
 first=bind('gr_seg_first_slot',[ptr],ptr);next_=bind('gr_slot_next_in_segment',[ptr],ptr)
 glyph=bind('gr_slot_gid',[ptr],C.c_ushort);before=bind('gr_slot_before',[ptr],C.c_int);after=bind('gr_slot_after',[ptr],C.c_int)
 origin=[bind('gr_slot_origin_'+axis,[ptr],floating)for axis in 'XY'];advance=[bind('gr_slot_advance_'+axis,[ptr,ptr,ptr],floating)for axis in 'XY']
 seg_advance=[bind('gr_seg_advance_'+axis,[ptr],floating)for axis in 'XY']
 parent=bind('gr_slot_attached_to',[ptr],ptr);child=bind('gr_slot_first_attachment',[ptr],ptr);sibling=bind('gr_slot_next_sibling_attachment',[ptr],ptr)
 attr=bind('gr_slot_attr',[ptr,ptr,C.c_int,C.c_ushort],C.c_int)
 can_insert=bind('gr_slot_can_insert_before',[ptr],C.c_int)
 records=[]
 for case in cases:
  path=HERE/case['font'];font_sha=sha(path.read_bytes());face=face_new(str(path).encode(),0);result={'face_accepted':bool(face),'segment':False,'slots':[]}
  if face:
   try:
    chars=(uint*len(case['text']))(*map(ord,case['text']));seg=seg_new(None,face,0,None,4,chars,len(case['text']),3 if case['direction']=='rtl'else 2)
    result['segment']=bool(seg)
    if seg:
     try:
      result['advance_bits']=[bits(query(seg))for query in seg_advance];slot=first(seg);seen=set()
      while slot:
       assert slot not in seen and len(seen)<65536,'unexpected public slot-list cycle'
       seen.add(slot);links=[query(slot)for query in [parent,child,sibling]]
       result['slots'].append({'glyph':glyph(slot),'before':before(slot),'after':after(slot),'position_bits':[bits(query(slot))for query in origin],'advance_bits':[bits(query(slot,face,None))for query in advance],'links_glyph':[glyph(link)if link else None for link in links],'attachment_level':attr(slot,seg,13,0)})
       if case['id'].startswith('collision-'):result['slots'][-1]['collision_attributes']=[attr(slot,seg,a,0)for a in range(57,78)]
       if args.slot_insertion:result['slots'][-1]['can_insert_before']=bool(can_insert(slot))
       slot=next_(slot)
     finally:seg_drop(seg)
    else:result['abort']='ProgramAbort'
   finally:face_drop(face)
  records.append({'id':case['id'],'font_sha256':font_sha,'key':sha(canonical({'case':case,'font':font_sha,'oracle':oracle})),'result':result})
 output.write_text(json.dumps({'oracle':oracle,'records':records},indent=2)+'\n')
 print(f'{len(records)} Graphite geometry records cached; {sum(not r["result"]["face_accepted"]for r in records)} rejected faces; {sum(r["result"].get("abort")=="ProgramAbort"for r in records)} program aborts')

if __name__=='__main__':main()
