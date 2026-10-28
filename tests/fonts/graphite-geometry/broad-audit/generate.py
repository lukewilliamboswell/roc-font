"""Original UPL broad-guard inputs; deliberately does not invent a predicate."""
import argparse
import importlib.util
import io
import json
from pathlib import Path
import struct
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("original_kerning_builder",HERE.parent/"kerning-audit/generate.py")
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
geometry = base.geometry


def make(name,recipe):
    params = recipe["params"]
    prior = "second_distance"in params
    first = dict(params,distance=100,flags_a=0,flags_b=1,pass_flags=1)if prior else params
    data,action = base.collision.make(name,first,False)
    font = TTFont(io.BytesIO(data),recalcTimestamp=False)
    programs = [action]
    if prior:
        old = font.getTableData("Silf")
        second_action = geometry.set_attr(0,params["second_distance"])+geometry.NEXT
        for attr,value in zip([58,59,60,61],params["second_bounds"]):
            second_action += geometry.set_attr(attr,value)
        second = bytearray(geometry.program(second_action+bytes([0x32]),True,(1,2)))
        for a,b in [(24,26),(35,36),(48,50)]:
            second[a:b] = old[a:b]
        second[84] = 1
        base.raw(font,"Silf",base.two_pass(old,bytes(second)))
        programs = [action,second_action]
    if params.get("glyph_limits"):
        glat = bytearray(font.getTableData("Glat"))
        gloc = font.getTableData("Gloc")
        for glyph,limits in params["glyph_limits"].items():
            at = struct.unpack_from(">H",gloc,8+int(glyph)*2)[0]
            struct.pack_into(">4h",glat,at+6+4+2,*limits)
        base.raw(font,"Glat",glat)
    for glyph,box in recipe["boxes"].items():
        pen = TTGlyphPen(None)
        x0,y0,x1,y1 = box
        pen.moveTo((x0,y0));pen.lineTo((x1,y0));pen.lineTo((x1,y1));pen.lineTo((x0,y1));pen.closePath()
        font["glyf"][font.getGlyphName(int(glyph))] = pen.glyph()
    out = io.BytesIO()
    font.save(out,reorderTables=True)
    return out.getvalue(),programs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check",action="store_true")
    args = parser.parse_args()
    recipes = json.loads((HERE/"recipes.json").read_text())["recipes"]
    cases = []
    for index,recipe in enumerate(recipes):
        name = f"collision-broad-audit-{index:03d}-"+recipe["source_name"].removeprefix("witness-")
        data,programs = make(name,recipe)
        path = HERE/(name+".ttf")
        if args.check:
            assert path.read_bytes()==data,path
        else:
            path.write_bytes(data)
        cases.append({"id":name,"font":"broad-audit/"+path.name,"text":"ab","direction":"ltr","positioning":True,
                      "precontext":0,"action":list(programs[0]),"programs":[list(p)for p in programs],
                      "collision":recipe["params"],"broad_observation":{"recipe":index,"mode":recipe["source_expected_mode"],
                      "status":"reference-observation; no general predicate claimed"}})
    output = json.dumps({"schema":1,"about":"76 retained original broad-guard witnesses plus8 displayed-rectangle controls; exact outcomes without a general guard claim.","cases":cases},indent=2)+"\n"
    path = HERE/"cases.jsonc"
    if args.check:
        assert path.read_text()==output,path
    else:
        path.write_text(output)
    print(len(cases),"original broad cases", "reproduced"if args.check else"generated")
if __name__=="__main__":
    main()
