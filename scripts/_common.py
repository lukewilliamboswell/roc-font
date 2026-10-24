"""Helpers shared by the conformance scripts (conformance.py, record_oracle.py,
fetch_corpus.py). Standard library only.

The case format, case ids, record keys and record files are defined here once
so the review and the recorder cannot disagree about them. See
docs/conformance.adoc for the formats.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

ROOT = Path(__file__).resolve().parents[1]
TMP_ROOT = Path(os.environ.get("ROC_FONT_TMPDIR", ROOT / ".roc-font-tmp")).resolve()
CASES_DIR = ROOT / "tests" / "cases"
RECORDS_DIR = ROOT / "tests" / "oracle" / "records"
CORPUS_DIR = ROOT / "tests" / "corpus"
KNOWN_FAILURES = ROOT / "tests" / "known-failures.json"
ORACLE_DIR = ROOT / "tools" / "oracle"
DRIVER_DIR = ROOT / "tools" / "driver"

# The option that turns a case into a reading case (a roc-font extension of
# the hb-shape options; HarfBuzz's runner would reject it).
READ_OPTION = "--read-outcome"


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


# -------------------------------------------------------------------- cases


@dataclass(frozen=True)
class Case:
    """One runnable line of a case file."""

    id: str
    file: Path  # the case file, absolute
    line: int  # 1-based line number in the file
    font: str  # font path as written
    options: tuple[str, ...]
    unicodes: str  # the code point field as written
    expected: str

    @property
    def kind(self) -> str:
        return "read" if READ_OPTION in self.options else "shape"

    @property
    def font_path(self) -> Path:
        """The font path resolved as HarfBuzz's runner does: relative to the
        case file's directory; an absolute path loses its `@sha1` suffix."""
        if self.font.startswith("/"):
            return Path(self.font.split("@", 1)[0])
        return Path(os.path.normpath(self.file.parent / self.font))

    @property
    def rel_file(self) -> str:
        return rel(self.file)


def rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def case_stem(path: Path) -> str:
    """`tests/cases/harfbuzz/in-house/x.cases` -> `harfbuzz/in-house/x`."""
    resolved = path.resolve()
    try:
        stem = resolved.relative_to(CASES_DIR).with_suffix("")
    except ValueError:
        stem = Path(resolved.stem)
    return stem.as_posix()


def parse_unicodes(field: str) -> list[int]:
    """hb-shape `--unicodes` syntax: hex numbers, optionally prefixed U+, u+
    or 0x, separated by commas or spaces. Raises ValueError otherwise."""
    values = []
    for word in field.replace(",", " ").split():
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


ID_PREFIX = "# id:"
UNNAMED = "line-"


def parse_case_file(path: Path) -> tuple[list[Case], list[str]]:
    """The runnable cases of a file and any format problems.

    Mirrors HarfBuzz's run-tests.py: blank lines are skipped, a line starting
    `#` is a comment or a disabled case, a line starting `@` is a backend
    directive, and every other line has exactly four `;`-separated fields.
    A `# id: <name>` comment names the next case; unnamed cases get an id
    from a hash of their line, so ids survive reordering.
    """
    stem = case_stem(path)
    cases: list[Case] = []
    problems: list[str] = []
    pending_name: str | None = None
    seen: dict[str, int] = {}
    text = path.read_text(encoding="utf-8")
    for number, raw in enumerate(text.split("\n"), start=1):
        line = raw.strip()
        if not line:
            continue
        if line.startswith(ID_PREFIX):
            pending_name = line[len(ID_PREFIX):].strip()
            if not pending_name or pending_name.startswith(UNNAMED) or any(c in pending_name for c in " \t/;~"):
                problems.append(f"{rel(path)}:{number}: bad case name {pending_name!r}")
                pending_name = None
            continue
        if line.startswith("#") or line.startswith("@"):
            continue
        fields = line.split(";")
        if len(fields) != 4:
            problems.append(f"{rel(path)}:{number}: expected 4 ';'-separated fields, found {len(fields)}")
            pending_name = None
            continue
        font, options, unicodes, expected = fields
        name = pending_name or UNNAMED + sha256_bytes(line.encode("utf-8"))[:12]
        pending_name = None
        case_id = f"{stem}/{name}"
        if case_id in seen:
            if not name.startswith(UNNAMED):
                problems.append(f"{rel(path)}:{number}: duplicate case name {name!r} (first at line {seen[case_id]})")
                continue
            # Identical unnamed lines: number the repeats.
            repeat = 2
            while f"{case_id}~{repeat}" in seen:
                repeat += 1
            case_id = f"{case_id}~{repeat}"
        seen[case_id] = number
        try:
            parse_unicodes(unicodes)
        except ValueError as error:
            problems.append(f"{rel(path)}:{number}: {error}")
        cases.append(Case(case_id, path.resolve(), number, font, tuple(options.split()), unicodes, expected))
    return cases, problems


def case_files(selectors: Sequence[str] = ()) -> list[Path]:
    """All case files, or those matching any selector (a path, or a
    substring of the path relative to tests/cases)."""
    every = sorted(CASES_DIR.rglob("*.cases"))
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


# ------------------------------------------------------------------ records


def record_key(case: Case, font_sha256: str, tools: dict[str, str], extractor: int) -> str:
    """SHA-256 over everything that can change a record: the font bytes (by
    hash), the case kind, options and code points (normalised, so spelling
    `U+41` or `U+0041` does not matter; the font path does not matter
    either), the versions of the oracle tools used, and the extractor
    version."""
    material = {
        "extractor": extractor,
        "font_sha256": font_sha256,
        "kind": case.kind,
        "options": list(case.options),
        "tools": tools,
        "unicodes": parse_unicodes(case.unicodes),
    }
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
