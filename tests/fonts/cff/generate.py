#!/usr/bin/env python3
"""Original UPL Type2 operator, subroutine, seac and calculator witnesses."""
import argparse
import io
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.misc.psCharStrings import T2CharString
from fontTools.cffLib import SubrsIndex, FDSelect, cffIExpertStrings, cffExpertSubsetStrings, cffStandardStrings
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable

HERE = Path(__file__).resolve().parent
START = [10, 20, "rmoveto"]
END = ["endchar"]
programs = {
    ".notdef": ["endchar"], "space": ["endchar"],
    "A": START + [100, 0, 0, 100, -100, 0, "rlineto"] + END,
    "acute": [0, 0, "rmoveto", 30, 50, "rlineto"] + END,
    "seac": [20, 200, 65, 194, "endchar"],
    "rlineto": START + [10, 20, 30, 40, "rlineto"] + END,
    "hlineto": START + [10, 20, 30, "hlineto"] + END,
    "vlineto": START + [10, 20, 30, "vlineto"] + END,
    "rrcurveto": START + [10, 20, 30, 40, 50, 60, "rrcurveto"] + END,
    "rcurveline": START + [10, 20, 30, 40, 50, 60, 70, 80, "rcurveline"] + END,
    "rlinecurve": START + [10, 20, 30, 40, 50, 60, 70, 80, "rlinecurve"] + END,
    "vvcurveto": START + [5, 10, 20, 30, 40, 50, 60, 70, 80, "vvcurveto"] + END,
    "hhcurveto": START + [5, 10, 20, 30, 40, 50, 60, 70, 80, "hhcurveto"] + END,
    "hvcurveto": START + [10, 20, 30, 40, 50, 60, 70, 80, 90, "hvcurveto"] + END,
    "vhcurveto": START + [10, 20, 30, 40, 50, 60, 70, 80, 90, "vhcurveto"] + END,
    "hflex": START + [10, 20, 30, 40, 50, 60, 70, "hflex"] + END,
    "flex": START + list(range(10, 140, 10)) + ["flex"] + END,
    "hflex1": START + list(range(10, 100, 10)) + ["hflex1"] + END,
    "flex1x": START + [100, 2, 30, 4, 50, 6, 70, 8, 90, 10, 20, "flex1"] + END,
    "flex1y": START + [1, 200, 3, 40, 5, 60, 7, 80, 9, 100, 20, "flex1"] + END,
    "hints": [500, 10, 20, "hstem", 30, 40, "vstemhm", "hintmask", b"\xc0"] + START + [50, 50, "rlineto"] + END,
    "locals": START + [-107, "callsubr", -107, "callgsubr"] + END,
    "moveonly": START + END,
    "calcadd": START + [7, 3, "add", 20, "rlineto"] + END,
    "calcsub": START + [7, 3, "sub", 20, "rlineto"] + END,
    "calcdiv": START + [12, 3, "div", 20, "rlineto"] + END,
    "calcmul": START + [7, 3, "mul", 20, "rlineto"] + END,
    "calcsqrt": START + [9, "sqrt", 20, "rlineto"] + END,
    "calcabsneg": START + [-7, "abs", "neg", 20, "rlineto"] + END,
    "calcand": START + [7, 3, "and", 20, "rlineto"] + END,
    "calcor": START + [0, 3, "or", 20, "rlineto"] + END,
    "calcnot": START + [0, "not", 20, "rlineto"] + END,
    "calceq": START + [7, 7, "eq", 20, "rlineto"] + END,
    "calcifelse": START + [7, 3, 1, 2, "ifelse", 20, "rlineto"] + END,
    "calcputget": START + [7, 31, "put", 31, "get", 20, "rlineto"] + END,
    "calcdup": START + [7, "dup", "rlineto"] + END,
    "calcexch": START + [7, 20, "exch", "rlineto"] + END,
    "calcindex": START + [7, 20, 1, "index", "drop", "rlineto"] + END,
    "calcroll": START + [7, 20, 2, 1, "roll", "rlineto"] + END,
    "random": START + ["random", 1000, "mul", 50, "rlineto", "random", 1000, "mul", 50, "rlineto", "random", 1000, "mul", 50, "rlineto"] + END,
}

def build(selected, seed=12345, subr_count=1):
    fb = FontBuilder(1000, isTTF=False)
    names = list(selected)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap({32: "space", **{0xE000 + i: name for i, name in enumerate(names) if name not in (".notdef", "space")}})
    fb.setupHorizontalMetrics({name: (600, 0) for name in names})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable({"familyName": "Original CFF Operator Tests", "styleName": "Regular", "psName": "OriginalCffOperators-Regular"})
    fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
    fb.setupPost()
    strings = {name: T2CharString(program=program) for name, program in selected.items()}
    fb.setupCFF("OriginalCffOperators-Regular", {"FullName": "Original CFF Operator Tests", "FamilyName": "Original CFF Operator Tests", "FontBBox": [0, 0, 5000, 5000]}, strings, {"initialRandomSeed": seed})
    top = fb.font["CFF "].cff.topDictIndex[0]
    top.Private.Subrs = SubrsIndex()
    for index in range(subr_count):
        top.Private.Subrs.append(T2CharString(program=[25, 35, "rlineto", "return"] if index == 0 else ["return"], private=top.Private, globalSubrs=fb.font["CFF "].cff.GlobalSubrs))
        fb.font["CFF "].cff.GlobalSubrs.append(T2CharString(program=[45, 55, "rlineto", "return"] if index + 1 == subr_count else ["return"], private=top.Private, globalSubrs=fb.font["CFF "].cff.GlobalSubrs))
    for cs in strings.values():
        cs.private = top.Private
        cs.globalSubrs = fb.font["CFF "].cff.GlobalSubrs
    fb.font.recalcBBoxes = False
    fb.font.recalcTimestamp = False
    fb.font["head"].created = fb.font["head"].modified = 2082844800
    output = io.BytesIO()
    fb.font.save(output)
    return output.getvalue()

def variable(count, select_format):
    font = TTFont(io.BytesIO(build({".notdef": END, "space": END, "A": END, "flex": END})), recalcBBoxes=False, recalcTimestamp=False)
    font.getGlyphOrder()
    del font["CFF "]
    fb = FontBuilder(font=font, isTTF=False)
    fb.setupFvar([("wght", 0, 0, 1000, "Weight")], [])
    line = [0, 0, "rmoveto"]
    for _ in range(count):
        line += [1, 2, 2, 1, "blend", 2, 2, 1, "blend", 1, "rlineto"]
    flex = [0, 0, "rmoveto", 0, 200, 0, 1, "blend", 20, 0, 20, 0, 20, 0, 20, 0, 20, 10, "flex1"]
    strings = {name: T2CharString(program=program) for name, program in {".notdef": [], "space": [], "A": line, "flex": flex}.items()}
    fb.setupCFF2(strings, fdArrayList=[{}, {}], regions=[{"wght": (0, 1, 1)}, {}])
    top = font["CFF2"].cff.topDictIndex[0]
    select = FDSelect(format=select_format)
    select.gidArray = [0, 0, 1, 1]
    top.FDSelect = select
    top.CharStrings.fdSelect = select
    for index, name in enumerate(font.getGlyphOrder()):
        strings[name].fdSelectIndex = select.gidArray[index]
        strings[name].private = top.FDArray[select.gidArray[index]].Private
    output = io.BytesIO()
    font.save(output)
    return output.getvalue()

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    def emit(file, data):
        if args.check:
            assert (HERE / file).read_bytes() == data, file
        else:
            (HERE / file).write_bytes(data)
    for file, selected in [("operators-cff1.otf", {name: program for name, program in programs.items() if not name.startswith("calc") and name != "random"}),
                           ("calculator-cff1.otf", programs)]:
        data = build(selected)
        if args.check:
            assert (HERE / file).read_bytes() == data, file
        else:
            (HERE / file).write_bytes(data)
        print(file, len(data), len(selected))
    for seed in (0, -12345, 54321):
        file = f"calculator-seed{seed}-cff1.otf"
        data = build(programs, seed)
        if args.check:
            assert (HERE / file).read_bytes() == data, file
        else:
            (HERE / file).write_bytes(data)
    for count in (16, 64, 256):
        program = [0, 0, "rmoveto"] + [value for _ in range(count) for value in (1, 1, "rlineto")] + END
        data = build({".notdef": END, "space": END, "A": program})
        file = f"lines-{count}-cff1.otf"
        if args.check:
            assert (HERE / file).read_bytes() == data, file
        else:
            (HERE / file).write_bytes(data)
    for file, names in [("expert-cff1.otf", cffIExpertStrings),
                        ("expert-subset-cff1.otf", cffExpertSubsetStrings),
                        ("charset2-cff1.otf", cffStandardStrings[:300])]:
        selected = {name: END if name in (".notdef", "space") else START + [20, 30, "rlineto"] + END for name in names}
        emit(file, build(selected))
    for count, bias in ((1240, 1131), (33900, 32768)):
        selected = {".notdef": END, "space": END,
                    "A": START + [-bias, "callsubr", count - 1 - bias, "callgsubr"] + END}
        emit(f"bias-{count}-cff1.otf", build(selected, subr_count=count))
    # Malformed required tables retain valid surrounding SFNT structure.
    font = TTFont(HERE / "operators-cff1.otf", recalcBBoxes=False, recalcTimestamp=False)
    font.getGlyphOrder()
    top = font["CFF "].cff.topDictIndex[0]
    raw = font.getTableData("CFF ")
    index = top.CharStrings.charStringsIndex
    local = top.Private.Subrs
    changes = {"bad-index-cff1.otf": raw[:top.rawDict["CharStrings"] + 3]}
    bad_call = bytearray(raw)
    start = index.offsetBase + index.offsets[21]
    assert bad_call[start + 3:start + 5] == b"\x20\x0a"
    bad_call[start + 3] = 33  # -106 selects missing local subroutine1.
    changes["bad-subr-cff1.otf"] = bytes(bad_call)
    cycle = bytearray(raw)
    subr_start = local.offsetBase + local.offsets[0]
    assert cycle[subr_start:subr_start + 4] == bytes([164, 174, 5, 11])
    cycle[subr_start:subr_start + 4] = bytes([32, 10, 11, 11])
    changes["cycle-subr-cff1.otf"] = bytes(cycle)
    for file, data in changes.items():
        table = DefaultTable("CFF ")
        table.data = data
        font["CFF "] = table
        output = io.BytesIO()
        font.save(output)
        emit(file, output.getvalue())
    boundary = [32767, "dup", "mul", 32767, 2, "mul", "add", 0, "rmoveto"]
    for file, tail in [("coordinate-edge-cff1.otf", END),
                       ("coordinate-outside-cff1.otf", [1, 0, "rlineto"] + END)]:
        emit(file, build({".notdef": END, "space": END, "A": boundary + tail}))
    seac_cycle = {".notdef": END, "space": END, "A": [0, 0, 65, 194, "endchar"], "acute": START + [10, 10, "rlineto"] + END}
    emit("cycle-seac-cff1.otf", build(seac_cycle))
    for count, select_format in ((16, 0), (64, 3), (256, 4)):
        emit(f"blends-{count}-cff2.otf", variable(count, select_format))
    font = TTFont(io.BytesIO(variable(1, 4)), recalcBBoxes=False, recalcTimestamp=False)
    font.getGlyphOrder()
    top = font["CFF2"].cff.topDictIndex[0]
    raw = bytearray(font.getTableData("CFF2"))
    first_fd_end = top.FDArray.offsetBase + top.FDArray.offsets[1]
    assert raw[first_fd_end - 1] == 18
    raw[first_fd_end - 1] = 2  # unknown key clears args; PrivateDICT absent
    table = DefaultTable("CFF2")
    table.data = bytes(raw)
    font["CFF2"] = table
    output = io.BytesIO()
    font.save(output)
    emit("missing-private-cff2.otf", output.getvalue())
