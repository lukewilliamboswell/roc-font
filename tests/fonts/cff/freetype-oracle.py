#!/usr/bin/env python3
"""Controlled FreeType2.13.2 oracle for Type2 calculator/random operators.

FreeType uses16.16 arithmetic and returns integer NO_SCALE points. Its
quantized paths validate our finite F64 calculator results; they do not
serve as an exact F64 oracle. A fresh face is used for each glyph because
FreeType's random state is mutable whereas roc-font queries are pure.
"""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import freetype
from fontTools.ttLib import TTFont

HERE = Path(__file__).resolve().parent

def path(face, glyph):
    face.load_glyph(glyph, freetype.FT_LOAD_NO_SCALE | freetype.FT_LOAD_NO_HINTING |
                    freetype.FT_LOAD_NO_BITMAP | freetype.FT_LOAD_NO_AUTOHINT)
    commands = []
    def point(p):
        return [p.x, p.y]
    def move(p, _):
        if commands:
            commands.append(["closePath", []])
        commands.append(["moveTo", [point(p)]])
    def line(p, _):
        commands.append(["lineTo", [point(p)]])
    def cubic(a, b, end, _):
        commands.append(["curveTo", [point(a), point(b), point(end)]])
    def conic(a, end, _):
        commands.append(["qCurveTo", [point(a), point(end)]])
    face.glyph.outline.decompose(move_to=move, line_to=line, cubic_to=cubic, conic_to=conic)
    if commands:
        commands.append(["closePath", []])
    return commands

def generate():
    assert freetype.version() == (2, 13, 2), freetype.version()
    file = HERE / "calculator-cff1.otf"
    names = TTFont(file).getGlyphOrder()
    records = []
    # Property0 honors the font's initialRandomSeed12345. Positive54321
    # overrides it; retaining both proves the property has an effect.
    for font_seed, property_seed in ((12345, 0), (12345, 54321), (0, 0), (-12345, 0)):
        file = HERE / ("calculator-cff1.otf" if font_seed == 12345 else f"calculator-seed{font_seed}-cff1.otf")
        seed = ctypes.c_int32(property_seed)
        for glyph, name in enumerate(names):
            # The driver advances its seed when creating each face. Reset
            # the property for every face, not merely once per font.
            error = freetype.FT_Property_Set(freetype.get_handle(), b"cff", b"random-seed", ctypes.byref(seed))
            assert error == 0, error
            face = freetype.Face(str(file))
            query_file = HERE / ("calculator-seed54321-cff1.otf" if property_seed else file.name)
            records.append({"font": file.name, "query_font": query_file.name,
                            "query_sha256": hashlib.sha256(query_file.read_bytes()).hexdigest(), "glyph": glyph, "name": name,
                            "property_random_seed": property_seed,
                            "font_initial_random_seed": font_seed,
                            "actual_seed": property_seed or abs(font_seed) or 987654321,
                            "path": path(face, glyph)})
    reset = ctypes.c_int32(0)
    assert freetype.FT_Property_Set(freetype.get_handle(), b"cff", b"random-seed", ctypes.byref(reset)) == 0
    return {"FreeType": "2.13.2", "flags": ["NO_SCALE", "NO_HINTING", "NO_BITMAP", "NO_AUTOHINT"],
            "policy": "Fresh face per glyph; property0 honors font initialRandomSeed12345; property54321 overrides it.",
            "records": records}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data = json.dumps(generate(), separators=(",", ":")) + "\n"
    destination = HERE / "freetype-oracle.json"
    if args.check:
        assert destination.read_text() == data, "regenerate freetype-oracle.json"
    else:
        destination.write_text(data)
    print("FreeType:160controlled calculator/random glyph records")
