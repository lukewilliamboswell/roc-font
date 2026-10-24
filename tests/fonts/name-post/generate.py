"""Generate the tiny `name` and `post` fixtures in this directory.

Run with the pinned oracle environment (fontTools 4.61.1):

    tools/oracle/.venv/bin/python -I tests/fonts/name-post/generate.py

The output is byte-for-byte reproducible. Each font has a handful of empty
glyphs; what matters are its `name` and `post` tables. fontTools writes
only format 0 naming tables and cannot write `post` version 2.5, so
`format1-v25.ttf` gets both tables assembled by hand.
"""
import os
import struct

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import newTable
from fontTools.ttLib.tables.DefaultTable import DefaultTable

HERE = os.path.dirname(os.path.abspath(__file__))


def base_font(glyph_names, post):
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(glyph_names)
    fb.setupCharacterMap({0x41 + i: name for i, name in enumerate(glyph_names[1:])})
    empty = TTGlyphPen(None).glyph()
    fb.setupGlyf({name: empty for name in glyph_names})
    fb.setupHorizontalMetrics({name: (500, 0) for name in glyph_names})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupOS2(usWinAscent=800, usWinDescent=200)
    version = post.pop("formatType")
    fb.setupPost(keepGlyphNames=version == 2.0, **post)
    # FontBuilder chooses only between versions 2.0 and 3.0.
    fb.font["post"].formatType = version
    fb.setupHead(unitsPerEm=1000, created=0, modified=0)
    return fb


def name_table(records):
    """records: (string, nameID, platformID, platEncID, langID)."""
    table = newTable("name")
    table.names = []
    for string, name_id, platform, encoding, language in records:
        table.setName(string, name_id, platform, encoding, language)
    return table


def raw(tag, data):
    table = DefaultTable(tag)
    table.data = data
    return table


def save(fb, name):
    path = os.path.join(HERE, name)
    fb.font.save(path)
    print(name, os.path.getsize(path))


def mac_roman_v1():
    """Only a Macintosh Roman family name, with characters past ASCII;
    `post` version 1.0 for eight glyphs (the first eight standard names)."""
    names = [".notdef", ".null", "nonmarkingreturn", "space", "exclam", "quotedbl", "numbersign", "dollar"]
    fb = base_font(names, dict(formatType=1.0, underlinePosition=-150, underlineThickness=60, italicAngle=-12.5, isFixedPitch=1))
    fb.font["name"] = name_table([
        ("Café™ Mac", 1, 1, 0, 0),
        ("Regular", 2, 1, 0, 0),
    ])
    save(fb, "mac-roman-v1.ttf")


def ranking_v2():
    """Family names on every platform: the best name ID 1 is the British
    English one, but a typographic family name (ID 16) in US English with a
    character outside the BMP wins. `post` version 2.0 with stored names,
    one of them past ASCII."""
    names = [".notdef", "space", "A", "a.alt", "café", "uni1F600"]
    fb = base_font(names, dict(formatType=2.0, underlinePosition=-100, underlineThickness=50))
    fb.font["name"] = name_table([
        ("Deutsch", 1, 3, 1, 0x407),
        ("Mac Family", 1, 1, 0, 0),
        ("Unicode Family", 1, 0, 3, 0),
        ("British Family", 1, 3, 1, 0x809),
        ("Mac Typo", 16, 1, 0, 0),
        ("Emoji \U0001F600 Sans", 16, 3, 10, 0x409),
    ])
    save(fb, "ranking-v2.ttf")


def utf16(text):
    return text.encode("utf-16-be")


def name_format1():
    """A format 1 naming table whose only family names are on the Unicode
    platform with language tags `de` and `EN-us`."""
    strings = [utf16("Deutsch Tag"), utf16("English Tag"), utf16("de"), utf16("EN-us")]
    offsets = []
    at = 0
    for s in strings:
        offsets.append(at)
        at += len(s)
    records = [(0, 4, 0x8000, 1, 0), (0, 4, 0x8001, 1, 1)]
    storage = 6 + 12 * len(records) + 2 + 4 * 2
    out = struct.pack(">HHH", 1, len(records), storage)
    for platform, encoding, language, name_id, k in records:
        out += struct.pack(">HHHHHH", platform, encoding, language, name_id, len(strings[k]), offsets[k])
    out += struct.pack(">H", 2)
    for k in (2, 3):
        out += struct.pack(">HH", len(strings[k]), offsets[k])
    return out + b"".join(strings)


def post_v25():
    """`post` version 2.5 for five glyphs named .notdef, A, B, space and a."""
    header = struct.pack(">IiHhIIIII", 0x00025000, 0, (-120) & 0xFFFF, 40, 0, 0, 0, 0, 0)
    standard = [0, 36, 37, 3, 68]
    offsets = [s - g for g, s in enumerate(standard)]
    return header + struct.pack(">H", 5) + struct.pack(">5b", *offsets)


def format1_v25():
    names = [".notdef", "A", "B", "space", "a"]
    fb = base_font(names, dict(formatType=3.0))
    fb.font["name"] = raw("name", name_format1())
    fb.font["post"] = raw("post", post_v25())
    save(fb, "format1-v25.ttf")


def japanese_v3():
    """Only a Japanese Windows family name; `post` version 3.0."""
    names = [".notdef", "A", "B"]
    fb = base_font(names, dict(formatType=3.0, underlinePosition=-75, underlineThickness=25, italicAngle=11.25))
    fb.font["name"] = name_table([("日本語フォント", 1, 3, 1, 0x411)])
    save(fb, "japanese-v3.ttf")


if __name__ == "__main__":
    mac_roman_v1()
    ranking_v2()
    format1_v25()
    japanese_v3()
