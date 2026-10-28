"""Original UPL retry scheduling/rounding witnesses, public-format programs only."""
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
WIDE = {1:[101,-300,201,300]}
RELAY = {1:[-100,-100,100,100],2:[-500,-100,500,100],3:[0,-100,400,100]}


def specifications():
    for rounds in (1,2,3,7):
        yield f"bad-rounds-{rounds}", {"limit":100,"pass_flags":rounds}, False
    for threshold in (0,199,200,201,255):
        yield f"wide-threshold-{threshold}", {"glyph_limits":WIDE,"threshold":threshold}, False
    for distance in (290,291):
        for threshold in (0,10):
            yield f"default-threshold-{distance}-{threshold}", {"flags_a":0,"flags_b":1,"distance":distance,"threshold":threshold}, False
    for threshold in (0,1):
        yield f"unit-threshold-{threshold}", {"flags_a":0,"flags_b":1,"distance":299,"threshold":threshold}, False
    for rounds in (2,3,4,7):
        yield f"relay-rounds-{rounds}", {"group_flags":[1,1,1],"glyph_limits":RELAY,"distance":50,"pass_flags":rounds}, False
    for threshold in (175,176):
        yield f"scaled-relay-{threshold}", {"group_flags":[1,1,1],"glyph_width":150,"distance":25,"threshold":threshold,
              "glyph_limits":{1:[-50,-100,50,100],2:[-250,-100,250,100],3:[0,-100,200,100]}}, False
    for threshold in (70,71):
        yield f"euclidean-threshold-{threshold}", {"flags_a":0,"flags_b":1,"distance":0,"threshold":threshold,
              "diagonal":[0,127,0,255],"boxes":{1:[0,0,100,100],2:[0,0,100,100]}}, False
    for flag in (0,1,17):
        yield f"neighbor-filter-{flag}", {"flags_b":flag,"glyph_limits":{1:[101,-300,201,300],2:[101,-100,201,100]}}, False
    for flag in (1,33,65,97,257,321,353):
        for rounds in (0,1,2):
            yield f"authored-flags-{flag}-{rounds}", {"flags_a":flag,"flags_b":flag,"pass_flags":rounds}, False
    yield "locked-threshold-255", {"flags_a":257,"flags_b":257,"threshold":255,"pass_flags":2}, False
    yield "margin-touch", {"glyph_limits":WIDE,"margin_a":50}, False
    for rounds in (3,7):
        yield f"fractional-one-pass-{rounds}", {"glyph_limits":WIDE,"margin_b":50,"pass_flags":rounds}, False
    for threshold in (1,10,20):
        yield f"fractional-threshold-{threshold}", {"glyph_limits":WIDE,"margin_b":50,"threshold":threshold}, False
    for shift in (0,100):
        yield f"fractional-prior-pass-{shift}", {"glyph_limits":WIDE,"margin_b":50,"prior":True,"obstacle_shift":shift}, False
    yield "prior-far-frozen", {"flags_a":0,"flags_b":1,"prior":True,"obstacle_shift":-2000}, False
    yield "far-frozen", {"group_flags":[0,1,1],"glyph_limits":{2:[-100,-100,100,100]},"far_frozen":True}, False
    for distance in (400,700,2000):
        yield f"search-window-{distance}", {"flags_a":1,"flags_b":0,"distance":distance,"glyph_limits":WIDE,"pass_flags":1}, False
    for kind in ("bad","mixed","ungrouped"):
        params = {"group_flags":[1,1,1,1]if kind=="ungrouped"else[1,9,5,1],"limit":100,"pass_flags":3}
        if kind == "mixed":
            params["glyph_limits"] = {3:[-1000,-1000,1000,1000],4:[-1000,-1000,1000,1000]}
        yield "groups-"+kind, params, False
    for rtl in (False,True):
        yield "reversed-pass", {"limit":100,"reverse":True}, rtl


def make(name,parameters,rtl):
    params = {"flags_a":1,"flags_b":1,"pass_flags":7}
    params.update(parameters)
    if params.get("prior"):
        params["pass_flags"] = 1
    if params.get("reverse"):
        params["pass_flags"] = 0
    data,action = base.collision.make(name,params,rtl)
    font = TTFont(io.BytesIO(data),recalcTimestamp=False)
    programs = [action]
    if params.get("far_frozen"):
        old = font.getTableData("Silf")
        action = geometry.set_attr(0,700)+geometry.NEXT+geometry.set_attr(0,100)+geometry.NEXT
        changed = bytearray(geometry.program(action+bytes([0x32]),True,(1,2,3)))
        for a,b in [(24,26),(35,36),(48,50),(84,85)]:
            changed[a:b] = old[a:b]
        base.raw(font,"Silf",changed)
        programs = [action]
    if params.get("prior") or params.get("reverse"):
        old = font.getTableData("Silf")
        second_action = b""if params.get("reverse")else(geometry.set_attr(20,params.get("obstacle_shift",0))+geometry.set_attr(0,100)+geometry.NEXT+geometry.set_attr(20,0))
        second = bytearray(geometry.program(second_action+bytes([0x32]),True,(1,2)))
        for a,b in [(24,26),(35,36),(48,50)]:
            second[a:b] = old[a:b]
        second[84] = 35 if params.get("reverse")else 7
        base.raw(font,"Silf",base.two_pass(old,bytes(second)))
        programs = [action,second_action]
    if params.get("glyph_limits"):
        glat = bytearray(font.getTableData("Glat"))
        gloc = font.getTableData("Gloc")
        for gid,limits in params["glyph_limits"].items():
            at = struct.unpack_from(">H",gloc,8+gid*2)[0]
            struct.pack_into(">4h",glat,at+6+4+2,*limits)
        base.raw(font,"Glat",glat)
    for gid,box in params.get("boxes",{}).items():
        pen = TTGlyphPen(None)
        x0,y0,x1,y1 = box
        pen.moveTo((x0,y0));pen.lineTo((x1,y0));pen.lineTo((x1,y1));pen.lineTo((x0,y1));pen.closePath()
        font["glyf"][font.getGlyphName(gid)] = pen.glyph()
    out = io.BytesIO()
    font.save(out,reorderTables=True)
    return out.getvalue(),programs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check",action="store_true")
    args = parser.parse_args()
    cases = []
    for label,parameters,rtl in specifications():
        name = "collision-retry-audit-"+label+("-rtl"if rtl else"-ltr")
        data,programs = make(name,parameters,rtl)
        path = HERE/(name+".ttf")
        if args.check:
            assert path.read_bytes()==data,path
        else:
            path.write_bytes(data)
        count = len(parameters.get("group_flags",[0,0]))
        cases.append({"id":name,"font":"retry-audit/"+path.name,"text":"".join(chr(97+i)for i in range(count)),
                      "direction":"rtl"if rtl else"ltr","positioning":True,"precontext":0,
                      "action":list(programs[0]),"programs":[list(p)for p in programs],"collision":parameters})
    output = json.dumps({"schema":1,"about":"Original UPL collision retry/threshold/flag and prior-pass float witnesses.","cases":cases},indent=2)+"\n"
    path = HERE/"cases.jsonc"
    if args.check:
        assert path.read_text()==output,path
    else:
        path.write_text(output)
    print(len(cases),"original retry cases", "reproduced"if args.check else"generated")

if __name__ == "__main__":
    main()
