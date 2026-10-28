"""Record twelve public Graphite2 collision/feature controls, without implementation access."""
from pathlib import Path
import argparse,ctypes as C,hashlib,json
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();sha=lambda data:hashlib.sha256(data).hexdigest();recipes=[('absent',None),('false',None),('true',None),('feature',None),('feature',0),('feature',1)]
recipes += [('zero-'+name,value)for name,value in recipes]
if args.check:
 rows=json.loads((HERE/'raw-records.json').read_text())['records'];assert len(rows)==12
 for (name,value),row in zip(recipes,rows):assert row['font']==name+'.ttf'and row['choice']==value and row['font_sha256']==sha((HERE/(name+'.ttf')).read_bytes())
 print('12 raw public C API controls and unchanged fonts current');raise SystemExit(0)
path=Path('/opt/homebrew/lib/libgraphite2.dylib');l=C.CDLL(str(path));ptr=C.c_void_p

def bind(n,a,r):f=getattr(l,n);f.argtypes=a;f.restype=r;return f
version=bind('gr_engine_version',[C.POINTER(C.c_int)]*3,None);a=C.c_int();b=C.c_int();c=C.c_int();version(C.byref(a),C.byref(b),C.byref(c));assert(a.value,b.value,c.value)==(1,3,14)
face=bind('gr_make_file_face',[C.c_char_p,C.c_uint],ptr);dropface=bind('gr_face_destroy',[ptr],None);vals=bind('gr_face_featureval_for_lang',[ptr,C.c_uint],ptr);dropvals=bind('gr_featureval_destroy',[ptr],None);find=bind('gr_face_find_fref',[ptr,C.c_uint],ptr);setvalue=bind('gr_fref_set_feature_value',[ptr,C.c_ushort,ptr],C.c_int);seg=bind('gr_make_seg',[ptr,ptr,C.c_uint,ptr,C.c_int,ptr,C.c_size_t,C.c_int],ptr);dropseg=bind('gr_seg_destroy',[ptr],None);first=bind('gr_seg_first_slot',[ptr],ptr);next_=bind('gr_slot_next_in_segment',[ptr],ptr);gid=bind('gr_slot_gid',[ptr],C.c_ushort);x=bind('gr_slot_origin_X',[ptr],C.c_float);total=bind('gr_seg_advance_X',[ptr],C.c_float)
rows=[]
for name,value in recipes:
 file=HERE/(name+'.ttf');fc=face(str(file).encode(),6);assert fc;features=vals(fc,0);assert features
 if value is not None:
  ref=find(fc,100);assert ref and setvalue(ref,value,features),('declared feature value rejected',value)
 chars=(C.c_uint*2)(97,98);s=seg(None,fc,0,features,4,chars,2,2);assert s;slots=[];slot=first(s)
 while slot:slots.append({'glyph':gid(slot),'x':x(slot)});slot=next_(slot)
 rows.append({'font':file.name,'font_sha256':sha(file.read_bytes()),'choice':value,'explicit_choice_accepted':None if value is None else True,'segment_advance':total(s),'slots':slots});dropseg(s);dropvals(features);dropface(fc)
(HERE/'raw-records.json').write_text(json.dumps({'engine':'Graphite2 1.3.14','library_sha256':sha(path.read_bytes()),'face_mode':6,'segment_flags':2,'records':rows},indent=2)+'\n');print('12 raw public C API collision/feature controls recorded')
