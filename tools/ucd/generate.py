#!/usr/bin/env python3
"""Write package/ShaperUnicodeData.roc from the pinned Unicode Character
Database files (tools/ucd/pins.json).

The shaper needs a few Unicode character properties to do what HarfBuzz
does before and around GSUB (architecture §6.2): the general category
(marks, letters, spaces, digits), the canonical combining class (mark
reordering), canonical decompositions and the compositions HarfBuzz allows
(compose or decompose by what the cmap maps), the bidi mirroring glyph
(right-to-left text) and Extended_Pictographic (emoji ZWJ sequences stay
one cluster). Nothing else is embedded.

Each table is one string of fixed-width records of upper-case hexadecimal
digits, sorted by its first field, so a lookup is a binary search:

  general_categories  SSSSSSgg     a run of code points from S with general
                                   category gg (HarfBuzz's
                                   hb_unicode_general_category_t), up to the
                                   next run; unlisted code points are Cn
  combining_classes   SSSSSScc     a run from S with combining class cc
  decompositions      CCCCCCAAAAAABBBBBB   C's canonical decomposition, one
                                   step: A then B (B 000000 for one character);
                                   Hangul syllables are algorithmic, not listed
  compositions        AAAAAABBBBBBCCCCCC   A followed by B composes to C, for
                                   every two-character canonical decomposition
                                   whose composite is not
                                   Full_Composition_Exclusion and has combining
                                   class 0 (HarfBuzz's gen-ucd-table.py rule)
  mirrors             XXXXXXYYYYYY X mirrors to Y (Bidi_Mirroring_Glyph)
  pictographic        SSSSSSEEEEEE Extended_Pictographic from S to E

Usage:
  python3 tools/ucd/generate.py           # download if needed, write the module
  python3 tools/ucd/generate.py --check   # fail if the committed module differs
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
PINS = HERE / "pins.json"
CACHE = HERE / ".cache"
OUTPUT = ROOT / "package" / "ShaperUnicodeData.roc"

# HarfBuzz's hb_unicode_general_category_t order.
CATEGORIES = [
    "Cc", "Cf", "Cn", "Co", "Cs", "Ll", "Lm", "Lo", "Lt", "Lu", "Mc", "Me", "Mn",
    "Nd", "Nl", "No", "Pc", "Pd", "Pe", "Pf", "Pi", "Po", "Ps", "Sc", "Sk", "Sm",
    "So", "Zl", "Zp", "Zs",
]
UNASSIGNED = CATEGORIES.index("Cn")
LIMIT = 0x110000
HANGUL_FIRST, HANGUL_LAST = 0xAC00, 0xAC00 + 11172 - 1


def fetch(name: str, pin: dict) -> bytes:
    path = CACHE / name
    if not path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(pin["url"]) as response:
            data = response.read()
        path.write_bytes(data)
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != pin["sha256"] or len(data) != pin["size"]:
        sys.exit(f"{name}: SHA-256 {digest}, {len(data)} bytes; pinned {pin['sha256']}, {pin['size']} bytes")
    return data


def lines(data: bytes):
    for raw in data.decode("utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            yield [field.strip() for field in line.split(";")]


def code_range(field: str) -> tuple[int, int]:
    first, _, last = field.partition("..")
    return int(first, 16), int(last or first, 16)


def read_unicode_data(data: bytes):
    category = [UNASSIGNED] * LIMIT
    ccc = [0] * LIMIT
    decomposition: dict[int, tuple[int, ...]] = {}
    pending_first = None
    for fields in lines(data):
        code = int(fields[0], 16)
        name, gc, cc, dm = fields[1], fields[2], int(fields[3]), fields[5]
        if name.endswith(", First>"):
            pending_first = code
            continue
        first = pending_first if name.endswith(", Last>") else code
        pending_first = None
        for c in range(first, code + 1):
            category[c] = CATEGORIES.index(gc)
            ccc[c] = cc
        if dm and not dm.startswith("<"):
            decomposition[code] = tuple(int(x, 16) for x in dm.split())
    return category, ccc, decomposition


def runs(values: list[int]) -> list[tuple[int, int]]:
    out = []
    previous = None
    for c, v in enumerate(values):
        if v != previous:
            out.append((c, v))
            previous = v
    return out


def merged_ranges(ranges: list[tuple[int, int]]) -> list[tuple[int, int]]:
    out: list[list[int]] = []
    for first, last in sorted(ranges):
        if out and first <= out[-1][1] + 1:
            out[-1][1] = max(out[-1][1], last)
        else:
            out.append([first, last])
    return [(a, b) for a, b in out]


def hex6(n: int) -> str:
    return f"{n:06X}"


def module(unicode_version: str, tables: dict[str, tuple[str, str, int]]) -> str:
    out = [
        f"## Unicode {unicode_version} character properties the shaper uses, generated by",
        "## `tools/ucd/generate.py` from the pinned Unicode Character Database",
        "## (`tools/ucd/pins.json`). Do not edit; run the generator.",
        "##",
        "## Internal data for `ShaperUnicode`. Each table is a string of",
        "## fixed-width records of upper-case hexadecimal digits sorted by their",
        "## first field (`ShaperUnicodeTests` checks the order); the generator's",
        "## docstring gives each record's layout.",
        "ShaperUnicodeData :: {}.{",
    ]
    for name, (doc, text, count) in tables.items():
        out.append("")
        out.append(f"\t## {doc} ({count} records)")
        out.append(f"\t{name} : List(U8)")
        out.append(f'\t{name} = "{text}".to_utf8()')
    out.append("}")
    return "\n".join(out) + "\n"


def build() -> str:
    pins = json.loads(PINS.read_text())
    files = {name: fetch(name, pin) for name, pin in pins["files"].items()}
    category, ccc, decomposition = read_unicode_data(files["UnicodeData.txt"])

    exclusions: set[int] = set()
    for fields in lines(files["DerivedNormalizationProps.txt"]):
        if len(fields) >= 2 and fields[1] == "Full_Composition_Exclusion":
            first, last = code_range(fields[0])
            exclusions.update(range(first, last + 1))

    mirrors = []
    for fields in lines(files["BidiMirroring.txt"]):
        mirrors.append((int(fields[0], 16), int(fields[1], 16)))
    mirrors.sort()

    pictographic = []
    for fields in lines(files["emoji-data.txt"]):
        if fields[1] == "Extended_Pictographic":
            pictographic.append(code_range(fields[0]))
    pictographic = merged_ranges(pictographic)

    gc_runs = runs(category)
    cc_runs = runs(ccc)
    decompositions = sorted(
        (c, v[0], v[1] if len(v) > 1 else 0)
        for c, v in decomposition.items()
        if not HANGUL_FIRST <= c <= HANGUL_LAST
    )
    for c, a, b in decompositions:
        assert len(decomposition[c]) <= 2, hex(c)
    compositions = sorted(
        (a, b, c) for c, a, b in decompositions if b != 0 and c not in exclusions and ccc[c] == 0
    )

    tables = {
        "general_categories": (
            "Runs of general category: start, then HarfBuzz's category number",
            "".join(hex6(s) + f"{v:02X}" for s, v in gc_runs),
            len(gc_runs),
        ),
        "combining_classes": (
            "Runs of canonical combining class: start, then the class",
            "".join(hex6(s) + f"{v:02X}" for s, v in cc_runs),
            len(cc_runs),
        ),
        "decompositions": (
            "Canonical decompositions, one step: the character, then its first and second parts (000000 for none)",
            "".join(hex6(c) + hex6(a) + hex6(b) for c, a, b in decompositions),
            len(decompositions),
        ),
        "compositions": (
            "Compositions HarfBuzz allows: the first and second characters, then the composite",
            "".join(hex6(a) + hex6(b) + hex6(c) for a, b, c in compositions),
            len(compositions),
        ),
        "mirrors": (
            "Bidi mirroring glyphs: the character, then its mirror",
            "".join(hex6(x) + hex6(y) for x, y in mirrors),
            len(mirrors),
        ),
        "pictographic": (
            "Extended_Pictographic ranges: first, then last",
            "".join(hex6(a) + hex6(b) for a, b in pictographic),
            len(pictographic),
        ),
    }
    return module(pins["unicode"], tables)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="fail if the committed module differs")
    args = parser.parse_args()
    text = build()
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text() != text:
            print(f"{OUTPUT.relative_to(ROOT)} is not what tools/ucd/generate.py writes", file=sys.stderr)
            return 1
        print(f"{OUTPUT.relative_to(ROOT)} is up to date")
        return 0
    OUTPUT.write_text(text)
    print(f"wrote {OUTPUT.relative_to(ROOT)} ({len(text)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
