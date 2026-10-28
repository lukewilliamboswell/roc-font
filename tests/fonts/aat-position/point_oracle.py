"""HB14.6 with an explicit FreeType2.13.2 unhinted contour-point callback.
The default HB OT font-functions backend does not provide contour points.
All shaping, glyph mapping, metrics and positioning still execute in HB;
only the requested outline point comes from independent FreeType.
"""
import ctypes as C
import freetype
import math,struct
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import RecordingPointPen
import uharfbuzz._harfbuzz as implementation
lib=C.CDLL(implementation.__file__);ptr=C.c_void_p;uint=C.c_uint

def define(name,args,result):
 f=getattr(lib,name);f.argtypes=args;f.restype=result;return f
blob_create=define('hb_blob_create',[C.c_char_p,uint,C.c_int,ptr,ptr],ptr)
face_create=define('hb_face_create',[ptr,uint],ptr)
font_create=define('hb_font_create',[ptr],ptr)
subfont_create=define('hb_font_create_sub_font',[ptr],ptr)
set_ot=define('hb_ot_font_set_funcs',[ptr],None)
funcs_create=define('hb_font_funcs_create',[],ptr)
set_funcs=define('hb_font_set_funcs',[ptr,ptr,ptr,ptr],None)
set_point=define('hb_font_funcs_set_glyph_contour_point_func',[ptr,ptr,ptr,ptr],None)
buf_create=define('hb_buffer_create',[],ptr)
add_text=define('hb_buffer_add_utf8',[ptr,C.c_char_p,C.c_int,uint,C.c_int],None)
set_dir=define('hb_buffer_set_direction',[ptr,C.c_int],None)
set_script=define('hb_buffer_set_script',[ptr,uint],None)
language=define('hb_language_from_string',[C.c_char_p,C.c_int],ptr)
set_language=define('hb_buffer_set_language',[ptr,ptr],None)
class Feature(C.Structure):_fields_=[('tag',uint),('value',uint),('start',uint),('end',uint)]
class Info(C.Structure):_fields_=[('glyph',uint),('mask',uint),('cluster',uint),('var1',uint),('var2',uint)]
class Position(C.Structure):_fields_=[('xa',C.c_int),('ya',C.c_int),('xo',C.c_int),('yo',C.c_int),('var',uint)]
shape=define('hb_shape',[ptr,ptr,C.POINTER(Feature),uint],None)
infos=define('hb_buffer_get_glyph_infos',[ptr,C.POINTER(uint)],C.POINTER(Info))
positions=define('hb_buffer_get_glyph_positions',[ptr,C.POINTER(uint)],C.POINTER(Position))
callback_type=C.CFUNCTYPE(C.c_int,ptr,ptr,uint,uint,C.POINTER(C.c_int),C.POINTER(C.c_int),ptr)

class Variation(C.Structure):_fields_=[("tag",uint),("value",C.c_float)]
set_variations=define("hb_font_set_variations",[ptr,C.POINTER(Variation),uint],None)

def materialized_points(path,glyph,weight):
 f=TTFont(path);pen=RecordingPointPen();f.getGlyphSet(location={'wght':weight})[f.getGlyphName(glyph)].drawPoints(pen)
 return [entry[1][0]for entry in pen.value if entry[0]=='addPoint']

def f32(value):return struct.unpack('>f',struct.pack('>f',value))[0]
def point_conversion(value):
 rounded=math.floor(f32(f32(value)+.5));return ((rounded+2**31)%2**32)-2**31

def shape_points(path,text,direction,kern,weight=0,source='freetype'):
 data=path.read_bytes();ft=freetype.Face(str(path));blob=blob_create(data,len(data),0,None,None);face=face_create(blob,0);base=font_create(face);set_ot(base)
 variation=Variation(int.from_bytes(b"wght","big"),weight);set_variations(base,C.byref(variation),1)
 try:ft.set_var_design_coords([weight])
 except freetype.FT_Exception:pass
 font=subfont_create(base)
 def point(_font,_data,glyph,index,x,y,_user):
  try:
   if source=='fonttools':values=materialized_points(path,glyph,weight)
   else:
    ft.load_glyph(glyph,freetype.FT_LOAD_NO_SCALE|freetype.FT_LOAD_NO_HINTING|freetype.FT_LOAD_NO_BITMAP)
    values=ft.glyph.outline.points
   if index>=len(values):return 0
   x[0],y[0]=map(point_conversion,values[index])if source=='fonttools'else values[index];return 1
  except freetype.FT_Exception:return 0
 cb=callback_type(point);funcs=funcs_create();set_point(funcs,C.cast(cb,ptr),None,None);set_funcs(font,funcs,None,None)
 b=buf_create();raw=text.encode();add_text(b,raw,len(raw),0,len(raw));set_dir(b,{'ltr':4,'rtl':5,'ttb':6,'btt':7}[direction]);set_script(b,int.from_bytes(b'Latn','big'));set_language(b,language(b'en',-1))
 features=(Feature*2)(Feature(int.from_bytes(b'kern','big'),int(kern),0,0xffffffff),Feature(int.from_bytes(b'vkrn','big'),int(kern),0,0xffffffff));shape(font,b,features,2)
 count=uint();ii=infos(b,C.byref(count));pp=positions(b,C.byref(count));out={'glyphs':[ii[i].glyph for i in range(count.value)],'clusters':[ii[i].cluster for i in range(count.value)],'advances':[[pp[i].xa,pp[i].ya]for i in range(count.value)],'offsets':[[pp[i].xo,pp[i].yo]for i in range(count.value)]}
 for name,obj in [('hb_buffer_destroy',b),('hb_font_destroy',font),('hb_font_funcs_destroy',funcs),('hb_font_destroy',base),('hb_face_destroy',face),('hb_blob_destroy',blob)]:define(name,[ptr],None)(obj)
 return out
