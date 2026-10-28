#!/usr/bin/env python3
"""Oracle extractor for roc-font conformance records.

Run inside the pinned virtual environment, isolated from the user's site
packages (scripts/record_oracle.py does this for you):

    tools/oracle/.venv/bin/python -I tools/oracle/extract.py versions
    tools/oracle/.venv/bin/python -I tools/oracle/extract.py run < requests.jsonl

`versions` prints one JSON object: the extractor version of each case kind
and the versions of the tools each kind uses. `run` reads one JSON request
per line,

    {"kind": "shape"|"read"|"coords"|"advances"|"metrics"|"extents",
     "font": <path>, "options": [...], "unicodes": [...],
     "glyphs": [...] or "all" (advances, extents),
     "location": null or {"fields": {...}, "axes": [[tag, value], ...] or null,
                          "default": bool, "problem": <str>}}

and prints one JSON response per line, in order:
`{"status": "ok"|"unsupported"|"error", "result": <str or null>,
"backend": <str>, "detail": <object>}`. `location` is scripts/_common.py's
resolve_location: every axis of a variable font at the value the case
selects (values are decimal strings, converted to the nearest
single-precision value as roc-font converts a `Dec`); a named instance is
set with `hb_font_set_var_named_instance`.

Shaping cases are answered by HarfBuzz through uharfbuzz, using HarfBuzz's
own OpenType font functions, and serialised as hb-shape does with
`--no-glyph-names`. The font-fact kinds are answered by HarfBuzz too:
normalised coordinates (`coords`), horizontal advances (`advances`),
`hb_ot_metrics_get_position_with_fallback` (`metrics`) and glyph extents
(`extents`). Reading cases are answered by OTS (`ots-sanitize`) when it is
installed, otherwise by fontTools. `--face-index=N` selects a face of a
collection; a face past the font is `read:reject`. Every output is a pure
function of the request and the tool versions, so re-recording reproduces
it.
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from decimal import Decimal
from fractions import Fraction
from importlib.metadata import version as dist_version
from pathlib import Path

# Per case kind; bump a kind's version whenever a change here can change one
# of its records: the result notation, the option handling, READ_TABLES, or
# the choice of backend. shape 2: `--single-par` (a no-op), `--face-index`,
# locations.
EXTRACTOR_VERSIONS = {"shape": 2, "read": 1, "coords": 1, "advances": 1, "metrics": 1, "extents": 1, "metadata": 1}
HARFBUZZ_KINDS = ("shape", "coords", "advances", "metrics", "extents")

HERE = Path(__file__).resolve().parent

# Tables roc-font reads. A reading result names dropped tables only from this
# set: a table roc-font never reads cannot be dropped by it.
READ_TABLES = ("GPOS", "GSUB", "OS/2", "cmap", "glyf", "head", "hhea", "hmtx", "kern", "loca", "maxp")
# Tables whose failure rejects the font in the fontTools fallback (architecture
# §4.4); any other failing table is reported as dropped.
REQUIRED_TABLES = ("head", "hhea", "maxp", "hmtx", "cmap", "loca", "glyf", "CFF ", "CFF2")


def ots_binary() -> str | None:
    explicit = os.environ.get("OTS_SANITIZE")
    if explicit:
        return explicit if Path(explicit).is_file() else None
    for candidate in sorted((HERE / ".cache").glob("ots-*/ots-sanitize")):
        return str(candidate)
    return shutil.which("ots-sanitize")


def ots_version(binary: str) -> str:
    completed = subprocess.run([binary, "--version"], capture_output=True, text=True, check=False)
    text = (completed.stdout or completed.stderr).strip()
    return text.split()[-1] if text else "unknown"


def versions() -> dict:
    import uharfbuzz as hb

    shape_tools = {"harfbuzz": hb.version_string(), "uharfbuzz": dist_version("uharfbuzz")}
    ots = ots_binary()
    if ots:
        read_tools = {"ots-sanitize": ots_version(ots)}
    else:
        read_tools = {"fonttools": dist_version("fonttools")}
    tools = {kind: shape_tools for kind in HARFBUZZ_KINDS}
    tools["metadata"] = {"fonttools": dist_version("fonttools")}
    tools["read"] = read_tools
    return {
        "extractor": EXTRACTOR_VERSIONS,
        "installed": {
            "fonttools": dist_version("fonttools"),
            "freetype-py": dist_version("freetype-py"),
            "uharfbuzz": dist_version("uharfbuzz"),
        },
        "tools": tools,
    }


# ------------------------------------------------------------------ shaping


class Unsupported(Exception):
    pass


def parse_features(text: str) -> dict:
    """hb-shape feature syntax: `kern`, `-liga`, `+dlig`, `aalt=2`,
    `kern[3:5]=0`, comma-separated."""
    features: dict = {}
    for item in filter(None, (part.strip() for part in text.split(","))):
        value = 1
        if item[0] in "+-":
            value = 0 if item[0] == "-" else 1
            item = item[1:]
        if "=" in item:
            item, raw = item.split("=", 1)
            value = int(raw)
        start, end = 0, None
        if "[" in item:
            item, span = item.split("[", 1)
            span = span.rstrip("]")
            lo, _, hi = span.partition(":")
            start = int(lo) if lo else 0
            end = int(hi) if hi else (start + 1 if ":" not in span else None)
        tag = item.strip("'\"")
        if not 1 <= len(tag) <= 4:
            raise Unsupported(f"--features={text}")
        if start == 0 and end is None:
            features[tag] = value
        else:
            features.setdefault(tag, [])
            if not isinstance(features[tag], list):
                raise Unsupported(f"--features={text}")
            features[tag].append((start, end if end is not None else 0xFFFFFFFF, value))
    return features


class Rejected(Exception):
    """The request names a face the file does not have."""


def dec_to_f32(text: str) -> float:
    """The single-precision value nearest a decimal (ties to even), as
    roc-font converts a `Dec` axis value and as HarfBuzz then receives it
    as a `float`. Going through binary64 first could round twice."""
    q = Fraction(Decimal(text))
    if q == 0:
        return 0.0
    sign = -1 if q < 0 else 1
    a = abs(q)
    exponent = a.numerator.bit_length() - a.denominator.bit_length()
    if Fraction(2) ** exponent > a:
        exponent -= 1
    shift = 23 - max(exponent, -126)  # 24 significant bits, subnormals below 2^-126
    scaled = a * (Fraction(2) ** shift)
    whole = scaled.numerator // scaled.denominator
    rest = scaled - whole
    if rest > Fraction(1, 2) or (rest == Fraction(1, 2) and whole % 2 == 1):
        whole += 1
    return sign * float(Fraction(whole) / (Fraction(2) ** shift))


def face_option(options: list[str]) -> int:
    for option in options:
        if option.startswith("--face-index="):
            value = option.split("=", 1)[1]
            if not value.isdigit():
                raise Unsupported(option)
            return int(value)
    return 0


def face_count(data: bytes) -> int | None:
    """Faces in an sfnt (1) or `ttcf` collection; None for anything else
    (HarfBuzz decides what it makes of those)."""
    if data[:4] == b"ttcf":
        return struct.unpack(">I", data[8:12])[0] if len(data) >= 12 else 0
    if data[:4] in (b"\x00\x01\x00\x00", b"true", b"OTTO"):
        return 1
    return None


def open_font(font_path: str, face_index: int, location: dict | None):
    """A HarfBuzz font for one face at the request's location. A face past
    the font raises Rejected: roc-font refuses to read it (`NoSuchFace`)
    where HarfBuzz would shape with an empty face."""
    import uharfbuzz as hb

    data = Path(font_path).read_bytes()
    count = face_count(data)
    if count is not None and face_index >= count:
        raise Rejected(f"face {face_index} of {count}")
    face = hb.Face(data, face_index)
    font = hb.Font(face)
    if location is not None:
        if location.get("axes") is None:
            raise ValueError(location.get("problem", "no location"))
        if "instance" in location["fields"]:
            font.var_named_instance = location["fields"]["instance"]
        elif location["axes"]:
            font.set_variations({tag: dec_to_f32(value) for tag, value in location["axes"]})
    return face, font


def steady(location: dict | None, compute):
    """compute() once, or at a non-default location twice, returning the
    second answer. HarfBuzz quantises a region's scalar in a cache on the
    font from its second evaluation on (docs/variable-fonts.adoc §3.3);
    roc-font models that steady state."""
    if location is not None and location.get("axes") and not location.get("default"):
        compute()
    return compute()


def shape(font_path: str, options: list[str], unicodes: list[int], location: dict | None = None) -> tuple[str, dict]:
    import uharfbuzz as hb

    flags = hb.BufferSerializeFlags.NO_GLYPH_NAMES
    utf8 = False
    direction = script = language = None
    features: dict = {}
    variations: dict = {}
    cluster_level = None
    buffer_flags = hb.BufferFlags.DEFAULT
    font_size = None
    text_range = None
    for option in options:
        name, _, value = option.partition("=")
        if option in ("--no-glyph-names", "--font-funcs=ot", "--font-funcs=ft", "--single-par"):
            # --single-par only stops hb-shape splitting its input at line
            # breaks; one buffer is always one paragraph here.
            pass
        elif name == "--face-index":
            face_option([option])
        elif option == "--no-positions":
            flags |= hb.BufferSerializeFlags.NO_POSITIONS
        elif option == "--no-advances":
            flags |= hb.BufferSerializeFlags.NO_ADVANCES
        elif option == "--no-clusters":
            flags |= hb.BufferSerializeFlags.NO_CLUSTERS
        elif option == "--ned":
            flags |= hb.BufferSerializeFlags.NO_CLUSTERS | hb.BufferSerializeFlags.NO_ADVANCES
        elif option == "--show-flags":
            flags |= hb.BufferSerializeFlags.GLYPH_FLAGS
        elif option == "--show-extents":
            flags |= hb.BufferSerializeFlags.GLYPH_EXTENTS
        elif option == "--utf8-clusters":
            utf8 = True
        elif option == "--remove-default-ignorables":
            buffer_flags |= hb.BufferFlags.REMOVE_DEFAULT_IGNORABLES
        elif name == "--direction" and value:
            direction = {"l": "ltr", "r": "rtl", "t": "ttb", "b": "btt"}.get(value[0].lower())
            if direction is None:
                raise Unsupported(option)
        elif name == "--script" and value:
            script = value
        elif name == "--language" and value:
            language = value
        elif name == "--features":
            features.update(parse_features(value))
        elif name == "--variations":
            for item in filter(None, value.split(",")):
                tag, _, number = item.partition("=")
                variations[tag.strip()] = float(number)
        elif name == "--cluster-level" and value in ("0", "1", "2", "3"):
            cluster_level = int(value)
        elif name == "--font-size" and value:
            font_size = value
        elif name == "--text-range":
            pieces = value.split(":")
            if len(pieces) != 2 or any(not n.isascii() or not n.isdigit() or int(n) > 0xFFFFFFFFFFFFFFFF for n in pieces):
                raise Unsupported(option)
            text_range = tuple(map(int, pieces))
            utf8 = True
        else:
            raise Unsupported(option)

    face, font = open_font(font_path, face_option(options), location)
    if font_size is not None and font_size != "upem":
        parts = font_size.replace(",", " ").split()
        try:
            sizes = [int(float(p)) for p in parts]
        except ValueError:
            raise Unsupported(f"--font-size={font_size}")
        font.scale = (sizes[0], sizes[-1])
    # With a location, --variations items are already part of it.
    if variations and location is None:
        font.set_variations(variations)

    def run():
        buf = hb.Buffer()
        if utf8:
            encoded = [chr(u).encode("utf-8") for u in unicodes]
            paragraph = b"".join(encoded)
            if text_range is None:
                buf.add_utf8(paragraph)
            else:
                start, end = text_range
                offsets, at = [], 0
                for scalar in encoded:
                    offsets.append(at)
                    at += len(scalar)
                selected = [i for i, offset in enumerate(offsets) if start <= offset < end]
                actual_start = offsets[selected[0]] if selected else len(paragraph)
                actual_end = offsets[selected[-1]] + len(encoded[selected[-1]]) if selected else actual_start
                buf.add_utf8(paragraph, actual_start, actual_end - actual_start)
        else:
            buf.add_codepoints(list(unicodes))
        if direction:
            buf.direction = direction
        if script:
            buf.script = script
        if language:
            buf.language = language
        buf.guess_segment_properties()
        if cluster_level is not None:
            buf.cluster_level = hb.BufferClusterLevel(cluster_level)
        buf.flags = buffer_flags
        hb.shape(font, buf, features)
        return buf

    buf = steady(location, run)
    text = buf.serialize(font, format=hb.BufferSerializeFormat.TEXT, flags=flags)
    # hb-shape prints nothing for an empty run; the notation here is `[]`.
    result = text if text else "[]"
    return result, {"direction": str(buf.direction), "script": str(buf.script)}


# --------------------------------------------------------------- font facts

# metrics: result names (roc-font's Metrics fields) and HarfBuzz's tags.
METRICS = (
    ("ascent", "HORIZONTAL_ASCENDER"),
    ("descent", "HORIZONTAL_DESCENDER"),
    ("line_gap", "HORIZONTAL_LINE_GAP"),
    ("cap_height", "CAP_HEIGHT"),
    ("x_height", "X_HEIGHT"),
    ("underline_position", "UNDERLINE_OFFSET"),
    ("underline_thickness", "UNDERLINE_SIZE"),
    ("strikeout_position", "STRIKEOUT_OFFSET"),
    ("strikeout_thickness", "STRIKEOUT_SIZE"),
)


def facts(kind: str, font_path: str, options: list[str], glyphs, location: dict | None) -> tuple[str, dict]:
    """The font-fact kinds, in font units at the request's location:

    coords    `coords:<tag>=<F2Dot14>,...` in fvar order (`coords:` for a static font)
    advances  `advances:<a>,<b>,...` per requested glyph
    metrics   `metrics:ascent=..,descent=..,...` (hb_ot_metrics with fallback)
    extents   `extents:<gid>=<x_min>,<y_min>,<x_max>,<y_max>|<gid>=empty|...`
    """
    import uharfbuzz as hb

    for option in options:
        if option not in ("--" + kind,) and not option.startswith("--face-index="):
            raise Unsupported(option)
    face, font = open_font(font_path, face_option(options), location)
    if glyphs == "all":
        glyphs = list(range(face.glyph_count))
    if kind == "coords":
        tags = [axis.tag for axis in face.axis_infos]
        coords = font.get_var_coords_normalized() or [0.0] * len(tags)
        # HarfBuzz keeps F2Dot14 integers; uharfbuzz divides by 2^14 exactly.
        result = "coords:" + ",".join(f"{tag}={int(c * 16384)}" for tag, c in zip(tags, coords))
        return result, {"design": font.get_var_coords_design() or []}
    if kind == "advances":
        values = steady(location, lambda: [font.get_glyph_h_advance(g) for g in glyphs])
        return "advances:" + ",".join(str(v) for v in values), {"glyph_count": face.glyph_count}
    if kind == "metrics":
        def measure():
            return [font.get_metric_position_with_fallback(getattr(hb.OTMetricsTag, tag)) for _, tag in METRICS]
        values = steady(location, measure)
        raw = {name: font.get_metric_position(getattr(hb.OTMetricsTag, tag)) for name, tag in METRICS}
        result = "metrics:" + ",".join(f"{name}={value}" for (name, _), value in zip(METRICS, values))
        return result, {"without_fallback": raw}
    if kind == "extents":
        def measure():
            return [font.get_glyph_extents(g) for g in glyphs]
        items = []
        for g, e in zip(glyphs, steady(location, measure)):
            if e is None or (e.width == 0 and e.height == 0):
                items.append(f"{g}=empty")
            else:
                x0, x1 = e.x_bearing, e.x_bearing + e.width
                y1, y0 = e.y_bearing, e.y_bearing + e.height
                items.append(f"{g}={min(x0, x1)},{min(y0, y1)},{max(x0, x1)},{max(y0, y1)}")
        return "extents:" + "|".join(items), {"glyph_count": face.glyph_count}
    raise Unsupported(f"kind={kind}")


def metadata(font_path: str, face: int) -> str:
    """Original sfnt facts, independently decoded by fontTools."""
    from fontTools.ttLib import TTFont

    with TTFont(font_path, fontNumber=face, lazy=True) as font:
        def name(name_id):
            if "name" not in font:
                return "-"
            table = font["name"]
            record = table.getName(name_id, 3, 1, 0x409)
            value = record.toUnicode() if record else table.getDebugName(name_id)
            return ",".join(map(str, value.encode("utf-8"))) if value is not None else "-"

        head, hhea = font["head"], font["hhea"]
        bounds = ",".join(str(getattr(head, key)) for key in ("xMin", "yMin", "xMax", "yMax"))
        header = ",".join(str(getattr(hhea, key)) for key in ("ascent", "descent", "lineGap"))
        flags = str(font["OS/2"].fsType) if "OS/2" in font else "-"
        metrics = font["hmtx"].metrics
        bearings = ",".join(str(metrics[glyph][1]) for glyph in font.getGlyphOrder())
        tables = []
        # fontTools reorders its reader dictionary by payload offset.
        # Preserve the original directory order for this public contract.
        source = Path(font_path).read_bytes()
        directory = struct.unpack_from(">I", source, 12 + 4 * face)[0] if source[:4] == b"ttcf" else 0
        count = struct.unpack_from(">H", source, directory + 4)[0]
        tags = [source[directory + 12 + 16 * i:directory + 16 + 16 * i].decode("latin-1") for i in range(count)]
        for tag in tags:
            entry = font.reader.tables[tag]
            checksum = 14695981039346656037
            for byte in font.reader[tag]:
                checksum = ((checksum ^ byte) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
            tables.append(f"{int.from_bytes(tag.encode('latin-1'), 'big')},{entry.offset},{entry.length},{checksum}")
        return "metadata:" + ";".join((name(1), name(4), name(6), flags, bounds, header, bearings, "|".join(tables)))


# ------------------------------------------------------------------ reading


def sfnt_tags(data: bytes, start: int = 0) -> list[str] | None:
    """Table tags of the sfnt directory at `start`, or None."""
    if len(data) < start + 12:
        return None
    count = struct.unpack(">H", data[start + 4 : start + 6])[0]
    if len(data) < start + 12 + 16 * count:
        return None
    return [data[start + 12 + 16 * i : start + 16 + 16 * i].decode("latin-1") for i in range(count)]


def face_tags(data: bytes, face: int) -> list[str] | None:
    """Table tags of one face (of a collection, or the font itself)."""
    if data[:4] != b"ttcf":
        return sfnt_tags(data)
    if len(data) < 16 + 4 * face:
        return None
    return sfnt_tags(data, struct.unpack(">I", data[12 + 4 * face : 16 + 4 * face])[0])


def read_with_ots(binary: str, font_path: str, face: int = 0) -> tuple[str, dict]:
    data = Path(font_path).read_bytes()
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "sanitized.ttf"
        # For a collection OTS writes the chosen face as a single font.
        command = [binary, font_path, str(out)] + ([str(face)] if data[:4] == b"ttcf" else [])
        completed = subprocess.run(command, capture_output=True, text=True, check=False)
        messages = [
            line.strip()
            for line in (completed.stdout + completed.stderr).splitlines()
            if line.startswith(("ERROR: ", "WARNING: "))
        ]
        if completed.returncode != 0:
            return "read:reject", {"messages": messages}
        before = set(face_tags(data, face) or [])
        after = set(sfnt_tags(out.read_bytes()) or []) if out.exists() else set()
    dropped_all = sorted(before - after)
    dropped = [t for t in dropped_all if t in READ_TABLES]
    result = "read:accept" if not dropped else "read:drop=" + ",".join(dropped)
    return result, {"dropped_all": dropped_all, "messages": messages}


def read_with_fonttools(font_path: str, face: int = 0) -> tuple[str, dict]:
    import io

    from fontTools.ttLib import TTFont

    logging.disable(logging.CRITICAL)
    data = Path(font_path).read_bytes()
    try:
        font = TTFont(io.BytesIO(data), lazy=True, fontNumber=face)
        tags = sorted(t for t in font.reader.keys())
    except Exception as error:  # noqa: BLE001 - any failure here rejects
        return "read:reject", {"error": type(error).__name__}
    failed = {}
    for tag in tags:
        try:
            table = font[tag]
            if hasattr(table, "ensureDecompiled"):
                table.ensureDecompiled()
        except Exception as error:  # noqa: BLE001
            failed[tag] = type(error).__name__
    missing = [t for t in ("head", "hhea", "maxp", "hmtx", "cmap") if t not in tags]
    if missing or any(t in REQUIRED_TABLES for t in failed):
        return "read:reject", {"failed": failed, "missing": missing}
    dropped = sorted(t for t in failed if t in READ_TABLES)
    result = "read:accept" if not dropped else "read:drop=" + ",".join(dropped)
    return result, {"failed": failed}


# --------------------------------------------------------------------- main


def answer(request: dict, ots: str | None) -> dict:
    kind = request["kind"]
    location = request.get("location")
    try:
        if kind == "metadata":
            result = metadata(request["font"], face_option(request["options"]))
            return {"status": "ok", "result": result, "backend": "fontTools stored font facts", "detail": {}}
        if kind == "shape":
            result, detail = shape(request["font"], request["options"], request["unicodes"], location)
            return {"status": "ok", "result": result, "backend": "uharfbuzz (HarfBuzz ot font functions)", "detail": detail}
        if kind in HARFBUZZ_KINDS:
            result, detail = facts(kind, request["font"], request["options"], request.get("glyphs"), location)
            return {"status": "ok", "result": result, "backend": "uharfbuzz (HarfBuzz ot font functions)", "detail": detail}
        if kind == "read":
            face = 0
            for option in request["options"]:
                if option.startswith("--face-index="):
                    face = face_option([option])
                elif option != "--read-outcome":
                    raise Unsupported(option)
            count = face_count(Path(request["font"]).read_bytes())
            if count is not None and face >= count:
                raise Rejected(f"face {face} of {count}")
            if ots:
                result, detail = read_with_ots(ots, request["font"], face)
                return {"status": "ok", "result": result, "backend": "ots-sanitize", "detail": detail}
            result, detail = read_with_fonttools(request["font"], face)
            return {"status": "ok", "result": result, "backend": "fontTools (decompile every table)", "detail": detail}
        return {"status": "error", "result": None, "backend": "", "detail": {"error": f"unknown kind {kind}"}}
    except Rejected as error:
        # roc-font's NoSuchFace; the backends would read another face or none.
        return {"status": "ok", "result": "read:reject", "backend": "extractor (face index past the font)", "detail": {"face": str(error)}}
    except Unsupported as error:
        return {"status": "unsupported", "result": None, "backend": "", "detail": {"option": str(error)}}
    except Exception as error:  # noqa: BLE001 - one bad case must not stop a batch
        detail = {"error": type(error).__name__}
        if isinstance(error, ValueError) and location is not None and location.get("problem"):
            detail["location"] = location["problem"]
        return {"status": "error", "result": None, "backend": "", "detail": detail}


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "versions":
        print(json.dumps(versions(), sort_keys=True))
        return 0
    if command == "run":
        ots = ots_binary()
        for line in sys.stdin:
            if line.strip():
                response = answer(json.loads(line), ots)
                sys.stdout.write(json.dumps(response, sort_keys=True) + "\n")
        sys.stdout.flush()
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
