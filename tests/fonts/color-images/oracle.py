"""Pinned independent fontTools container/metrics and HB blob/shape oracles.
Only --record needs oracle packages. Cached answers replay with stdlib.
No Roc source is generated; requests come from cases.jsonc data.
"""
from pathlib import Path
import ctypes as C,gzip,json,struct,hashlib
import fontTools
from fontTools.ttLib import TTFont
import uharfbuzz as hb
import uharfbuzz._harfbuzz as impl
HERE=Path(__file__).resolve().parent
lib=C.CDLL(impl.__file__)
ptr=C.c_void_p;uint=C.c_uint

def declare(name,args,result):
    fn=getattr(lib,name);fn.argtypes=args;fn.restype=result;return fn
blob_create=declare('hb_blob_create',[C.c_char_p,uint,C.c_int,ptr,ptr],ptr)
face_create=declare('hb_face_create',[ptr,uint],ptr)
font_create=declare('hb_font_create',[ptr],ptr)
set_funcs=declare('hb_ot_font_set_funcs',[ptr],None)
set_scale=declare('hb_font_set_scale',[ptr,C.c_int,C.c_int],None)
set_ppem=declare('hb_font_set_ppem',[ptr,uint,uint],None)
ref_svg=declare('hb_ot_color_glyph_reference_svg',[ptr,uint],ptr)
ref_png=declare('hb_ot_color_glyph_reference_png',[ptr,uint],ptr)
blob_data=declare('hb_blob_get_data',[ptr,C.POINTER(uint)],ptr)
blob_destroy=declare('hb_blob_destroy',[ptr],None)
face_destroy=declare('hb_face_destroy',[ptr],None)
font_destroy=declare('hb_font_destroy',[ptr],None)

def read_blob(blob):
    count=uint();at=blob_data(blob,C.byref(count));result=C.string_at(at,count.value);blob_destroy(blob);return result

class HbAssets:
    def __init__(self,data):
        self.blob=blob_create(data,len(data),0,None,None);self.face=face_create(self.blob,0);self.font=font_create(self.face);set_funcs(self.font)
        upem=hb.Face(data).upem;set_scale(self.font,upem,upem)
    def svg(self,glyph):return read_blob(ref_svg(self.face,glyph))
    def png(self,glyph,ppem):
        set_ppem(self.font,ppem,ppem);return read_blob(ref_png(self.font,glyph))
    def close(self):font_destroy(self.font);face_destroy(self.face);blob_destroy(self.blob)

LINE_FIELDS=['ascender','descender','widthMax','caretSlopeNumerator','caretSlopeDenominator','caretOffset','minOriginSB','minAdvanceSB','maxBeforeBL','minAfterBL']
def line(metrics):return ','.join(str(getattr(metrics,key)) for key in LINE_FIELDS)
def axis(x,y,advance):return f'{x},{y},{advance}'

def inspect(path):
    font=TTFont(path,recalcTimestamp=False);data=path.read_bytes();hb_assets=HbAssets(data)
    names=font.getGlyphOrder();gid_for={n:i for i,n in enumerate(names)}
    sbix=[]
    if 'sbix' in font:
        raw_sbix=font.reader['sbix'];count=struct.unpack_from('>I',raw_sbix,4)[0]
        for i in range(count):
            offset=struct.unpack_from('>I',raw_sbix,8+4*i)[0]
            ppem=struct.unpack_from('>H',raw_sbix,offset)[0]
            sbix.append(font['sbix'].strikes[ppem])
    cblc=font['CBLC'].strikes if 'CBLC' in font else []
    strikes=[]
    for s in sbix:strikes.append(f's,{s.ppem},{s.resolution},{int(bool(font["sbix"].flags&2))}')
    for s in cblc:
        m=s.bitmapSizeTable
        strikes.append(f'b,{m.ppemX},{m.ppemY},{m.bitDepth},{m.flags},{m.startGlyphIndex},{m.endGlyphIndex},{line(m.hori)},{line(m.vert)}')
    result={'count':str(len(strikes))}
    result.update({f'strike{i}':value for i,value in enumerate(strikes)})
    svg_docs={}
    if 'SVG ' in font:
        # Independent fontTools parsing verifies document ranges and decoded
        # XML; HB returns the original encoded glyph-document blob.
        raw=font.reader['SVG '];base=struct.unpack_from('>I',raw,2)[0]
        for index,doc in enumerate(font['SVG '].docList):
            start,end,offset,length=struct.unpack_from('>HHII',raw,base+2+index*12)
            encoded=raw[base+offset:base+offset+length]
            assert (start,end)==(doc.startGlyphID,doc.endGlyphID)
            assert (gzip.decompress(encoded) if doc.compressed else encoded).decode()==doc.data
            for glyph in range(start,end+1):
                assert hb_assets.svg(glyph)==encoded
                svg_docs[glyph]=f'{start},{end},{"g" if doc.compressed else "u"},{encoded.hex()}'
    for gid in range(len(names)+1):
        result[f'svg{gid}']=svg_docs.get(gid,'_')
        for index in range(len(strikes)+1):
            value='_'
            if gid<len(names) and index<len(sbix):
                s=sbix[index];name=names[gid];seen=set()
                while s.glyphs[name].graphicType=='dupe':
                    assert name not in seen;seen.add(name);name=s.glyphs[name].referenceGlyphName
                image=s.glyphs[name]
                if image.graphicType:
                    tag=int.from_bytes(image.graphicType.encode('latin1'),'big')
                    value=f'{tag};s,{image.originOffsetX},{image.originOffsetY},{gid_for[name]};{image.imageData.hex()}'
            elif gid<len(names) and index<len(strikes):
                j=index-len(sbix);s=cblc[j];name=names[gid];image=font['CBDT'].strikeData[j].get(name)
                if image is not None:
                    payload=image.imageData
                    if image.getFormat()==19:
                        metric=next(t.metrics for t in s.indexSubTables if name in t.names)
                    else:metric=image.metrics
                    if image.getFormat()==17:
                        a=axis(metric.BearingX,metric.BearingY,metric.Advance)
                        h=a if s.bitmapSizeTable.flags==1 else '_'
                        v=axis(metric.BearingY,metric.BearingX,metric.Advance) if s.bitmapSizeTable.flags==2 else '_'
                    else:
                        h=axis(metric.horiBearingX,metric.horiBearingY,metric.horiAdvance)
                        v=axis(metric.vertBearingX,metric.vertBearingY,metric.vertAdvance)
                    value=f'1886283552;b,{metric.width},{metric.height};{h};{v};{payload.hex()}'
                    # On a real CBDT-only font the exact-strike HB blob is
                    # an independent byte-for-byte check of each payload.
                    if not sbix:assert hb_assets.png(gid,s.bitmapSizeTable.ppemX)==payload
            result[f'image{gid}:{index}']=value
    hb_assets.close()
    return result

def shape(path,text):
    font=hb.Font(hb.Face(path.read_bytes()));buf=hb.Buffer();buf.add_utf8(text.encode());buf.direction='ltr';buf.script='Latn';hb.shape(font,buf)
    return {'shape':';'.join(f'{g.codepoint},{g.cluster},{p.x_advance},{p.y_advance},{p.x_offset},{p.y_offset}' for g,p in zip(buf.glyph_infos,buf.glyph_positions))}

def record():
    assert fontTools.__version__=='4.61.1',fontTools.__version__
    assert hb.version_string()=='14.6.0',hb.version_string()
    cases=json.loads((HERE/'cases.jsonc').read_text())['cases']
    records=[]
    for case in cases:
        path=HERE/case['font']
        expected=shape(path,case['text']) if case['kind']=='shape' else inspect(path)
        records.append({'id':case['id'],'font_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'expected':expected})
    return {'fontTools':fontTools.__version__,'harfbuzz':hb.version_string(),'records':records}

if __name__=='__main__':
    (HERE/'oracle.json').write_text(json.dumps(record(),ensure_ascii=False,indent=2)+'\n')
