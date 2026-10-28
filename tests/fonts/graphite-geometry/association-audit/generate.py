"""Original UPL F32 association witnesses; no engine implementation sources."""
import argparse
import importlib.util
import io
import json
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("original_kerning_builder",HERE.parent/"kerning-audit/generate.py")
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)

CASES = [
    ("left-sum",-100,300,200,10,False),
    ("left-sum",-10,100,127,13,False),
    ("left-sum",-10,100,128,13,False),
    ("right-sum",-1000,3,42,101,False),
    ("right-sum",-1000,200,1,101,False),
    ("right-sum",-1000,300,1,101,False),
    ("right-diff",-100,200,42,10,False),
    ("right-diff",-100,200,200,10,False),
    ("right-diff",-100,100,200,10,True),
]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check",action="store_true")
    args = parser.parse_args()
    cases = []
    for branch,xmin,width,byte,margin,unresolved in CASES:
        name = f"collision-association-{branch}-{xmin}-{width}-{byte}-{margin}"
        diagonal = [byte,255,0,255]if branch=="left-sum"else[0,byte,0,255]if branch=="right-sum"else[0,255,0,byte]
        rtl = branch=="left-sum"
        params = {"pass_flags":9,"flags_a":17,"flags_b":0,"margin":margin,"distance":0,"diagonals":{1:diagonal}}
        data,programs = base.make(name,params,rtl)
        font = TTFont(io.BytesIO(data),recalcTimestamp=False)
        for gid,box in {1:[xmin,0,xmin+width,1],2:[0,0,3,1]}.items():
            pen = TTGlyphPen(None)
            x0,y0,x1,y1 = box
            pen.moveTo((x0,y0));pen.lineTo((x1,y0));pen.lineTo((x1,y1));pen.lineTo((x0,y1));pen.closePath()
            font["glyf"][font.getGlyphName(gid)] = pen.glyph()
        out = io.BytesIO()
        font.save(out,reorderTables=True)
        path = HERE/(name+".ttf")
        if args.check:
            assert path.read_bytes()==out.getvalue(),path
        else:
            path.write_bytes(out.getvalue())
        cases.append({"id":name,"font":"association-audit/"+path.name,"text":"ab","direction":"rtl"if rtl else"ltr",
                      "positioning":True,"precontext":0,"action":list(programs[0]),"collision":params,
                      "association":{"branch":branch,"target_bbox":[xmin,0,xmin+width,1],"neighbor_bbox":[0,0,3,1],
                                     "analytic_association":"unresolved"if unresolved else"facet_then_margin"}})
    output = json.dumps({"schema":1,"about":"Eight distinguishing F32 association observations plus one explicitly unresolved analytical witness; every cached output is normative.","cases":cases},indent=2)+"\n"
    path = HERE/"cases.jsonc"
    if args.check:
        assert path.read_text()==output,path
    else:
        path.write_text(output)
    print(len(cases),"original association cases", "reproduced"if args.check else"generated")
if __name__=="__main__":
    main()
