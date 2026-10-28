"""Original UPL kerning witnesses: public-format fonts, never engine source.

Imports only the owned original fixture builders. Behavior/oracle records come
separately from the public Graphite2 C ABI and public gr_start_logging JSON.
"""
import argparse
import io
import json
from pathlib import Path
import struct
import sys
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
from fontTools.pens.ttGlyphPen import TTGlyphPen

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import collision_generate as collision
import generate as geometry


def specifications():
    for rtl in (False, True):
        yield "base", {}, rtl
        yield "prior-x", {"prior": "x"}, rtl
        yield "prior-y", {"prior": "y"}, rtl
        for bounds in [(-100, 100), (50, 100), (-100, -50), (500, 100), (-50, -100), (500, 1000), (-1000, -500)]:
            yield "bounds-" + "-".join(map(str, bounds)), {"bounds": bounds}, rtl
        for bounds in [(0, 100), (-100, 0), (-10, 10), (100, -100)]:
            yield "prior-bounds-" + "-".join(map(str, bounds)), {"prior": "x", "next_bounds": bounds}, rtl
        for which in ("target", "neighbor"):
            for active in (False, True):
                yield f"blank-{which}-{'active' if active else 'disabled'}", {"blank": which, "pass_flags": 9 if active else 0}, rtl
    for margin in (10, 50, 101):
        yield f"float-margin-{margin}", {"margin": margin, "diagonals": {1: [0, 255, 200, 255]}}, True
    for height in (1, 3, 9):
        yield f"bins-height-{height}", {"height": height}, True
    for y in (600, 609):
        yield f"bins-neighbor-y-{y}", {"shift_y": y}, True
    for name, diagonal in [("sum-min", [127,255,0,255]), ("diff-min", [0,255,127,255]),
                           ("sum-max", [0,127,0,255]), ("diff-max", [0,255,0,127])]:
        for rtl in (False, True):
            yield "edge-" + name, {"diagonal": diagonal}, rtl
    yield "blank-point-target", {"phase1": "target"}, False
    yield "blank-point-obstacle", {"phase1": "obstacle"}, False
    for d in (0, 100, 1000):
        yield f"space-distance-{d}", {"group_flags": [17,128,0], "distance": d}, True
    yield "ignore-distance-100", {"group_flags": [17,2,0], "distance": 100}, True
    for attachment in ("forward", "backward"):
        for flags in ([17,0,0], [0,17,0]):
            yield "child-" + attachment + "-" + "-".join(map(str,flags)), {"group_flags": flags, "attachment": attachment}, True
    for gid in (1, 2):
        for exclude in (-1, 1, 32767):
            yield f"exclude-{gid}-{exclude}", {"dynamic_exclude": [gid,exclude]}, True


def raw(font, tag, data):
    table = DefaultTable(tag)
    table.data = bytes(data)
    font[tag] = table


def configure_program(action, old):
    program = bytearray(geometry.program(action + bytes([0x32]), True, (1,2)))
    # Preserve only original builder metadata, not offsets tied to code size.
    for start,end in [(24,26), (35,36), (48,50), (84,85)]:
        program[start:end] = old[start:end]
    return bytes(program)


def two_pass(first, second):
    body1, body2 = first[84:], second[84:]
    def relocate(body, delta):
        result = bytearray(body)
        for at in (8,12,16):
            struct.pack_into(">I", result, at, struct.unpack_from(">I", result, at)[0] + delta)
        return bytes(result)
    header = bytearray(first[:58])
    header[30] = header[33] = 2
    struct.pack_into(">H", header, 22, 54)
    return bytes(header) + struct.pack(">III",72,72+len(body1),72+len(body1)+len(body2)) + first[66:84] + relocate(body1,4) + relocate(body2,4+len(body1))


def make(name, parameters, rtl):
    params = {"pass_flags": 9, "flags_a": 17, "flags_b": 0}
    params.update(parameters)
    if params.get("prior"):
        params.update(pass_flags=1, flags_a=1, flags_b=0)
    if params.get("phase1"):
        params.update(pass_flags=1, flags_a=0, flags_b=1, distance=0,
                      shift_x=100 if params["phase1"] == "target" else -100,
                      shift_y=100 if params["phase1"] == "target" else -100)
    data, action = collision.make(name, params, rtl)
    font = TTFont(io.BytesIO(data), recalcTimestamp=False)
    programs = [action]
    if params.get("dynamic_exclude"):
        gid, exclude = params["dynamic_exclude"]
        extra = geometry.set_attr(66,exclude) + geometry.set_attr(67,100) + geometry.set_attr(68,0)
        action = extra + action if gid == 1 else action + extra
        raw(font, "Silf", configure_program(action,font.getTableData("Silf")))
        programs = [action]
    if params.get("prior"):
        old = font.getTableData("Silf")
        if params["prior"] == "y":
            action = (geometry.set_attr(21,500) + geometry.NEXT + geometry.set_attr(0,0)) if rtl else (geometry.set_attr(0,0) + geometry.set_attr(21,500) + geometry.NEXT)
            old = configure_program(action, old)
        second = geometry.set_attr(57,17)
        if params.get("next_bounds"):
            lo,hi = params["next_bounds"]
            second += geometry.set_attr(58,lo) + geometry.set_attr(60,hi)
        second += geometry.NEXT + geometry.set_attr(57,0)
        next_program = bytearray(configure_program(second,old))
        next_program[84] = 9
        raw(font,"Silf",two_pass(old,bytes(next_program)))
        programs = [action,second]
    if params.get("bounds") or params.get("diagonals"):
        glat = bytearray(font.getTableData("Glat"))
        gloc = font.getTableData("Gloc")
        for gid in range(font["maxp"].numGlyphs):
            at = struct.unpack_from(">H",gloc,8+gid*2)[0]
            if params.get("bounds"):
                lo,hi = params["bounds"]
                struct.pack_into(">h",glat,at+6+4+2,lo)
                struct.pack_into(">h",glat,at+6+4+6,hi)
            if gid in params.get("diagonals",{}):
                glat[at+2:at+6] = bytes(params["diagonals"][gid])
        raw(font,"Glat",glat)
    blank = params.get("blank")
    boxes = {}
    if blank:
        boxes[1 if blank == "target" else 2] = None
    if params.get("phase1"):
        boxes[2 if params["phase1"] == "target" else 1] = None
    if params.get("height"):
        boxes.update({1:(0,0,300,params["height"]),2:(0,0,300,params["height"])})
    for gid,box in boxes.items():
        pen = TTGlyphPen(None)
        if box is not None:
            x0,y0,x1,y1 = box
            pen.moveTo((x0,y0));pen.lineTo((x1,y0));pen.lineTo((x1,y1));pen.lineTo((x0,y1));pen.closePath()
        font["glyf"][font.getGlyphName(gid)] = pen.glyph()
    output = io.BytesIO()
    font.save(output,reorderTables=True)
    return output.getvalue(), programs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check",action="store_true")
    args = parser.parse_args()
    cases = []
    for label,parameters,rtl in specifications():
        name = "collision-kern-audit-" + label + ("-rtl" if rtl else "-ltr")
        data,programs = make(name,parameters,rtl)
        file = HERE / (name + ".ttf")
        if args.check:
            assert file.read_bytes() == data,file
        else:
            file.write_bytes(data)
        count = len(parameters.get("group_flags",[0,0]))
        cases.append({"id":name,"font":"kerning-audit/"+file.name,
                      "text":"".join(chr(97+i)for i in range(count)),
                      "direction":"rtl"if rtl else"ltr","positioning":True,"precontext":0,
                      "action":list(programs[0]),"programs":[list(p)for p in programs],"collision":parameters})
    output = json.dumps({"schema":1,"about":"Original UPL public-C-API kerning witnesses; no engine implementation source.","cases":cases},indent=2) + "\n"
    path = HERE / "cases.jsonc"
    if args.check:
        assert path.read_text() == output,path
    else:
        path.write_text(output)
    print(len(cases),"original kerning audit cases", "reproduced"if args.check else"generated")

if __name__ == "__main__":
    main()
