"""Record MATH font facts from pinned HarfBuzz and independently check fontTools.

    tools/oracle/.venv/bin/python tests/fonts/math/oracle.py

Writes oracle.jsonl, never Roc source. verify.py replays these records through
an optimized native public-API driver without either oracle installed.
"""
from pathlib import Path
import json, hashlib, math, re, io
import uharfbuzz as hb
import fontTools
from fontTools.ttLib import TTFont
from fontTools.varLib.varStore import VarStoreInstancer
from fontTools.varLib.models import normalizeLocation

HERE = Path(__file__).resolve().parent
assert hb.__version__ == '0.56.3' and hb.version_string() == '14.6.0'
assert fontTools.__version__ == '4.61.1'


def cases():
    return json.loads((HERE/'cases.jsonc').read_text())['cases']


def at(obj, name):
    return getattr(obj, name, None) if obj is not None else None


def covered(obj, coverage_name, glyph):
    cov=at(obj,coverage_name)
    if cov is None or glyph not in cov.glyphs:
        return None
    return cov.glyphs.index(glyph)


def facts(case):
    path=HERE/case['font']; data=path.read_bytes(); ft=TTFont(path)
    face=hb.Face(data); font=hb.Font(face); font.scale=(face.upem,face.upem)
    font.set_variations({'wght':case['weight']})
    table=ft['MATH'].table
    info=table.MathGlyphInfo; variants=table.MathVariants
    order=ft.getGlyphOrder(); ids=ft.getReverseGlyphMap()
    if 'fvar' in ft:
        axes=ft['fvar'].axes
        norm=normalizeLocation({'wght':case['weight']},{a.axisTag:(a.minValue,a.defaultValue,a.maxValue) for a in axes})
        instancer=VarStoreInstancer(ft['GDEF'].table.VarStore, axes, norm)
    else:
        norm={};instancer=None

    def value(r):
        if r is None:return 0
        result=r.Value;d=r.DeviceTable
        if d is not None and d.DeltaFormat==0x8000 and any(norm.values()):
            result+=math.floor(instancer[(d.StartSize<<16)|d.EndSize]+0.5)
        return result

    # HarfBuzz 14.6 does not pass a GDEF store to MATH device evaluation.
    # For varied cases independently evaluate each value with fontTools,
    # materialize the resulting MATH table, and use HarfBuzz to cross-check
    # every static query. This is explicitly different oracle provenance.
    varied = instancer is not None and any(norm.values())
    if varied:
        def materialize(obj):
            if isinstance(obj, list):
                for child in obj: materialize(child)
            elif hasattr(obj, 'Value') and hasattr(obj, 'DeviceTable'):
                obj.Value=value(obj); obj.DeviceTable=None
            elif hasattr(obj, 'getConverters'):
                for converter in obj.getConverters():
                    materialize(getattr(obj, converter.name, None))
        materialize(table)
        stream=io.BytesIO();ft.save(stream)
        materialized=hb.Face(stream.getvalue());font=hb.Font(materialized)
        font.scale=(face.upem,face.upem)
    out=[]
    constants=[]
    # fontTools field order is the specified MATH constant enum order.
    converters=table.MathConstants.getConverters()
    assert len(converters)==56
    for enum, converter in zip(hb.OTMathConstant,converters):
        r=getattr(table.MathConstants,converter.name)
        expected=value(r) if hasattr(r,'Value') else r
        actual=font.get_math_constant(enum)
        assert actual==expected,(case['id'],converter.name,actual,expected)
        constants.append(actual)
    out.append('constants|'+','.join(map(str,constants)))
    assert font.get_math_min_connector_overlap('ttb')==variants.MinConnectorOverlap
    out.append(f'overlap|{variants.MinConnectorOverlap}')
    for g,name in enumerate(order):
        ic=at(info,'MathItalicsCorrectionInfo'); i=covered(ic,'Coverage',name)
        italic=None if i is None else value(ic.ItalicsCorrection[i])
        assert font.get_math_glyph_italics_correction(g)==(italic or 0)
        ac=at(info,'MathTopAccentAttachment'); i=covered(ac,'TopAccentCoverage',name)
        accent=None if i is None else value(ac.TopAccentAttachment[i])
        assert font.get_math_glyph_top_accent_attachment(g)==(accent if accent is not None else font.get_glyph_h_advance(g)//2)
        ext=name in (at(at(info,'ExtendedShapeCoverage'),'glyphs') or [])
        assert face.is_glyph_extended_math_shape(g)==ext
        out.append(f'glyph|{g}|'+('_' if italic is None else str(italic))+'|'+('_' if accent is None else str(accent))+f'|{int(ext)}')
        ki=at(info,'MathKernInfo'); i=covered(ki,'MathKernCoverage',name)
        for corner in hb.OTMathKern:
            field=['TopRightMathKern','TopLeftMathKern','BottomRightMathKern','BottomLeftMathKern'][corner.value]
            raw=None if i is None else getattr(ki.MathKernInfoRecords[i],field)
            entries=font.get_math_glyph_kernings(g,corner)
            if raw is None:
                assert not entries
                assert font.get_math_glyph_kerning(g,corner,0)==0
                continue
            heights=[value(r) for r in raw.CorrectionHeight]; values=[value(r) for r in raw.KernValue]
            assert [(e.max_correction_height,e.kern_value) for e in entries]==list(zip(heights+[2147483647],values))
            out.append(f'kern-table|{g}|{corner.value}|'+','.join(map(str,heights))+'|'+','.join(map(str,values)))
            for h in sorted(set([-2147483648,0,2147483647]+[x+d for x in heights for d in [-1,0,1]])):
                index=sum(h>=x for x in heights)
                actual=font.get_math_glyph_kerning(g,corner,h)
                assert actual==values[index],(case['id'],g,corner,h,actual,values)
                out.append(f'kern|{g}|{corner.value}|{h}|{actual}')
        for axis,direction in enumerate(['ttb','ltr']):
            prefix='Vert' if axis==0 else 'Horiz'
            cv=getattr(variants,prefix+'GlyphCoverage');i=None if cv is None or name not in cv.glyphs else cv.glyphs.index(name)
            raw=None if i is None else getattr(variants,prefix+'GlyphConstruction')[i]
            expected=[] if raw is None else [(ids[r.VariantGlyph],r.AdvanceMeasurement) for r in raw.MathGlyphVariantRecord]
            actual=[(r.glyph,r.advance) for r in font.get_math_glyph_variants(g,direction)]
            assert actual==expected
            if actual:out.append(f'variants|{g}|{axis}|'+','.join(f'{a}:{b}' for a,b in actual))
            assembly=at(raw,'GlyphAssembly');parts,italic=font.get_math_glyph_assembly(g,direction)
            expected=[] if assembly is None else [(ids[p.glyph],p.StartConnectorLength,p.EndConnectorLength,p.FullAdvance,p.PartFlags) for p in assembly.PartRecords]
            actual=[(p.glyph,p.start_connector_length,p.end_connector_length,p.full_advance,int(p.flags)) for p in parts]
            assert actual==expected
            assert italic==(0 if assembly is None else value(assembly.ItalicsCorrection))
            if assembly is not None:out.append(f'assembly|{g}|{axis}|{italic}|'+','.join(':'.join(map(str,p)) for p in actual))
    return {'id':case['id'],'font_sha256':hashlib.sha256(data).hexdigest(),'harfbuzz':hb.version_string(),'fonttools':fontTools.__version__,'oracle':'fonttools-varstore-and-harfbuzz-materialized' if varied else 'harfbuzz-and-fonttools','divergence':'HarfBuzz 14.6 ignores raw MATH VariationIndex devices; variable values are independently materialized using fontTools before HarfBuzz queries.' if varied else None,'facts':out}


if __name__=='__main__':
    with (HERE/'oracle.jsonl').open('w') as out:
        for case in cases():
            record=facts(case);out.write(json.dumps(record,separators=(',',':'))+'\n')
            print(case['id'],len(record['facts']),'facts')
