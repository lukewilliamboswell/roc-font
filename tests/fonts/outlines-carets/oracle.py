"""Record/query pinned HB paths and carets independently of Roc.
No Roc files are generated. JSON is diagnostic/cached oracle data.
"""
from pathlib import Path
import ctypes as C
import json
import uharfbuzz as hb
import uharfbuzz._harfbuzz as implementation
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import RecordingPen
from fontTools.varLib.instancer import instantiateVariableFont
import io

HERE = Path(__file__).resolve().parent
lib = C.CDLL(implementation.__file__)

def declare(name, args, result):
    f = getattr(lib, name)
    f.argtypes, f.restype = args, result
    return f

ptr, uint = C.c_void_p, C.c_uint
blob_create = declare('hb_blob_create',[C.c_char_p,uint,C.c_int,ptr,ptr],ptr)
face_create = declare('hb_face_create',[ptr,uint],ptr)
font_create = declare('hb_font_create',[ptr],ptr)
set_funcs = declare('hb_ot_font_set_funcs',[ptr],None)
set_scale = declare('hb_font_set_scale',[ptr,C.c_int,C.c_int],None)
set_variations = declare('hb_font_set_variations',[ptr,ptr,uint],None)
get_carets = declare('hb_ot_layout_get_ligature_carets',[ptr,C.c_int,uint,uint,C.POINTER(uint),C.POINTER(C.c_int)],uint)
blob_destroy = declare('hb_blob_destroy',[ptr],None)
face_destroy = declare('hb_face_destroy',[ptr],None)
font_destroy = declare('hb_font_destroy',[ptr],None)

class Variation(C.Structure):
    _fields_ = [('tag',uint),('value',C.c_float)]

def carets(data, glyph, axes):
    blob = blob_create(data,len(data),0,None,None)
    face = face_create(blob,0)
    font = font_create(face)
    set_funcs(font)
    upem = hb.Face(data).upem
    set_scale(font,upem,upem)
    variations=(Variation*len(axes))(*(Variation(int.from_bytes(k.encode(),'big'),v) for k,v in axes.items()))
    set_variations(font,variations,len(axes))
    positions=(C.c_int*64)()
    count=uint(64)
    total=get_carets(font,4,glyph,0,C.byref(count),positions)
    assert total <= 64
    values=list(positions)[:count.value]
    font_destroy(font); face_destroy(face); blob_destroy(blob)
    return values

def path(font,glyph):
    pen=RecordingPen()
    font.draw_glyph_with_pen(glyph,pen)
    return [[op,[list(p) for p in points]] for op,points in pen.value]

def records():
    for relative, places in [
      ('outlines-carets.ttf',[{}, {'wght':650}, {'wght':900}]),
      ('../variable/var-outlines.ttf',[{}, {'wght':900}, {'wght':650,'wdth':87.5}]),
    ]:
        file=HERE/relative; data=file.read_bytes(); face=hb.Face(data)
        for axes in places:
            font=hb.Font(face);font.set_variations(axes)
            tt=TTFont(io.BytesIO(data),recalcTimestamp=False)
            if 'fvar' in tt:
                location={axis.axisTag:axes.get(axis.axisTag,axis.defaultValue) for axis in tt['fvar'].axes}
                tt=instantiateVariableFont(tt,location,inplace=False)
            for glyph in range(face.glyph_count):
                name=tt.getGlyphOrder()[glyph]
                coordinates,ends,flags=tt['glyf'][name].getCoordinates(tt['glyf'])
                shift=(tt['glyf'][name].xMin-tt['hmtx'].metrics[name][1]) if coordinates else 0
                point_records=[[float(x-shift),float(y)] for x,y in coordinates]
                yield {'font':relative,'axes':axes,'glyph':glyph,'path':path(font,glyph),'carets':carets(data,glyph,axes),'fonttools_points':point_records,'contour_ends':list(ends),'on_curve':[bool(flag&1) for flag in flags]}

if __name__ == '__main__':
    assert hb.version_string()=='14.6.0',hb.version_string()
    print(json.dumps({'harfbuzz':hb.version_string(),'records':list(records())},indent=2))
