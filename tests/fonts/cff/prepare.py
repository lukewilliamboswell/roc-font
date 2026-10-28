#!/usr/bin/env python3
"""Reproduce renamed OFL CFF subsets with fontTools 4.61.1.

The public source bytes and licences are pinned in source-pins.json. Supply
--download to populate the cache; --check only compares the derived outputs.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
import urllib.request
from fontTools import subset
from fontTools.ttLib import TTFont
import fontTools

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--cache", type=Path, default=Path("/private/tmp/roc-font-cff-sources"))
parser.add_argument("--download", action="store_true")
parser.add_argument("--check", action="store_true")
args = parser.parse_args()
assert fontTools.__version__ == "4.61.1"
sources = json.loads((HERE / "source-pins.json").read_text())["sources"]
files = {}
for source in sources:
    for info in source["files"]:
        cached = args.cache / info["cache"]
        if not cached.exists() and args.download:
            cached.parent.mkdir(parents=True, exist_ok=True)
            cached.write_bytes(urllib.request.urlopen(info["url"]).read())
        assert hashlib.sha256(cached.read_bytes()).hexdigest() == info["sha256"], cached
        files[info["cache"]] = cached

def save(path, data):
    if args.check:
        assert path.read_bytes() == data, f"regenerate {path}"
    else:
        path.write_bytes(data)

text = " ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,!?:;()[]+-=ÁÅÇÉÊÖÜáåçéêöüœﬁﬂΩαβγЖж−∑∫"
jobs = [
    ("source-sans-SourceSans3-Regular.otf", "sans-cff1.otf", "Cff Test Sans"),
    ("source-sans-SourceSans3VF-Upright.otf", "sans-cff2.otf", "Cff Test Variable Sans"),
    ("source-serif-SourceSerif4Variable-Roman.otf", "serif-cff2.otf", "Cff Test Variable Serif"),
    ("source-han-sans-SourceHanSans-Regular.otf", "cid-cff1.otf", "Cff Test CID"),
]
derived = []
with tempfile.TemporaryDirectory(prefix="cff-subsets-") as directory:
    for original, name, family in jobs:
        font = TTFont(files[original], recalcTimestamp=False)
        options = subset.Options()
        options.recalc_timestamp = False
        options.name_IDs = ["*"]
        options.name_legacy = True
        options.name_languages = ["*"]
        options.notdef_outline = True
        options.recommended_glyphs = True
        sub = subset.Subsetter(options=options)
        selected = set(map(ord, text))
        if name == "cid-cff1.otf":
            # Preserve real CID FDSelect references across as many source
            # FDs as available rather than a hand-written fake CID reader.
            top = font["CFF "].cff.topDictIndex[0]
            counts = {}
            glyphs = []
            for index, glyph in enumerate(font.getGlyphOrder()):
                fd = top.FDSelect[index]
                if counts.get(fd, 0) < 2:
                    counts[fd] = counts.get(fd, 0) + 1
                    glyphs.append(glyph)
            sub.populate(unicodes=selected | set(map(ord, "漢字日本語天地玄黄")), glyphs=glyphs)
        else:
            sub.populate(unicodes=selected)
        sub.subset(font)
        ps_name = family.replace(" ", "") + "-Regular"
        # OFL Reserved Font Names are not retained in modified font names.
        for record in font["name"].names:
            if record.nameID in (1, 3, 4, 6, 16, 17, 18, 21, 22, 25):
                value = ps_name if record.nameID in (3, 6, 25) else "Regular" if record.nameID in (17, 22) else family
                record.string = value.encode(record.getEncoding())
        if "fvar" in font:
            for index, instance in enumerate(font["fvar"].instances):
                if instance.postscriptNameID != 0xFFFF:
                    font["name"].setName(ps_name + str(index), instance.postscriptNameID, 3, 1, 0x409)
        if "CFF " in font:
            cff = font["CFF "].cff
            cff.fontNames = [ps_name]
            top = cff.topDictIndex[0]
            top.FullName = family
            top.FamilyName = family
            if hasattr(top, "FDArray"):
                for index, fd in enumerate(top.FDArray):
                    fd.FontName = ps_name + f"FD{index}"
        output = Path(directory) / name
        font.save(output)
        data = output.read_bytes()
        save(HERE / name, data)
        derived.append({"file": name, "source": original, "glyphs": font["maxp"].numGlyphs,
                        "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
for source in sources:
    for info in source["files"]:
        if "LICENSE" in info["path"]:
            save(HERE / (source["repo"] + "-OFL.txt"), files[info["cache"]].read_bytes())
save(HERE / "derived-pins.json", (json.dumps({"fontTools": fontTools.__version__, "fonts": derived}, indent=2) + "\n").encode())
print(json.dumps(derived, indent=2))
