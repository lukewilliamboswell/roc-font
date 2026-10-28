"""Renamed OFL Inter body with an original mort consumer program.

This is not a claim that Inter ships legacy AAT. It gives fuzzing a real
font body/GDEF/GPOS/cmap/outline set while exercising the original program.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import runpy
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
factory = runpy.run_path(str(HERE / "generate.py"))
parser = argparse.ArgumentParser(); parser.add_argument("--check",action="store_true"); args = parser.parse_args()
source = ROOT / "package/fonts/Inter-Variable.ttf"
font = TTFont(source,recalcTimestamp=False)
font = instantiateVariableFont(font,{axis.axisTag:axis.defaultValue for axis in font["fvar"].axes},inplace=True)
options = subset.Options(); options.recalc_timestamp = False; options.name_IDs = ["*"]; options.name_legacy = True; options.name_languages = ["*"]
subsetter = subset.Subsetter(options=options); subsetter.populate(unicodes=list(map(ord," ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzfiÁΩαβ\u0301"))); subsetter.subset(font)
for record in font["name"].names:
    if record.nameID in (1,3,4,6,16,17,18,21,22,25):
        value = "MortBodySans-Regular" if record.nameID in (3,6,25) else "Regular" if record.nameID in (17,22) else "Mort Body Sans"
        record.string = value.encode(record.getEncoding())
glyph_a = font.getGlyphID(font.getBestCmap()[ord("A")])
glyph_b = font.getGlyphID(font.getBestCmap()[ord("B")])
table = DefaultTable("mort"); table.data = factory["mort"](factory["lookup"](glyph_a,[glyph_b]),4,0x3000); font["mort"] = table
output = io.BytesIO(); font.save(output)
data = output.getvalue()
files = {"body-sans.ttf":data,"body-sans-OFL.txt":(ROOT / "package/fonts/Inter-OFL.txt").read_bytes()}
pin = {"source":"package/fonts/Inter-Variable.ttf","source_sha256":hashlib.sha256(source.read_bytes()).hexdigest(),
       "origin":"Inter4.1, the repository's unmodified default font", "derived_sha256":hashlib.sha256(data).hexdigest(),
       "program":"Original mort format4 maps A's glyph to B's; other glyphs retain the font's bodies and position tables.",
       "glyph_a":glyph_a,"glyph_b":glyph_b,"glyphs":font["maxp"].numGlyphs}
files["real-pins.json"] = (json.dumps(pin,indent=2)+"\n").encode()
cases = []
for text in ["","A","AV","ABC","fi","ÁV","aAΩ","AAAA","A B"]:
    for direction in ["ltr","rtl","ttb","btt"]:
        cases.append({"id":"mort-real-"+direction+"-"+text.encode().hex(),"font":"body-sans.ttf","text":text,
                      "options":{"script":"Latn","direction":direction,"hb_options":["--show-flags"]},"expected":"oracle"})
files["body-cases.jsonc"] = (json.dumps({"schema":1,"about":"Renamed OFL real Inter body plus original mort consumer program; not a native legacy producer font.","cases":cases},indent=2,ensure_ascii=False)+"\n").encode()
for name, content in files.items():
    path = HERE / name
    if args.check: assert path.read_bytes() == content, path
    else: path.write_bytes(content)
