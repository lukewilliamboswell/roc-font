#!/usr/bin/env python3
"""Oracle extractor for roc-font conformance records.

Run inside the pinned virtual environment, isolated from the user's site
packages (scripts/record_oracle.py does this for you):

    tools/oracle/.venv/bin/python -I tools/oracle/extract.py versions
    tools/oracle/.venv/bin/python -I tools/oracle/extract.py run < requests.jsonl

`versions` prints one JSON object: the extractor version and the versions of
the tools each case kind uses. `run` reads one JSON request per line,
`{"kind": "shape"|"read", "font": <path>, "options": [...], "unicodes": [...]}`,
and prints one JSON response per line, in order:
`{"status": "ok"|"unsupported"|"error", "result": <str or null>,
"backend": <str>, "detail": <object>}`.

Shaping cases are answered by HarfBuzz through uharfbuzz, using HarfBuzz's
own OpenType font functions, and serialised as hb-shape does with
`--no-glyph-names`. Reading cases are answered by OTS (`ots-sanitize`) when
it is installed, otherwise by fontTools. Every output is a pure function of
the request and the tool versions, so re-recording reproduces it.
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
from importlib.metadata import version as dist_version
from pathlib import Path

# Bump whenever a change here can change a record: the result notation, the
# option handling, READ_TABLES, or the choice of backend.
EXTRACTOR_VERSION = 1

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
    return {
        "extractor": EXTRACTOR_VERSION,
        "installed": {
            "fonttools": dist_version("fonttools"),
            "freetype-py": dist_version("freetype-py"),
            "uharfbuzz": dist_version("uharfbuzz"),
        },
        "tools": {"read": read_tools, "shape": shape_tools},
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


def shape(font_path: str, options: list[str], unicodes: list[int]) -> tuple[str, dict]:
    import uharfbuzz as hb

    flags = hb.BufferSerializeFlags.NO_GLYPH_NAMES
    utf8 = False
    direction = script = language = None
    features: dict = {}
    variations: dict = {}
    cluster_level = None
    buffer_flags = hb.BufferFlags.DEFAULT
    font_size = None
    for option in options:
        name, _, value = option.partition("=")
        if option in ("--no-glyph-names", "--font-funcs=ot", "--font-funcs=ft"):
            pass
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
        else:
            raise Unsupported(option)

    data = Path(font_path).read_bytes()
    face = hb.Face(data)
    font = hb.Font(face)
    if font_size is not None and font_size != "upem":
        parts = font_size.replace(",", " ").split()
        try:
            sizes = [int(float(p)) for p in parts]
        except ValueError:
            raise Unsupported(f"--font-size={font_size}")
        font.scale = (sizes[0], sizes[-1])
    if variations:
        font.set_variations(variations)

    buf = hb.Buffer()
    if utf8:
        buf.add_utf8("".join(chr(u) for u in unicodes).encode("utf-8"))
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
    text = buf.serialize(font, format=hb.BufferSerializeFormat.TEXT, flags=flags)
    # hb-shape prints nothing for an empty run; the notation here is `[]`.
    result = text if text else "[]"
    return result, {"direction": str(buf.direction), "script": str(buf.script)}


# ------------------------------------------------------------------ reading


def sfnt_tags(data: bytes) -> list[str] | None:
    if len(data) < 12:
        return None
    count = struct.unpack(">H", data[4:6])[0]
    if len(data) < 12 + 16 * count:
        return None
    return [data[12 + 16 * i : 16 + 16 * i].decode("latin-1") for i in range(count)]


def read_with_ots(binary: str, font_path: str) -> tuple[str, dict]:
    data = Path(font_path).read_bytes()
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "sanitized.ttf"
        completed = subprocess.run([binary, font_path, str(out)], capture_output=True, text=True, check=False)
        messages = [
            line.strip()
            for line in (completed.stdout + completed.stderr).splitlines()
            if line.startswith(("ERROR: ", "WARNING: "))
        ]
        if completed.returncode != 0:
            return "read:reject", {"messages": messages}
        before = set(sfnt_tags(data) or [])
        after = set(sfnt_tags(out.read_bytes()) or []) if out.exists() else set()
    dropped_all = sorted(before - after)
    dropped = [t for t in dropped_all if t in READ_TABLES]
    result = "read:accept" if not dropped else "read:drop=" + ",".join(dropped)
    return result, {"dropped_all": dropped_all, "messages": messages}


def read_with_fonttools(font_path: str) -> tuple[str, dict]:
    import io

    from fontTools.ttLib import TTFont

    logging.disable(logging.CRITICAL)
    data = Path(font_path).read_bytes()
    try:
        font = TTFont(io.BytesIO(data), lazy=True)
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
    try:
        if kind == "shape":
            result, detail = shape(request["font"], request["options"], request["unicodes"])
            return {"status": "ok", "result": result, "backend": "uharfbuzz (HarfBuzz ot font functions)", "detail": detail}
        if kind == "read":
            if ots:
                result, detail = read_with_ots(ots, request["font"])
                return {"status": "ok", "result": result, "backend": "ots-sanitize", "detail": detail}
            result, detail = read_with_fonttools(request["font"])
            return {"status": "ok", "result": result, "backend": "fontTools (decompile every table)", "detail": detail}
        return {"status": "error", "result": None, "backend": "", "detail": {"error": f"unknown kind {kind}"}}
    except Unsupported as error:
        return {"status": "unsupported", "result": None, "backend": "", "detail": {"option": str(error)}}
    except Exception as error:  # noqa: BLE001 - one bad case must not stop a batch
        return {"status": "error", "result": None, "backend": "", "detail": {"error": type(error).__name__}}


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
