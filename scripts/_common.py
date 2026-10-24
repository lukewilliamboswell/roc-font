"""Helpers shared by the conformance scripts (conformance.py, record_oracle.py,
fetch_corpus.py). Standard library only.

The case format, case ids, record keys and record files are defined here once
so the review and the recorder cannot disagree about them. See
docs/conformance.adoc for the formats.
"""

from __future__ import annotations

import hashlib
import json
import struct
from decimal import Decimal, InvalidOperation
from fractions import Fraction
import os
import re
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Sequence

ROOT = Path(__file__).resolve().parents[1]
TMP_ROOT = Path(os.environ.get("ROC_FONT_TMPDIR", ROOT / ".roc-font-tmp")).resolve()
CASES_DIR = ROOT / "tests" / "cases"
RECORDS_DIR = ROOT / "tests" / "oracle" / "records"
CORPUS_DIR = ROOT / "tests" / "corpus"
KNOWN_FAILURES = ROOT / "tests" / "known-failures.json"
CURATION_LIST = ROOT / "tests" / "cases" / "curated.jsonc"
ORACLE_DIR = ROOT / "tools" / "oracle"
DRIVER_DIR = ROOT / "tools" / "driver"

# The option that turns a case into a reading case (a roc-font extension of
# the hb-shape options; HarfBuzz's runner would reject it).
READ_OPTION = "--read-outcome"
# The option that selects a Chrome width case (part of its record key).
WIDTH_OPTION = "--width"
# The options that select the font-fact kinds (part of their record keys).
FACT_OPTIONS = {"coords": "--coords", "advances": "--advances", "metrics": "--metrics", "extents": "--extents"}


# ----------------------------------------------------------------- commands


def resolve_command(command: str) -> str:
    """Resolve path-like commands while leaving PATH lookups unchanged."""
    if "/" in command or "\\" in command:
        return str(Path(command).expanduser().resolve())
    return command


def roc_command() -> str:
    return resolve_command(os.environ.get("ROC", "roc"))


def roc_version(roc: str) -> str:
    try:
        completed = subprocess.run([roc, "version"], capture_output=True, text=True, check=False)
    except OSError:
        return "unavailable"
    return completed.stdout.strip() or completed.stderr.strip() or "unknown"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json(value: object) -> str:
    """The one JSON spelling used for keys and records: sorted keys, no
    spaces, ASCII only, so output is byte-for-byte reproducible."""
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


# -------------------------------------------------------------------- JSONC


def strip_jsonc(text: str) -> str:
    """JSON text from JSONC: `//` and `/* */` comments outside strings become
    spaces (newlines are kept, so JSON error positions still match the
    file), and a comma directly before `]` or `}` is dropped."""
    out: list[str] = []
    i, n = 0, len(text)
    in_string = False
    while i < n:
        c = text[i]
        if in_string:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_string = False
            i += 1
        elif c == '"':
            in_string = True
            out.append(c)
            i += 1
        elif text.startswith("//", i):
            end = text.find("\n", i)
            end = n if end < 0 else end
            out.append(" " * (end - i))
            i = end
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            if end < 0:
                raise ValueError(f"unterminated /* comment at offset {i}")
            out.append("".join(ch if ch == "\n" else " " for ch in text[i : end + 2]))
            i = end + 2
        else:
            out.append(c)
            i += 1
    if in_string:
        raise ValueError("unterminated string")
    stripped = "".join(out)
    # Trailing commas: a comma followed only by whitespace and a closer.
    result: list[str] = []
    in_string = False
    i, n = 0, len(stripped)
    while i < n:
        c = stripped[i]
        if in_string:
            result.append(c)
            if c == "\\" and i + 1 < n:
                result.append(stripped[i + 1])
                i += 2
                continue
            if c == '"':
                in_string = False
        elif c == '"':
            in_string = True
            result.append(c)
        elif c == ",":
            j = i + 1
            while j < n and stripped[j] in " \t\r\n":
                j += 1
            result.append(" " if j < n and stripped[j] in "]}" else c)
        else:
            result.append(c)
        i += 1
    return "".join(result)


def load_jsonc(path: Path) -> object:
    text = path.read_text(encoding="utf-8")
    try:
        # Decimals stay exact (axis values such as 87.5 are part of keys).
        return json.loads(strip_jsonc(text), parse_float=Decimal)
    except (ValueError, json.JSONDecodeError) as error:
        raise ValueError(f"{rel(path)}: {error}") from None


# -------------------------------------------------------------------- cases

# Case kinds this repository knows. `shape`, `read` and the font-fact kinds
# (`coords`, `advances`, `metrics`, `extents`) are answered by
# tools/oracle/extract.py; `width` by the Chrome oracle. Other lower-case
# kinds parse (the format is extensible) and are reported as unsupported
# until an oracle and the driver handle them.
KNOWN_KINDS = ("shape", "read", "width", "coords", "advances", "metrics", "extents")
# Kinds that take text (`text`/`unicodes`), and kinds that take glyph ids.
TEXT_KINDS = ("shape", "width")
GLYPH_KINDS = ("advances", "extents")

# Structured shaping options, in the order they become hb-shape options.
OPTION_FIELDS = (
    "direction",
    "script",
    "language",
    "features",
    "variations",
    "font_size",
    "cluster_level",
    "output",
    "utf8_clusters",
    "remove_default_ignorables",
    "hb_options",
)
OUTPUT_FLAGS = ("ned", "no-clusters", "no-positions", "no-advances")
DIRECTIONS = {"l": "ltr", "r": "rtl", "t": "ttb", "b": "btt"}
CASE_FIELDS = {
    "id", "kind", "font", "font_sha256", "unicodes", "text", "options", "expected",
    "reason", "comment", "source", "milestone", "needs", "area",
    "face", "variations", "variation", "instance", "glyphs",
}
LOCATION_FIELDS = ("variations", "variation", "instance")


@dataclass(frozen=True)
class Case:
    """One case of a case file, normalised.

    `options` are the equivalent hb-shape command-line options in a fixed
    order (the oracle's input and part of the record key); `settings` holds
    the structured options they were made from; `unicodes` is the text as
    `U+XXXX,...`. `expected` is the written expectation, with "oracle"
    mapped to "*" (not compared)."""

    id: str
    file: Path  # the case file, absolute
    line: int  # 1-based line of the case's "id" in the file
    font: str  # font path as written (relative to the case file)
    options: tuple[str, ...]
    unicodes: str
    expected: str
    kind: str = "shape"
    settings: dict = field(default_factory=dict, compare=False, hash=False)
    font_sha256: str | None = None
    source: dict | None = field(default=None, compare=False, hash=False)
    milestone: str | None = None
    reason: str | None = None
    # The face of a collection (`face`, or `--face-index=N` in hb_options).
    face: int = 0
    # The location fields as written, canonical (see parse_location): empty
    # when the case gives none. Values are decimal strings.
    location: dict = field(default_factory=dict, compare=False, hash=False)
    # Glyph ids for `advances` and `extents` cases, or "all"; None otherwise.
    glyphs: tuple[int, ...] | str | None = None

    @property
    def font_path(self) -> Path:
        """The font path resolved against the case file's directory."""
        if self.font.startswith("/"):
            return Path(self.font)
        return Path(os.path.normpath(self.file.parent / self.font))

    @property
    def rel_file(self) -> str:
        return rel(self.file)

    @property
    def scalars(self) -> list[int]:
        return parse_unicodes(self.unicodes)


def rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def case_stem(path: Path) -> str:
    """`tests/cases/harfbuzz/in-house/x.jsonc` -> `harfbuzz/in-house/x`."""
    resolved = path.resolve()
    try:
        stem = resolved.relative_to(CASES_DIR).with_suffix("")
    except ValueError:
        stem = Path(resolved.stem)
    return stem.as_posix()


def parse_unicodes(field_text: str) -> list[int]:
    """hb-shape `--unicodes` syntax: hex numbers, optionally prefixed U+, u+
    or 0x, separated by commas or spaces. Raises ValueError otherwise."""
    values = []
    for word in field_text.replace(",", " ").split():
        digits = word
        for prefix in ("U+", "u+", "0x", "0X"):
            if digits.startswith(prefix):
                digits = digits[len(prefix):]
                break
        if not digits or len(digits) > 6 or any(c not in "0123456789abcdefABCDEF" for c in digits):
            raise ValueError(f"bad code point {word!r}")
        value = int(digits, 16)
        if value > 0x10FFFF or 0xD800 <= value <= 0xDFFF:
            raise ValueError(f"not a Unicode scalar value: {word!r}")
        values.append(value)
    return values


def format_unicodes(values: Sequence[int]) -> str:
    return ",".join(f"U+{v:04X}" for v in values)


# Default_Ignorable_Code_Point (Unicode DerivedCoreProperties.txt, stable
# since Unicode 6.x; the property is closed to new assignments outside these
# blocks). Used to decide whether `remove_default_ignorables` changes a case.
DEFAULT_IGNORABLE = (
    (0x00AD, 0x00AD), (0x034F, 0x034F), (0x061C, 0x061C), (0x115F, 0x1160), (0x17B4, 0x17B5),
    (0x180B, 0x180F), (0x200B, 0x200F), (0x202A, 0x202E), (0x2060, 0x206F), (0x3164, 0x3164),
    (0xFE00, 0xFE0F), (0xFEFF, 0xFEFF), (0xFFA0, 0xFFA0), (0xFFF0, 0xFFF8), (0x1BCA0, 0x1BCA3),
    (0x1D173, 0x1D17A), (0xE0000, 0xE0FFF),
)


def is_default_ignorable(code_point: int) -> bool:
    return any(lo <= code_point <= hi for lo, hi in DEFAULT_IGNORABLE)


def parse_hb_options(words: Sequence[str]) -> dict:
    """Structured options from hb-shape command-line options (already split,
    quotes removed). Options with no structured field are kept verbatim in
    `hb_options`; `--no-glyph-names` is implied and dropped."""
    settings: dict = {}
    for word in words:
        name, has_value, value = word.partition("=")
        if word == "--no-glyph-names":
            continue
        if name == "--direction" and value and value[0].lower() in DIRECTIONS:
            settings["direction"] = DIRECTIONS[value[0].lower()]
        elif name == "--script" and value:
            settings["script"] = value
        elif name == "--language" and value:
            settings["language"] = value
        elif name == "--features" and has_value:
            settings.setdefault("features", []).extend(f.strip() for f in value.split(",") if f.strip())
        elif name == "--variations" and has_value:
            settings.setdefault("variations", []).extend(v.strip() for v in value.split(",") if v.strip())
        elif name == "--font-size" and value.isdigit():
            settings["font_size"] = int(value)
        elif name == "--cluster-level" and value in ("0", "1", "2", "3"):
            settings["cluster_level"] = int(value)
        elif word[2:] in OUTPUT_FLAGS and word.startswith("--"):
            settings.setdefault("output", []).append(word[2:])
        elif word == "--utf8-clusters":
            settings["utf8_clusters"] = True
        elif word == "--remove-default-ignorables":
            settings["remove_default_ignorables"] = True
        else:
            settings.setdefault("hb_options", []).append(word)
    return settings


def hb_options(kind: str, settings: dict, face: int = 0) -> tuple[str, ...]:
    """The hb-shape options equivalent to a case's kind, face and structured
    options, in OPTION_FIELDS order. Shaping cases always carry
    `--no-glyph-names`; every other kind carries its selecting option
    (`--read-outcome`, `--width`, `--coords`, ...). A face other than 0
    follows as `--face-index=N`."""
    out: list[str] = []
    if kind == "shape":
        out.append("--no-glyph-names")
    elif kind == "read":
        out.append(READ_OPTION)
    elif kind == "width":
        out.append(WIDTH_OPTION)
    elif kind in FACT_OPTIONS:
        out.append(FACT_OPTIONS[kind])
    if face:
        out.append(f"--face-index={face}")
    for name in OPTION_FIELDS:
        if name not in settings:
            continue
        value = settings[name]
        if name in ("direction", "script", "language"):
            out.append(f"--{name}={value}")
        elif name in ("features", "variations"):
            out.append(f"--{name}={','.join(value)}")
        elif name == "font_size":
            out.append(f"--font-size={value}")
        elif name == "cluster_level":
            out.append(f"--cluster-level={value}")
        elif name == "output":
            out += [f"--{flag}" for flag in value]
        elif name == "utf8_clusters" and value:
            out.append("--utf8-clusters")
        elif name == "remove_default_ignorables" and value:
            out.append("--remove-default-ignorables")
        elif name == "hb_options":
            out += list(value)
    return tuple(out)


def check_settings(settings: object) -> list[str]:
    """Problems with a case's structured options."""
    if not isinstance(settings, dict):
        return ["options must be an object"]
    problems = []
    for name, value in settings.items():
        if name not in OPTION_FIELDS:
            problems.append(f"unknown option {name!r}")
        elif name == "direction" and value not in DIRECTIONS.values():
            problems.append("direction must be ltr, rtl, ttb or btt")
        elif name in ("script", "language") and not (isinstance(value, str) and value and value.strip() == value and " " not in value):
            problems.append(f"{name} must be a non-empty string")
        elif name in ("features", "variations", "hb_options") and not (
            isinstance(value, list) and all(isinstance(v, str) and v and not any(c.isspace() for c in v) for v in value)
        ):
            problems.append(f"{name} must be a list of strings without spaces")
        elif name == "font_size" and not (isinstance(value, int) and not isinstance(value, bool) and value > 0):
            problems.append("font_size must be a positive integer")
        elif name == "cluster_level" and value not in (0, 1, 2, 3):
            problems.append("cluster_level must be 0, 1, 2 or 3")
        elif name == "output" and not (isinstance(value, list) and all(v in OUTPUT_FLAGS for v in value)):
            problems.append(f"output must list flags from {', '.join(OUTPUT_FLAGS)}")
        elif name in ("utf8_clusters", "remove_default_ignorables") and not isinstance(value, bool):
            problems.append(f"{name} must be true or false")
    return problems


# ---------------------------------------------------------------- locations
#
# A case selects a variable font's location with one of:
#
#   "variations": {"wght": 450, "opsz": 14}     axis tag -> design value
#   "variation": {"weight": "Bold", "width": 87.5, "optical_size": 12}
#   "instance": 3                                a named instance index
#
# `variation` and `variations` combine as roc-font's `Font.Variation` does
# (the named fields first, then `variations` entries winning per tag);
# `instance` stands alone. Without any of them a case measures at
# `Font.Variation.{}`: Regular weight (`wght` 400), Normal width (`wdth`
# 100) and the font's default optical size. HarfBuzz's own default is the
# font's default instance, which for some fonts (Merriweather, Fira Code)
# is Light, so the oracle is always given the resolved location of every
# axis (resolve_location).

# CSS weights (font-weight) and widths (font-stretch percentages), as
# docs/variable-fonts.adoc §5.1 maps Font.Weight and Font.Width.
WEIGHTS = {
    "Thin": 100, "ExtraLight": 200, "Light": 300, "Regular": 400, "Medium": 500,
    "SemiBold": 600, "Bold": 700, "ExtraBold": 800, "Black": 900,
}
WIDTHS = {
    "UltraCondensed": Decimal("50"), "ExtraCondensed": Decimal("62.5"), "Condensed": Decimal("75"),
    "SemiCondensed": Decimal("87.5"), "Normal": Decimal("100"), "SemiExpanded": Decimal("112.5"),
    "Expanded": Decimal("125"), "ExtraExpanded": Decimal("150"), "UltraExpanded": Decimal("200"),
}
VARIATION_FIELDS = ("weight", "width", "optical_size")
# Axis values are Roc `Dec`s: at most 18 decimal places. The magnitude bound
# keeps them far inside Dec and single precision.
MAX_AXIS_VALUE = Decimal(10) ** 9


def dec_text(value: Decimal | int) -> str:
    """The canonical decimal spelling: no exponent, no trailing zeros, no
    `-0` (`Decimal("87.50")` -> `87.5`, `400.0` -> `400`)."""
    d = Decimal(value)
    if d == d.to_integral_value():
        return str(int(d))
    text = format(d.normalize(), "f")
    return text


def parse_axis_number(value: object) -> Decimal | None:
    """A JSON number usable as a `Dec` axis value, or None."""
    if isinstance(value, bool) or not isinstance(value, (int, Decimal)):
        return None
    d = Decimal(value)
    if not d.is_finite() or abs(d) > MAX_AXIS_VALUE:
        return None
    exponent = d.normalize().as_tuple().exponent
    if isinstance(exponent, int) and exponent < -18:
        return None
    return d


def good_axis_tag(tag: object) -> bool:
    """Axis tags in cases: 1 to 8 printable ASCII characters other than
    space, `,`, `:`, `=`, `\\` and quotes. Tags that are not exactly four
    bytes are allowed so a case can show that roc-font ignores them."""
    return isinstance(tag, str) and 1 <= len(tag) <= 8 and all(0x21 <= ord(c) <= 0x7E and c not in ',:="\\' for c in tag)


def parse_location(merged: dict) -> tuple[dict, list[str]]:
    """The canonical location fields of a merged case object, and problems.

    The result holds only the fields given: `variations` as a list of
    `[tag, value]` in written order, `variation` as an object of names or
    decimal strings, `instance` as an integer."""
    location: dict = {}
    errors: list[str] = []
    variations = merged.get("variations")
    if variations is not None:
        if not isinstance(variations, dict):
            errors.append("`variations` must be an object of axis tag to design value, such as {\"wght\": 450}")
        else:
            entries = []
            for tag, value in variations.items():
                number = parse_axis_number(value)
                if not good_axis_tag(tag):
                    errors.append(f"`variations`: bad axis tag {tag!r}")
                elif number is None:
                    errors.append(f"`variations`: {tag} needs a number with at most 18 decimal places")
                else:
                    entries.append([tag, dec_text(number)])
            location["variations"] = entries
    variation = merged.get("variation")
    if variation is not None:
        if not isinstance(variation, dict) or set(variation) - set(VARIATION_FIELDS):
            errors.append("`variation` must be an object with `weight`, `width` and/or `optical_size`")
        else:
            canon: dict = {}
            weight = variation.get("weight")
            if weight is not None:
                if isinstance(weight, str) and weight in WEIGHTS:
                    canon["weight"] = weight
                elif isinstance(weight, int) and not isinstance(weight, bool) and 0 <= weight <= 0xFFFF:
                    canon["weight"] = str(weight)
                else:
                    errors.append(f"`variation.weight` must be one of {', '.join(WEIGHTS)} or an integer 0-65535")
            width = variation.get("width")
            if width is not None:
                number = parse_axis_number(width)
                if isinstance(width, str) and width in WIDTHS:
                    canon["width"] = width
                elif number is not None and number >= 0:
                    canon["width"] = dec_text(number)
                else:
                    errors.append(f"`variation.width` must be one of {', '.join(WIDTHS)} or a percentage")
            size = variation.get("optical_size")
            if size is not None:
                number = parse_axis_number(size)
                if size == "FontDefault":
                    canon["optical_size"] = size
                elif number is not None and number >= 0:
                    canon["optical_size"] = dec_text(number)
                else:
                    errors.append("`variation.optical_size` must be \"FontDefault\" or a size in CSS px")
            location["variation"] = canon
    instance = merged.get("instance")
    if instance is not None:
        if isinstance(instance, int) and not isinstance(instance, bool) and 0 <= instance <= 0xFFFF:
            location["instance"] = instance
        else:
            errors.append("`instance` must be a named instance index (an integer 0-65535)")
        if variations is not None or variation is not None:
            errors.append("`instance` cannot be combined with `variation` or `variations`")
    return location, errors


def sfnt_face_tables(data: bytes, face: int) -> dict[str, tuple[int, int]] | None:
    """The table directory (tag -> offset, length) of one face of an sfnt or
    `ttcf` collection, or None when the bytes are not one or the face does
    not exist. Every offset is checked against the data."""
    def u32(offset: int) -> int | None:
        return struct.unpack_from(">I", data, offset)[0] if 0 <= offset and offset + 4 <= len(data) else None

    start = 0
    if data[:4] == b"ttcf":
        count = u32(8)
        if count is None or face >= count or face < 0:
            return None
        start = u32(12 + 4 * face)
        if start is None:
            return None
    elif face != 0:
        return None
    if start + 12 > len(data) or data[start:start + 4] not in (b"\x00\x01\x00\x00", b"true", b"OTTO"):
        return None
    tables_count = struct.unpack_from(">H", data, start + 4)[0]
    if start + 12 + 16 * tables_count > len(data):
        return None
    tables = {}
    for i in range(tables_count):
        record = start + 12 + 16 * i
        tag = data[record:record + 4].decode("latin-1")
        offset, length = struct.unpack_from(">II", data, record + 8)
        if offset + length <= len(data):
            tables.setdefault(tag, (offset, length))
    return tables


def font_axes(data: bytes, face: int = 0) -> tuple[list[tuple[str, int, int, int]], list[list[int]]]:
    """The `fvar` axes (tag, min, default, max as Fixed 16.16 integers) and
    named instances (coordinates as Fixed) of a face. A face without a
    readable `fvar` has no axes: HarfBuzz ignores a table that fails its
    checks and roc-font's lenient reading drops it, so both then use the
    default instance."""
    tables = sfnt_face_tables(data, face) or {}
    if "fvar" not in tables:
        return [], []
    offset, length = tables["fvar"]
    fvar = data[offset:offset + length]
    if len(fvar) < 16:
        return [], []
    major, _, axes_offset, _, axis_count, axis_size, instance_count, instance_size = struct.unpack_from(">HHHHHHHH", fvar, 0)
    if major != 1 or axis_size != 20 or axes_offset < 16 or instance_size not in (4 * axis_count + 4, 4 * axis_count + 6):
        return [], []
    if axes_offset + axis_count * axis_size + instance_count * instance_size > len(fvar):
        return [], []
    axes = []
    for i in range(axis_count):
        record = axes_offset + 20 * i
        tag = fvar[record:record + 4].decode("latin-1")
        low, default, high = struct.unpack_from(">iii", fvar, record + 4)
        axes.append((tag, low, default, high))
    instances = []
    base = axes_offset + axis_count * axis_size
    for i in range(instance_count):
        record = base + instance_size * i + 4
        instances.append(list(struct.unpack_from(f">{axis_count}i", fvar, record)))
    return axes, instances


def fixed_dec(value: int) -> Decimal:
    """A Fixed 16.16 value as an exact decimal."""
    return Decimal(value) / Decimal(65536)


def resolve_location(case: Case, data: bytes) -> dict | None:
    """Where the oracle measures a case: None for a static font and a case
    without location fields (old record keys stay valid), otherwise
    `{"fields": <the case's location fields>, "axes": [[tag, value], ...]
    in fvar order, "default": <every axis at its default>}`. A named
    instance index past the font's instances gives `"axes": null` and a
    `"problem"`. Values outside an axis's range are passed on unclamped;
    the oracle clamps them as the format defines."""
    axes, instances = font_axes(data, case.face)
    fields = case.location
    if not axes:
        return {"fields": fields, "axes": [], "default": True} if fields else None
    values = [fixed_dec(default) for _, _, default, _ in axes]
    if "instance" in fields:
        index = fields["instance"]
        if index >= len(instances):
            return {"fields": fields, "axes": None, "default": False, "problem": f"no named instance {index} (the font has {len(instances)})"}
        values = [fixed_dec(v) for v in instances[index]]
    else:
        variation = fields.get("variation", {})
        weight = variation.get("weight", "Regular")
        width = variation.get("width", "Normal")
        size = variation.get("optical_size", "FontDefault")
        settings = [
            ("wght", Decimal(WEIGHTS[weight]) if weight in WEIGHTS else Decimal(weight)),
            ("wdth", WIDTHS[width] if width in WIDTHS else Decimal(width)),
        ]
        if size != "FontDefault":
            settings.append(("opsz", Decimal(size)))
        settings += [(tag, Decimal(value)) for tag, value in fields.get("variations", [])]
        for tag, value in settings:
            if len(tag.encode("latin-1", "replace")) != 4:
                continue  # roc-font ignores tags that are not four bytes
            for i, (axis_tag, _, _, _) in enumerate(axes):
                if axis_tag == tag:
                    values[i] = value
    default = all(value == fixed_dec(axis[2]) for value, axis in zip(values, axes))
    return {"fields": fields, "axes": [[axis[0], dec_text(v)] for axis, v in zip(axes, values)], "default": default}


def parse_glyphs(value: object) -> tuple[tuple[int, ...] | str | None, str | None]:
    """`glyphs`: a list of glyph ids (integers 0 to 2^32-1) or "all"."""
    if value == "all":
        return "all", None
    if isinstance(value, list) and all(isinstance(g, int) and not isinstance(g, bool) and 0 <= g <= 0xFFFFFFFF for g in value):
        return tuple(value), None
    return None, "`glyphs` must be a list of glyph ids or \"all\""


def bad_name(name: object) -> bool:
    return not isinstance(name, str) or not name or name.startswith("line-") or any(c in name for c in " \t\n/;~\\\"")


def parse_case_file(path: Path) -> tuple[list[Case], list[str]]:
    """The cases of a JSONC case file and any problems found in it.

    The file is an object with `cases` (a list of case objects) and optional
    `schema` (1), `about` and `defaults` (fields every case takes unless it
    gives its own; `options` objects are merged). See docs/conformance.adoc.
    Every problem in the file is reported; a case with a problem is left out.
    """
    where = rel(path)
    try:
        data = load_jsonc(path)
    except ValueError as error:
        return [], [str(error)]
    if not isinstance(data, dict) or not isinstance(data.get("cases"), list):
        return [], [f"{where}: a case file is an object with a `cases` list"]
    problems: list[str] = []
    if data.get("schema", 1) != 1:
        problems.append(f"{where}: unknown schema {data.get('schema')!r}")
    unknown_top = set(data) - {"schema", "about", "defaults", "cases"}
    if unknown_top:
        problems.append(f"{where}: unknown top-level fields {', '.join(sorted(unknown_top))}")
    defaults = data.get("defaults", {})
    if not isinstance(defaults, dict) or set(defaults) - CASE_FIELDS - {"options"} or "id" in defaults:
        problems.append(f"{where}: `defaults` must be an object of case fields other than id")
        defaults = {}
    # Positions in the comment-blanked text equal those in the file.
    text = strip_jsonc(path.read_text(encoding="utf-8"))
    stem = case_stem(path)
    search_from = 0
    cases: list[Case] = []
    seen: dict[str, int] = {}
    for index, raw in enumerate(data["cases"]):
        line = 0
        label = f"{where}: case {index + 1}"
        if not isinstance(raw, dict):
            problems.append(f"{label}: not an object")
            continue
        name = raw.get("id")
        if isinstance(name, str):
            found = re.compile(r'"id"\s*:\s*' + re.escape(json.dumps(name))).search(text, search_from)
            if found:
                line = text.count("\n", 0, found.start()) + 1
                search_from = found.end()
            label = f"{where}:{line} ({name})"
        merged = dict(defaults)
        merged.update(raw)
        if isinstance(defaults.get("options"), dict) and isinstance(raw.get("options"), dict):
            merged["options"] = {**defaults["options"], **raw["options"]}
        errors: list[str] = []
        if bad_name(name):
            errors.append("`id` must be a non-empty name without spaces, '/', ';', '~' or quotes, not starting with `line-`")
        elif name in seen:
            errors.append(f"duplicate id (first at line {seen[name]})")
        unknown = set(raw) - CASE_FIELDS
        if unknown:
            errors.append(f"unknown fields {', '.join(sorted(unknown))}")
        kind = merged.get("kind", "shape")
        if not (isinstance(kind, str) and kind.isalpha() and kind.islower()):
            errors.append("`kind` must be a lower-case word such as shape or read")
        font = merged.get("font")
        if not isinstance(font, str) or not font:
            errors.append("`font` is required (a path relative to the case file)")
        settings = merged.get("options", {})
        errors += check_settings(settings)
        if kind in KNOWN_KINDS and kind != "shape" and settings:
            errors.append(f"{kind} cases take no options")
        unicodes = merged.get("unicodes")
        scalars: list[int] = []
        if unicodes is not None:
            if isinstance(unicodes, list):
                unicodes = ",".join(str(u) for u in unicodes)
            if not isinstance(unicodes, str):
                errors.append("`unicodes` must be a string or a list of code points")
            else:
                try:
                    scalars = parse_unicodes(unicodes)
                except ValueError as error:
                    errors.append(str(error))
        sample = merged.get("text")
        if sample is not None:
            if not isinstance(sample, str):
                errors.append("`text` must be a string")
            elif unicodes is not None and [ord(c) for c in sample] != scalars:
                errors.append("`text` and `unicodes` disagree")
            else:
                scalars = [ord(c) for c in sample]
                if any(0xD800 <= s <= 0xDFFF for s in scalars):
                    errors.append("`text` holds a lone surrogate")
        if kind in KNOWN_KINDS and kind not in TEXT_KINDS and scalars:
            errors.append(f"{kind} cases take no text")
        location, location_errors = parse_location(merged)
        errors += location_errors
        if kind == "read" and location:
            errors.append("reading cases take no location (`variations`, `variation`, `instance`)")
        face = merged.get("face")
        if face is not None and not (isinstance(face, int) and not isinstance(face, bool) and 0 <= face <= 0xFFFF):
            errors.append("`face` must be a face index (an integer 0-65535)")
            face = None
        # Imported cases spell the face as hb-shape does, in hb_options.
        hb_face = [o.split("=", 1)[1] for o in (settings.get("hb_options", []) if isinstance(settings, dict) else []) if isinstance(o, str) and o.startswith("--face-index=")]
        face_index = face or 0
        if hb_face:
            if merged.get("face") is not None or len(hb_face) > 1 or not hb_face[0].isdigit():
                errors.append("give the face once: `face`, or one --face-index=N in an imported case's hb_options")
            else:
                face_index = int(hb_face[0])
        glyphs = None
        if kind in GLYPH_KINDS:
            glyphs, glyph_error = parse_glyphs(merged.get("glyphs"))
            if glyph_error:
                errors.append(glyph_error)
        elif merged.get("glyphs") is not None:
            errors.append(f"{kind} cases take no `glyphs` (only {' and '.join(GLYPH_KINDS)} do)")
        expected = merged.get("expected", "oracle")
        if not isinstance(expected, str) or "\n" in expected or "\t" in expected:
            errors.append("`expected` must be a one-line string")
        pin = merged.get("font_sha256")
        if pin is not None and not (isinstance(pin, str) and len(pin) == 64 and all(c in "0123456789abcdef" for c in pin)):
            errors.append("`font_sha256` must be 64 lower-case hex digits")
        if isinstance(font, str) and font and pin is None:
            resolved = Path(font) if font.startswith("/") else Path(os.path.normpath(path.resolve().parent / font))
            if is_corpus_font(resolved):
                errors.append("a font in tests/corpus/ needs `font_sha256`")
        for key in ("reason", "comment", "milestone", "area"):
            if key in merged and not isinstance(merged[key], str):
                errors.append(f"`{key}` must be a string")
        if "source" in merged and not isinstance(merged["source"], dict):
            errors.append("`source` must be an object")
        if errors:
            problems += [f"{label}: {e}" for e in errors]
            continue
        seen[name] = line
        cases.append(
            Case(
                id=f"{stem}/{name}",
                file=path.resolve(),
                line=line,
                font=font,
                options=hb_options(kind, settings, face or 0),
                unicodes=format_unicodes(scalars),
                expected="*" if expected == "oracle" else expected,
                kind=kind,
                settings=dict(settings),
                font_sha256=pin,
                source=merged.get("source"),
                milestone=merged.get("milestone"),
                reason=merged.get("reason", merged.get("comment")),
                face=face_index,
                location=location,
                glyphs=glyphs,
            )
        )
    return cases, problems


def fill_expected(path: Path, results: dict[str, str]) -> int:
    """Write results into `"expected": "?"` fields of a JSONC case file.
    `results` maps a case id (Case.id, `<file stem>/<name>`) to its result.
    The case object is found by its `"id": "<name>"` text; the first
    `"expected": "?"` between that and the next `"id"` is replaced, so
    comments and layout are kept. Returns the number of fields written."""
    text = path.read_text(encoding="utf-8")
    blank = strip_jsonc(text)  # same positions, comments blanked
    stem = case_stem(path)
    ids = [m.start() for m in re.finditer(r'"id"\s*:', blank)]
    edits = []
    for case_id, result in results.items():
        name = case_id[len(stem) + 1:] if case_id.startswith(stem + "/") else case_id
        found_id = re.compile(r'"id"\s*:\s*' + re.escape(json.dumps(name))).search(blank)
        if not found_id:
            continue
        begin = found_id.end()
        later = [i for i in ids if i >= begin]
        end = later[0] if later else len(text)
        found = re.compile(r'"expected"\s*:\s*"\?"').search(blank, begin, end)
        if found:
            edits.append((found.start(), found.end(), '"expected": ' + json.dumps(result, ensure_ascii=False)))
    for start, end, replacement in sorted(edits, reverse=True):
        text = text[:start] + replacement + text[end:]
    if edits:
        path.write_text(text, encoding="utf-8")
    return len(edits)


def case_files(selectors: Sequence[str] = ()) -> list[Path]:
    """All case files (`*.jsonc` under tests/cases, except the curation list
    tests/cases/curated.jsonc), or those matching any selector (a path, or a
    substring of the path relative to tests/cases)."""
    every = sorted(p for p in CASES_DIR.rglob("*.jsonc") if p.resolve() != CURATION_LIST.resolve())
    if not selectors:
        return every
    chosen = []
    for path in every:
        stem = path.relative_to(CASES_DIR).as_posix()
        for selector in selectors:
            candidate = Path(selector)
            if (candidate.exists() and candidate.resolve() == path.resolve()) or selector in stem:
                chosen.append(path)
                break
    return chosen


def is_corpus_font(path: Path) -> bool:
    try:
        path.resolve().relative_to(CORPUS_DIR.resolve())
        return True
    except ValueError:
        return False


def has_glyph_names(expected: str) -> bool:
    """True when an hb-shape result names glyphs rather than numbering them
    (HarfBuzz's own expectations usually do)."""
    if not expected.startswith("[") or expected == "[]":
        return False
    for glyph in expected[1:-1].split("|"):
        name = glyph
        for mark in "=@+#<":
            name = name.split(mark, 1)[0]
        if not name.isdigit():
            return True
    return False


# ----------------------------------------------------------- driver protocol

# The request line the Roc driver reads (tools/driver/Case.roc), one per line:
#
#     <tag> TAB <font path> TAB <kind> TAB <items> TAB <flags>
#
# tag: an opaque name echoed back (the case id); font path: as the driver
# should open it; kind: shape, read or width (the run's total advance), and
# from protocol 2 coords, advances, metrics or extents; items: the code
# points (shape, width) or glyph ids (advances, extents, or `all`), lower-case
# hex without prefix, comma-separated, empty for none; flags:
# comma-separated, from no-clusters, no-positions, no-advances,
# utf8-clusters and font-size=<n>, and from protocol 2 face=<n>,
# instance=<n>, weight=<name or n>, width=<name or percent>,
# optical-size=<FontDefault or px> and axis=<tag>:<value> (repeatable, in
# order; later wins). The driver answers `<tag> TAB <result>` per request,
# in order, plus a third column with the reader's problems under --explain.
# docs/conformance.adoc ("The driver") is the full description.
DRIVER_NOOP_HB_OPTIONS = ("--font-funcs=ot", "--font-funcs=ft", "--single-par")

# The protocol tools/driver speaks. 1: shape, read and width at the font's
# default location, face 0. 2: also the font-fact kinds, faces and
# locations (the flags above); tools/driver/Case.roc parses it. The driver
# itself answers `unsupported:instance` and `unsupported:kind=coords` (on a
# variable font) while the public API cannot answer them.
DRIVER_PROTOCOL = 2
PROTOCOL_1_KINDS = ("shape", "read", "width")


def driver_location_flags(case: Case) -> list[str]:
    """Protocol 2 flags for a case's location fields, in the order roc-font
    applies them: the named fields, then each axis setting (an imported
    case's `--variations=` items after its `variations`)."""
    flags: list[str] = []
    location = case.location
    if "instance" in location:
        flags.append(f"instance={location['instance']}")
    variation = location.get("variation", {})
    for name in VARIATION_FIELDS:
        if name in variation:
            flags.append(f"{name.replace('_', '-')}={variation[name]}")
    for tag, value in location.get("variations", []):
        flags.append(f"axis={tag}:{value}")
    for item in case.settings.get("variations", []):
        tag, _, value = item.partition("=")
        # hb-shape spells values freely (`.3`, `1.0`); the driver takes the
        # canonical decimal, which denotes the same number.
        try:
            value = dec_text(Decimal(value))
        except (InvalidOperation, ValueError):
            pass
        flags.append(f"axis={tag}:{value}")
    return flags


def driver_request(case: Case, font: str, location: dict | None = None, protocol: int | None = None) -> tuple[str | None, str]:
    """The protocol line for a case, or None and what the driver cannot
    honour (reported as `unsupported:<what>`: an hb-shape option, `kind=<k>`,
    `face`, or `location`). `location` is resolve_location's result for the
    case's font."""
    protocol = DRIVER_PROTOCOL if protocol is None else protocol
    if case.kind not in (KNOWN_KINDS if protocol >= 2 else PROTOCOL_1_KINDS):
        return None, f"kind={case.kind}"
    flags: list[str] = []
    s = case.settings
    if case.kind == "shape":
        for name in ("direction", "script", "language", "features", "variations", "cluster_level"):
            if name not in s:
                continue
            if name == "direction" and s[name] == "ltr":
                continue
            if name == "variations" and protocol >= 2:
                continue  # sent as axis= flags
            return None, hb_options("", {name: s[name]})[0]
        if "font_size" in s:
            flags.append(f"font-size={s['font_size']}")
        for flag in s.get("output", []):
            flags += ["no-clusters", "no-advances"] if flag == "ned" else [flag]
        if s.get("utf8_clusters"):
            flags.append("utf8-clusters")
        if s.get("remove_default_ignorables") and any(is_default_ignorable(c) for c in case.scalars):
            return None, "--remove-default-ignorables"
        for option in s.get("hb_options", []):
            if option not in DRIVER_NOOP_HB_OPTIONS and not (protocol >= 2 and option.startswith("--face-index=")):
                return None, option
    if case.face:
        if protocol < 2:
            return None, "face"
        flags.append(f"face={case.face}")
    if protocol >= 2:
        flags += driver_location_flags(case)
    elif (location is None and (case.location or s.get("variations"))) or (location is not None and not location["default"]):
        # Protocol 1 measures at the font's default location only: a case
        # runs when every axis the oracle is given is at its default (Inter
        # at Regular, Merriweather at `wght` 300, any static font).
        return None, "location"
    if "\t" in case.id or "\t" in font or "\n" in font:
        return None, "font-path"
    if case.kind in GLYPH_KINDS:
        items = "all" if case.glyphs == "all" else ",".join(f"{g:x}" for g in case.glyphs or ())
    else:
        items = ",".join(f"{c:x}" for c in case.scalars)
    return f"{case.id}\t{font}\t{case.kind}\t{items}\t{','.join(dict.fromkeys(flags))}", ""


# ------------------------------------------------------------------ records


def record_key(case: Case, font_sha256: str, tools: dict[str, str], extractor: int, location: dict | None = None) -> str:
    """SHA-256 over everything that can change a record: the font bytes (by
    hash), the case kind, options and code points (normalised, so spelling
    `U+41` or `U+0041` does not matter; the font path does not matter
    either), the glyph ids of `advances` and `extents` cases, the location
    (resolve_location: the case's location fields and the resolved axes;
    absent for a static font without location fields, so such keys are
    unchanged), the versions of the oracle tools used, and the extractor
    version."""
    material = {
        "extractor": extractor,
        "font_sha256": font_sha256,
        "kind": case.kind,
        "options": list(case.options),
        "tools": tools,
        "unicodes": parse_unicodes(case.unicodes),
    }
    if case.glyphs is not None:
        material["glyphs"] = case.glyphs if isinstance(case.glyphs, str) else list(case.glyphs)
    if location is not None:
        material["location"] = location
    return sha256_bytes(canonical_json(material).encode("ascii"))


def records_path(case_file: Path) -> Path:
    return RECORDS_DIR / (case_stem(case_file) + ".jsonl")


def load_records(case_file: Path) -> dict[str, dict]:
    path = records_path(case_file)
    if not path.exists():
        return {}
    records = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            record = json.loads(line)
            records[record["id"]] = record
    return records


def write_records(case_file: Path, records: Iterable[dict]) -> bool:
    """Write records sorted by id; returns True when the file changed."""
    path = records_path(case_file)
    lines = [canonical_json(r) for r in sorted(records, key=lambda r: r["id"])]
    text = "".join(line + "\n" for line in lines)
    old = path.read_text(encoding="utf-8") if path.exists() else None
    if not lines:
        if path.exists():
            path.unlink()
            return True
        return False
    if old == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return True


def load_known_failures() -> list[dict]:
    data = json.loads(KNOWN_FAILURES.read_text(encoding="utf-8"))
    entries = data["entries"]
    problems = []
    ids = set()
    for entry in entries:
        if not entry.get("id") or not str(entry.get("reason", "")).strip():
            problems.append(f"entry without id or reason: {entry!r}")
        if entry.get("id") in ids:
            problems.append(f"duplicate entry: {entry['id']}")
        ids.add(entry.get("id"))
    if problems:
        raise ValueError("tests/known-failures.json: " + "; ".join(problems))
    return entries


def which(name: str) -> str | None:
    return shutil.which(name)
