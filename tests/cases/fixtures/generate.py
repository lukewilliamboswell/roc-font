#!/usr/bin/env python3
"""Generate the tiny font fixtures used by tests/cases/reading.cases.

Every fixture is derived from one crafted TrueType font (`tiny.ttf`: four
glyphs, a format 4 cmap for space, A and V, and a `kern` pair A V = -100),
either unchanged or with one deliberate defect. The output is
deterministic (fixed dates, sorted tables, computed checksums), so the
committed files can be checked against this script:

    python3 tests/cases/fixtures/generate.py           # rewrite the fixtures
    python3 tests/cases/fixtures/generate.py --check   # fail if any differs

Standard library only. The fixtures are original works made for this
repository and carry its licence.
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

UPEM = 1000
# glyph order: .notdef, space, A, V
ADVANCES = [500, 250, 600, 580]
CMAP = {0x20: 1, 0x41: 2, 0x56: 3}
KERN = {(2, 3): -100}


def checksum(data: bytes) -> int:
    data = data + b"\0" * (-len(data) % 4)
    return sum(struct.unpack(f">{len(data) // 4}I", data)) & 0xFFFFFFFF


def box_glyph(x0: int, y0: int, x1: int, y1: int) -> bytes:
    """A simple glyph with one rectangular contour of on-curve points."""
    points = [(x0, y0), (x0, y1), (x1, y1), (x1, y0)]
    header = struct.pack(">hhhhh", 1, x0, y0, x1, y1)
    body = struct.pack(">HH", 3, 0) + bytes([0x01] * 4)
    xs, ys, px, py = b"", b"", 0, 0
    for x, y in points:
        xs += struct.pack(">h", x - px)
        ys += struct.pack(">h", y - py)
        px, py = x, y
    glyph = header + body + xs + ys
    return glyph + b"\0" * (len(glyph) % 2)


def build_tables() -> dict[bytes, bytes]:
    glyphs = [box_glyph(50, 0, 450, 700), b"", box_glyph(0, 0, 600, 700), box_glyph(0, 0, 580, 700)]
    glyf, loca, at = b"", [], 0
    for g in glyphs:
        loca.append(at // 2)
        glyf += g
        at += len(g)
    loca.append(at // 2)

    head = struct.pack(
        ">IIIIHHqqhhhhHHhhh",
        0x00010000, 0x00010000, 0, 0x5F0F3CF5, 0x000B, UPEM,
        0, 0,  # created, modified: fixed for reproducibility
        0, 0, 600, 700,  # xMin yMin xMax yMax
        0, 8, 2, 0, 0,  # macStyle lowestRecPPEM fontDirectionHint indexToLocFormat glyphDataFormat
    )
    hhea = struct.pack(
        ">IhhhHhhhhhhhhhhhH",
        0x00010000, 800, -200, 0, max(ADVANCES), 0, 0, 600, 1, 0, 0, 0, 0, 0, 0, 0, len(ADVANCES),
    )
    maxp = struct.pack(">IHHHHHHHHHHHHHH", 0x00010000, len(glyphs), 4, 1, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0)
    hmtx = b"".join(struct.pack(">Hh", adv, 0) for adv in ADVANCES)
    os2 = struct.pack(
        ">HhHHHhhhhhhhhhhh10sIIII4sHHHhhhHHIIhhHHH",
        4, 500, 400, 5, 0, 650, 600, 0, 75, 650, 600, 0, 350, 50, 250, 0,
        bytes(10), 1, 0, 0, 0, b"NONE", 0x0040, 0x20, 0x56, 800, -200, 0, 1000, 200, 1, 0,
        500, 700, 0, 0x20, 0,
    )
    post = struct.pack(">IihhIIIII", 0x00030000, 0, -100, 50, 0, 0, 0, 0, 0)
    name = name_table({1: "RocFontTiny", 2: "Regular", 4: "RocFontTiny Regular", 6: "RocFontTiny-Regular"})
    cmap = cmap_table()
    kern = kern_table()
    return {
        b"OS/2": os2, b"cmap": cmap, b"glyf": glyf, b"head": head, b"hhea": hhea, b"hmtx": hmtx,
        b"kern": kern, b"loca": b"".join(struct.pack(">H", o) for o in loca), b"maxp": maxp,
        b"name": name, b"post": post,
    }


def name_table(names: dict[int, str]) -> bytes:
    records, strings = b"", b""
    for name_id in sorted(names):
        s = names[name_id].encode("utf-16-be")
        records += struct.pack(">HHHHHH", 3, 1, 0x409, name_id, len(s), len(strings))
        strings += s
    return struct.pack(">HHH", 0, len(names), 6 + len(records)) + records + strings


def cmap_table() -> bytes:
    codes = sorted(CMAP)
    seg_count = len(codes) + 1
    ends = codes + [0xFFFF]
    starts = codes + [0xFFFF]
    deltas = [(CMAP[c] - c) & 0xFFFF for c in codes] + [1]
    search = 2 ** (seg_count.bit_length() - 1) * 2
    sub = struct.pack(
        ">HHHHHHH", 4, 0, 0, seg_count * 2, search, (search // 2).bit_length() - 1, seg_count * 2 - search,
    )
    sub += struct.pack(f">{seg_count}H", *ends) + b"\0\0" + struct.pack(f">{seg_count}H", *starts)
    sub += struct.pack(f">{seg_count}H", *deltas) + struct.pack(f">{seg_count}H", *([0] * seg_count))
    sub = sub[:2] + struct.pack(">H", len(sub)) + sub[4:]
    return struct.pack(">HHHHI", 0, 1, 3, 1, 12) + sub


def kern_table(pairs: list[tuple[tuple[int, int], int]] | None = None) -> bytes:
    pairs = sorted(KERN.items()) if pairs is None else pairs
    n = len(pairs)
    search = 2 ** (n.bit_length() - 1) * 6
    body = struct.pack(">HHHH", n, search, (search // 6).bit_length() - 1, n * 6 - search)
    body += b"".join(struct.pack(">HHh", l, r, v) for (l, r), v in pairs)
    sub = struct.pack(">HHH", 0, 6 + len(body), 0x0001) + body
    return struct.pack(">HH", 0, 1) + sub


def assemble(tables: dict[bytes, bytes], *, version: int = 0x00010000, lengths: dict[bytes, int] | None = None) -> bytes:
    """An sfnt with `tables` in tag order; `lengths` overrides recorded lengths."""
    tags = sorted(tables)
    n = len(tags)
    search = 2 ** (n.bit_length() - 1) * 16
    header = struct.pack(">IHHHH", version, n, search, (search // 16).bit_length() - 1, n * 16 - search)
    offset = 12 + 16 * n
    directory, body = b"", b""
    for tag in tags:
        data = tables[tag]
        length = (lengths or {}).get(tag, len(data))
        directory += struct.pack(">4sIII", tag, checksum(data), offset + len(body), length)
        body += data + b"\0" * (-len(data) % 4)
    font = bytearray(header + directory + body)
    if b"head" in tables:
        head_at = 12 + 16 * n + sum(len(tables[t]) + (-len(tables[t]) % 4) for t in tags[: tags.index(b"head")])
        adjust = (0xB1B0AFBA - checksum(bytes(font))) & 0xFFFFFFFF
        font[head_at + 8 : head_at + 12] = struct.pack(">I", adjust)
    return bytes(font)


def fixtures() -> dict[str, bytes]:
    tables = build_tables()
    tiny = assemble(tables)

    def without(tag: bytes) -> dict[bytes, bytes]:
        return {t: d for t, d in tables.items() if t != tag}

    head = bytearray(tables[b"head"])
    head[18:20] = struct.pack(">H", 0)
    # A kern subtable claiming 1000 pairs where it holds one: the table lies
    # inside the file but its contents do not fit it.
    kern = bytearray(tables[b"kern"])
    kern[10:12] = struct.pack(">H", 1000)
    return {
        "tiny.ttf": tiny,
        "empty.ttf": b"",
        "header-only.ttf": tiny[:12],
        "bad-magic.ttf": b"ABCD" + tiny[4:],
        "truncated-half.ttf": tiny[: len(tiny) // 2],
        "hmtx-past-end.ttf": assemble(tables, lengths={b"hmtx": 0xFFFF}),
        "kern-past-end.ttf": assemble(tables, lengths={b"kern": 0xFFFF}),
        "kern-bad-pairs.ttf": assemble({**tables, b"kern": bytes(kern)}),
        # Pairs out of order: OTS drops the table, fontTools reads it.
        "kern-unsorted.ttf": assemble({**tables, b"kern": kern_table([((2, 3), -100), ((2, 1), -20)])}),
        "no-cmap.ttf": assemble(without(b"cmap")),
        "no-kern.ttf": assemble(without(b"kern")),
        "upem-zero.ttf": assemble({**tables, b"head": bytes(head)}),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="fail if a committed fixture differs")
    args = parser.parse_args()
    differ = []
    for name, data in sorted(fixtures().items()):
        path = HERE / name
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                differ.append(name)
        else:
            path.write_bytes(data)
    if differ:
        print("fixtures differ from generate.py: " + ", ".join(differ), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
