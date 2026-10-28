"""Original UPL sequencing controls, derived from public formats/API observations."""
import argparse
import importlib.util
import io
import json
from pathlib import Path
import struct
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
from fontTools.pens.ttGlyphPen import TTGlyphPen

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("original_kerning_builder",HERE.parent/"kerning-audit/generate.py")
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
geometry = base.geometry
DEFAULT = [1,0,1,100,300,-50,100,150,500]


def specifications():
    for rtl in (False,True):
        yield "canonical", {}, rtl
        yield "following-rightup", {"attachment":"backward","target":1,"order":2}, rtl
        yield "siblings", {"siblings":True}, rtl
        for order in (0,2,3,4,8,5,6,9,10,12,15):
            yield "order-"+str(order), {"order":order}, rtl
        for order in (1,2,4,8):
            yield "reversed-pass-"+str(order), {"order":order,"reverse_pass":True}, rtl
    for a,b,prox in [(0,0,0),(1,0,1),(1,1,0),(1,1,2),(1,2,0),(1,2,1),(2,1,2),(-1,-1,0),(-1,1,-1)]:
        yield f"class-{a}-{b}-{prox}", {"classes":[a,b,prox]}, True
    yield "separate-trees", {"separate":True}, True
    yield "neighbor-margin", {"margin_a":50}, True
    yield "target-margin", {"margin_b":50}, True
    yield "repeat-offset", {"repeat":True,"neighbor_fields":{3:0}}, True
    yield "asymmetric-limits", {"limits":[-250,-100,700,900],"neighbor_fields":{3:0}}, True
    yield "offset-bounds", {"boxes":{1:[30,40,130,240],2:[10,20,310,620]},"neighbor_fields":{3:0}}, True
    yield "fractional-output", {"boxes":{1:[-80,-170,-60,-150],2:[0,0,20,20]},"limits":[-1,-1000,1,1000],"neighbor_fields":{3:0,4:3,5:0,6:1,7:100,8:1}}, True
    for field,values in [(2,[0,2]),(3,[0,1]),(4,[0,1]),(5,[-100,100]),(6,[0,1]),(7,[0,1]),(8,[0,1])]:
        for value in values:
            yield f"neighbor-field-{field}-{value}", {"neighbor_fields":{field:value}}, True
    yield "target-parameters-ignored", {"target_fields":{3:0,4:1,5:100,6:1,7:1,8:1}}, True


def make(name,parameters,rtl):
    target = parameters.get("target",2)
    params = {"pass_flags":1,"flags_a":int(target==1),"flags_b":int(target==2),"attachment":parameters.get("attachment","forward")}
    for key in ("margin_a","margin_b"):
        if key in parameters:
            params[key] = parameters[key]
    if parameters.get("separate"):
        params.pop("attachment")
    if parameters.get("siblings"):
        params["group_flags"] = [0,1,0]
    if parameters.get("reverse_pass"):
        params["pass_flags"] = 0
    if parameters.get("repeat"):
        params["second"] = "repeat"
    data,action = base.collision.make(name,params,rtl)
    font = TTFont(io.BytesIO(data),recalcTimestamp=False)
    programs = [action]
    old = font.getTableData("Silf")
    if parameters.get("siblings"):
        action = geometry.attach(2)+geometry.NEXT+geometry.attach(1)+geometry.set_attr(3,200)+geometry.set_attr(4,100)
        changed = bytearray(geometry.program(action+bytes([0x32]),True,(1,2,3)))
        for start,end in [(24,26),(35,36),(48,50),(84,85)]:
            changed[start:end] = old[start:end]
        base.raw(font,"Silf",changed)
        programs = [action]
    if parameters.get("reverse_pass"):
        second = bytearray(geometry.program(bytes([0x32]),True,(1,2)))
        for start,end in [(24,26),(35,36),(48,50)]:
            second[start:end] = old[start:end]
        second[84] = 33
        base.raw(font,"Silf",base.two_pass(old,bytes(second)))
        programs = [action,b""]
    sequence = {1:DEFAULT.copy(),2:DEFAULT.copy()}
    sequence[target][2] = parameters.get("order",1)
    if parameters.get("classes"):
        a,b,prox = parameters["classes"]
        sequence[1][0],sequence[2][0],sequence[target][1] = a,b,prox
    neighbor = 3-target
    for field,value in parameters.get("neighbor_fields",{}).items():
        sequence[neighbor][field] = value
    for field,value in parameters.get("target_fields",{}).items():
        sequence[target][field] = value
    if parameters.get("siblings"):
        sequence[3] = [0]*9
    glat = bytearray(font.getTableData("Glat"))
    gloc = font.getTableData("Gloc")
    for gid,values in sequence.items():
        at = struct.unpack_from(">H",gloc,8+gid*2)[0]
        struct.pack_into(">9h",glat,at+6+4+7*2,*values)
    if parameters.get("limits"):
        for gid in range(font["maxp"].numGlyphs):
            at = struct.unpack_from(">H",gloc,8+gid*2)[0]
            struct.pack_into(">4h",glat,at+6+4+2,*parameters["limits"])
    base.raw(font,"Glat",glat)
    for gid,box in parameters.get("boxes",{}).items():
        pen = TTGlyphPen(None)
        x0,y0,x1,y1 = box
        pen.moveTo((x0,y0));pen.lineTo((x1,y0));pen.lineTo((x1,y1));pen.lineTo((x0,y1));pen.closePath()
        font["glyf"][font.getGlyphName(gid)] = pen.glyph()
    output = io.BytesIO()
    font.save(output,reorderTables=True)
    return output.getvalue(),programs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check",action="store_true")
    args = parser.parse_args()
    cases = []
    for label,parameters,rtl in specifications():
        name = "collision-sequence-audit-"+label+("-rtl"if rtl else"-ltr")
        data,programs = make(name,parameters,rtl)
        path = HERE/(name+".ttf")
        if args.check:
            assert path.read_bytes() == data,path
        else:
            path.write_bytes(data)
        cases.append({"id":name,"font":"sequencing-audit/"+path.name,"text":"abc"if parameters.get("siblings")else"ab",
                      "direction":"rtl"if rtl else"ltr","positioning":True,"precontext":0,
                      "action":list(programs[0]),"programs":[list(p)for p in programs],"collision":parameters})
    output = json.dumps({"schema":1,"about":"Original UPL sequencing constraints from normative GDL and public Graphite2 API/logs.","cases":cases},indent=2)+"\n"
    path = HERE/"cases.jsonc"
    if args.check:
        assert path.read_text() == output,path
    else:
        path.write_text(output)
    print(len(cases),"original sequencing cases", "reproduced"if args.check else"generated")

if __name__ == "__main__":
    main()
