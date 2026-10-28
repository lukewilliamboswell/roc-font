#!/usr/bin/env python3
"""Original UPL Type2 operator, subroutine, seac and calculator witnesses."""
import argparse
import io
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.misc.psCharStrings import T2CharString
from fontTools.cffLib import SubrsIndex

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

def build(selected, seed=12345):
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
    top.Private.Subrs.append(T2CharString(program=[25, 35, "rlineto", "return"], private=top.Private, globalSubrs=fb.font["CFF "].cff.GlobalSubrs))
    fb.font["CFF "].cff.GlobalSubrs.append(T2CharString(program=[45, 55, "rlineto", "return"], private=top.Private, globalSubrs=fb.font["CFF "].cff.GlobalSubrs))
    for cs in strings.values():
        cs.private = top.Private
        cs.globalSubrs = fb.font["CFF "].cff.GlobalSubrs
    fb.font.recalcBBoxes = False
    fb.font.recalcTimestamp = False
    fb.font["head"].created = fb.font["head"].modified = 2082844800
    output = io.BytesIO()
    fb.font.save(output)
    return output.getvalue()

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
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
