"""Record MATH font facts from pinned HarfBuzz and independently check fontTools.

    tools/oracle/.venv/bin/python tests/fonts/math/oracle.py

Default records are selected checkpoints. --full writes exhaustive local
records under ignored .roc-font-tmp/math, never Roc source. verify.py replays
either mode without an oracle installed.
"""
from pathlib import Path
import argparse, json, hashlib, math, re, io, struct
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


def facts(case, full=False):
    wide=case.get('wide',False)
    path=HERE/case['font']; data=path.read_bytes(); ft=TTFont(path)
    face=hb.Face(data); font=hb.Font(face); font.scale=(face.upem,face.upem)
    font.set_variations(case.get('axes',{'wght':case['weight']}))
    table=ft['MATH'].table
    info=table.MathGlyphInfo; variants=table.MathVariants
    order=ft.getGlyphOrder(); ids=ft.getReverseGlyphMap()
    if 'fvar' in ft:
        axes=ft['fvar'].axes
        norm=normalizeLocation(case.get('axes',{'wght':case['weight']}),{a.axisTag:(a.minValue,a.defaultValue,a.maxValue) for a in axes})
        instancer=VarStoreInstancer(ft['GDEF'].table.VarStore, axes, norm)
    else:
        norm={};instancer=None

    def value(r):
        if r is None:return 0
        result=r.Value;d=r.DeviceTable
        if d is not None and d.DeltaFormat==0x8000 and instancer is not None:
            delta=instancer[(d.StartSize<<16)|d.EndSize]
            if wide:
                # The wide fixture uses32identicalexactbinaryweights; its
                # sum is independently computed byfontTools then rounded
                # tobinary32, as the shaper's variation arithmetic does.
                delta=struct.unpack('>f',struct.pack('>f',delta))[0]
                delta=struct.unpack('>f',struct.pack('>f',delta+0.5))[0]
                result+=math.floor(delta)
            else:
                result+=math.floor(delta+0.5)
        return result

    # HarfBuzz 14.6 does not pass a GDEF store to MATH device evaluation.
    # For varied cases independently evaluate each value with fontTools,
    # materialize the resulting MATH table, and use HarfBuzz to cross-check
    # every static query. This is explicitly different oracle provenance.
    varied = instancer is not None
    if varied and not wide:
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
        actual=expected if wide else font.get_math_constant(enum)
        assert actual==expected,(case['id'],converter.name,actual,expected)
        constants.append(actual)
    out.append('constants|'+','.join(map(str,constants)))
    assert font.get_math_min_connector_overlap('ttb')==variants.MinConnectorOverlap
    out.append(f'overlap|{variants.MinConnectorOverlap}')
    glyphs=list(range(len(order))) if full else case['glyphs']
    assert len(set(glyphs))==len(glyphs) and all(0<=g<len(order) for g in glyphs)
    for g in glyphs:
        name=order[g]
        ic=at(info,'MathItalicsCorrectionInfo'); i=covered(ic,'Coverage',name)
        italic=None if i is None else value(ic.ItalicsCorrection[i])
        if not wide:assert font.get_math_glyph_italics_correction(g)==(italic or 0)
        ac=at(info,'MathTopAccentAttachment'); i=covered(ac,'TopAccentCoverage',name)
        accent=None if i is None else value(ac.TopAccentAttachment[i])
        if not wide:assert font.get_math_glyph_top_accent_attachment(g)==(accent if accent is not None else font.get_glyph_h_advance(g)//2)
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
            if not wide:assert [(e.max_correction_height,e.kern_value) for e in entries]==list(zip(heights+[2147483647],values))
            out.append(f'kern-table|{g}|{corner.value}|'+','.join(map(str,heights))+'|'+','.join(map(str,values)))
            for h in sorted(set([-2147483648,0,2147483647]+[x+d for x in heights for d in [-1,0,1]])):
                index=sum(h>=x for x in heights)
                actual=font.get_math_glyph_kerning(g,corner,h)
                if wide:
                    # RawHB14.6selects therange; fontTools supplies its
                    # correctedwidevalue. Heights inthisfixture donotvary.
                    raw_values=[r.Value for r in raw.KernValue]
                    actual=values[raw_values.index(actual)]
                # Duplicate threshold equality follows HarfBuzz's first
                # visited binary-search match; do not impose upper_bound.
                matches=[values[j+1] for j,x in enumerate(heights) if x==h]
                assert actual in (matches or [values[index]]),(case['id'],g,corner,h,actual,values)
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
            expected_italic=0 if assembly is None else value(assembly.ItalicsCorrection)
            if not wide:assert italic==expected_italic
            italic=expected_italic
            if assembly is not None:out.append(f'assembly|{g}|{axis}|{italic}|'+','.join(':'.join(map(str,p)) for p in actual))
    return {'id':case['id'],'case_sha256':hashlib.sha256(json.dumps(case,sort_keys=True,separators=(',',':')).encode()).hexdigest(),'selection':'all-glyphs' if full else 'checkpoints','glyphs':glyphs,'font_sha256':hashlib.sha256(data).hexdigest(),'harfbuzz':hb.version_string(),'fonttools':fontTools.__version__,'oracle':'fonttools-varstore-f32-wide' if wide else 'fonttools-varstore-and-harfbuzz-materialized' if varied else 'harfbuzz-and-fonttools','divergence':'Valid variable math distances may exceedI32; HarfBuzz14.6 ignoresMATHvariation devices. fontTools independently evaluates32identicalbinaryweightedlongwordcolumns and the result is roundedtobinary32; font facts retainI64values.' if wide else 'HarfBuzz 14.6 ignores raw MATH VariationIndex devices; variable values are independently materialized using fontTools before HarfBuzz queries.' if varied else None,'facts':out}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--full',action='store_true',help='record every glyph into ignored .roc-font-tmp/math/oracle-full.jsonl')
    args=parser.parse_args()
    output=HERE.parents[2]/'.roc-font-tmp/math/oracle-full.jsonl' if args.full else HERE/'oracle.jsonl'
    output.parent.mkdir(parents=True,exist_ok=True)
    with output.open('w') as out:
        for case in cases():
            record=facts(case,full=args.full);out.write(json.dumps(record,separators=(',',':'))+'\n')
            print(case['id'],len(record['facts']),'facts')
    print(output)
