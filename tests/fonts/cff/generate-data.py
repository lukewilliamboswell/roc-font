#!/usr/bin/env python3
"""Generate fixed CFF encoding/charset facts from pinned fontTools 4.61.1.

The SID sequences are Adobe CFF format constants, not Unicode properties.
No font bytes or executable reference implementation enter the bundle.
"""
import argparse
from pathlib import Path
import fontTools
from fontTools import cffLib
from fontTools.encodings.StandardEncoding import StandardEncoding

assert fontTools.__version__ == "4.61.1", fontTools.__version__
root = Path(__file__).resolve().parents[3]
sid = {name: index for index, name in enumerate(cffLib.cffStandardStrings)}
tables = {
    "standard_encoding": [sid[name] for name in StandardEncoding],
    "expert": [sid[name] for name in cffLib.cffIExpertStrings],
    "expert_subset": [sid[name] for name in cffLib.cffExpertSubsetStrings],
}
text = """## Adobe CFF standard SID sequences, generated with fontTools4.61.1.
## Source: Adobe Technical Note5176, appendices A/B/C.
## Regenerate: tests/fonts/cff/generate-data.py (oracle environment).
TableCffData :: {}.{
"""
for name, values in tables.items():
    text += f"\t{name} : List(U64)\n\t{name} = [{', '.join(map(str, values))}]\n"
text += "}\n"
dest = root / "package/TableCffData.roc"
args = argparse.ArgumentParser()
args.add_argument("--check", action="store_true")
if args.parse_args().check:
    assert dest.read_text() == text, "regenerate TableCffData.roc"
else:
    dest.write_text(text)
