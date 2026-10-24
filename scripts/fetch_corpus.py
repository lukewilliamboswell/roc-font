#!/usr/bin/env python3
"""Fetch the pinned external font corpus, and import HarfBuzz's shaping tests.

    python3 scripts/fetch_corpus.py list                    # entries and whether fetched
    python3 scripts/fetch_corpus.py fetch                   # every entry
    python3 scripts/fetch_corpus.py fetch --tag malformed   # entries with a tag
    python3 scripts/fetch_corpus.py fetch inter-variable-4.1 source-sans-3.052
    python3 scripts/fetch_corpus.py verify                  # re-hash what is fetched
    python3 scripts/fetch_corpus.py import-hb-tests --suite in-house [--file latin]
    python3 scripts/fetch_corpus.py import-hb-tests --curated [--check] [--pin-fonts]

Entries live in tests/corpus.json; downloads go to tests/corpus/<id>/
(not committed). Every download, licence and listed archive member is
checked against its SHA-256 and a mismatch fails the run. An entry marked
`"verified": false` (hashes not yet confirmed by a download) is refused.

`import-hb-tests` converts HarfBuzz `.tests` files from a fetched HarfBuzz
release (default: the `harfbuzz-14.6.0` entry) into JSONC case files,
tests/cases/harfbuzz/<suite>/<name>.jsonc: each case line becomes a case
object with its font (pinned by SHA-256), code points, structured options,
expectation and `source` (suite, file, line and a hash of the normalised
line, which is also the case id). The result is git-ignored and scored, not
gating.

`import-hb-tests --curated` instead copies exactly the cases named in
tests/cases/curated.jsonc (each by suite, file, line and a hash of the
normalised case line, so a case that moved is still found). Cases marked
`"gating": true` go to tests/cases/hb-curated/<suite>.jsonc; the rest go to
tests/cases/hb-pending/<milestone>.jsonc, a scored suite. Fonts of gating
cases up to `font_size_cap` bytes are copied to tests/cases/hb-fonts/<suite>/
with the suite's licence; larger fonts, and the fonts of pending cases, are
referenced in the fetched corpus (pending cases are skipped without it). Every
font must match its SHA-256 pin in curated.jsonc (`--pin-fonts` records pins
for newly used fonts and drops unused ones). The script owns hb-curated/,
hb-pending/ and hb-fonts/: anything there it did not write is removed.
Re-running changes nothing; `--check` writes nothing and fails if any
output would change.

Standard library only.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import sys
import tarfile
import urllib.request
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import (  # noqa: E402
    CASES_DIR,
    CORPUS_DIR,
    ROOT,
    format_unicodes,
    load_jsonc,
    has_glyph_names,
    parse_hb_options,
    parse_unicodes,
    rel,
    sha256_bytes,
    sha256_file,
)

MANIFEST = ROOT / "tests" / "corpus.json"
CURATED = CASES_DIR / "curated.jsonc"
CURATED_HEADER = (
    "// Curation list for scripts/fetch_corpus.py import-hb-tests --curated; see\n"
    "// `about` and docs/conformance.adoc. --pin-fonts rewrites this file in\n"
    "// canonical form (this header kept, other comments dropped): put\n"
    "// explanations in `reason`.\n"
)
CURATED_DIRS = {"gating": CASES_DIR / "hb-curated", "pending": CASES_DIR / "hb-pending", "fonts": CASES_DIR / "hb-fonts"}
SUITES = ("in-house", "aots", "text-rendering-tests")
# Licence copied beside committed fonts, relative to test/shape/data (in-house
# fonts are covered by HarfBuzz's top-level COPYING).
SUITE_LICENCE = {"in-house": "../../../COPYING", "aots": "aots/COPYING", "text-rendering-tests": "text-rendering-tests/COPYING"}
CURATED_FIELDS = ("id", "suite", "file", "line", "case", "area", "milestone", "gating", "needs", "reason")


def load_manifest() -> list[dict]:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    entries = data["entries"]
    ids = [e["id"] for e in entries]
    if len(ids) != len(set(ids)):
        raise SystemExit("tests/corpus.json: duplicate entry ids")
    for entry in entries:
        for field in ("id", "kind", "url", "sha256", "licence", "tags"):
            if field not in entry:
                raise SystemExit(f"tests/corpus.json: {entry.get('id', '?')} has no {field}")
        if "/main/" in entry["url"] or "/master/" in entry["url"]:
            raise SystemExit(f"tests/corpus.json: {entry['id']} points at a moving branch")
    return entries


def entry_dir(entry: dict) -> Path:
    return CORPUS_DIR / entry["id"]


def download_path(entry: dict) -> Path:
    return entry_dir(entry) / entry.get("filename", Path(entry["url"]).name)


def licence_path(entry: dict) -> Path:
    return entry_dir(entry) / ("LICENCE-" + Path(entry["licence"]["url"]).name)


def download(url: str, target: Path, sha256: str) -> None:
    if target.exists() and sha256_file(target) == sha256:
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_name(target.name + ".part")
    print(f"  downloading {url}", flush=True)
    with urllib.request.urlopen(url, timeout=300) as response, partial.open("wb") as out:
        shutil.copyfileobj(response, out)
    digest = sha256_file(partial)
    if digest != sha256:
        partial.unlink()
        raise SystemExit(f"sha256 mismatch for {url}:\n  expected {sha256}\n  got      {digest}")
    partial.replace(target)


def extract(entry: dict, archive: Path) -> None:
    dest = entry_dir(entry)
    members: dict[str, str] = entry.get("members", {})
    strip = int(entry.get("strip_components", 0))
    include = tuple(entry.get("include", ()))
    marker = dest / ".extracted"
    if marker.exists() and marker.read_text(encoding="utf-8") == entry["sha256"]:
        return
    print(f"  extracting {archive.name}", flush=True)
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as bundle:
            names = list(members) if members else [n for n in bundle.namelist() if not n.endswith("/")]
            names = [n for n in names if not include or Path(*Path(n).parts[strip:]).as_posix().startswith(include)]
            for name in names:
                parts = Path(name).parts[strip:]
                if not parts or any(p in ("..", "") for p in parts) or Path(name).is_absolute():
                    raise SystemExit(f"{entry['id']}: unsafe archive member {name}")
                target = dest.joinpath(*parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(bundle.read(name))
    else:
        with tarfile.open(archive) as bundle:
            chosen = []
            for member in bundle.getmembers():
                parts = Path(member.name).parts[strip:]
                if not parts or (members and member.name not in members):
                    continue
                if include and not Path(*parts).as_posix().startswith(include):
                    continue
                member.name = str(Path(*parts))
                chosen.append(member)
            # The "data" filter refuses absolute paths, links out of the tree
            # and device files.
            bundle.extractall(dest, members=chosen, filter="data")
    for name, digest in members.items():
        target = dest.joinpath(*Path(name).parts[strip:])
        if sha256_file(target) != digest:
            raise SystemExit(f"{entry['id']}: sha256 mismatch for archive member {name}")
    marker.write_text(entry["sha256"], encoding="utf-8")


def fetch(entries: list[dict]) -> int:
    unverified = [e["id"] for e in entries if not e.get("verified", False)]
    if unverified:
        print("refusing entries whose hashes were never verified: " + ", ".join(unverified), file=sys.stderr)
        return 1
    for entry in entries:
        print(f"{entry['id']}", flush=True)
        download(entry["url"], download_path(entry), entry["sha256"])
        download(entry["licence"]["url"], licence_path(entry), entry["licence"]["sha256"])
        if entry["kind"] == "archive":
            extract(entry, download_path(entry))
    print(f"{len(entries)} entries fetched into {rel(CORPUS_DIR)}")
    return 0


def verify(entries: list[dict]) -> int:
    bad = 0
    for entry in entries:
        path = download_path(entry)
        if not path.exists():
            print(f"{entry['id']}: not fetched")
            continue
        ok = sha256_file(path) == entry["sha256"] and sha256_file(licence_path(entry)) == entry["licence"]["sha256"]
        for name, digest in entry.get("members", {}).items():
            member = entry_dir(entry).joinpath(*Path(name).parts[int(entry.get("strip_components", 0)):])
            ok = ok and member.exists() and sha256_file(member) == digest
        print(f"{entry['id']}: {'ok' if ok else 'MISMATCH'}")
        bad += 0 if ok else 1
    return 1 if bad else 0


def normalise_case(line: str) -> str:
    """A HarfBuzz case line with each of its four fields stripped and runs
    of whitespace collapsed: the form whose hash identifies an imported
    case across versions, wherever its line moves."""
    return ";".join(" ".join(field.split()) for field in line.strip().split(";"))


def case_identity(line: str) -> str:
    return sha256_bytes(normalise_case(line).encode("utf-8"))[:16]


def is_case_line(raw: str) -> bool:
    line = raw.strip()
    return bool(line) and not line.startswith(("#", "@")) and len(line.split(";")) == 4


def split_options(text: str) -> list[str]:
    """hb-shape options as HarfBuzz's runner passes them (shell words, so
    `--features="test"` loses its quotes)."""
    try:
        return shlex.split(text)
    except ValueError:
        return text.split()


class Converter:
    """Turns HarfBuzz `.tests` lines into JSONC case objects."""

    def __init__(self, data_dir: Path, label: str):
        self.data_dir = data_dir
        self.label = label
        self.hashes: dict[Path, str] = {}

    def font_hash(self, font: Path) -> str:
        if font not in self.hashes:
            self.hashes[font] = sha256_file(font)
        return self.hashes[font]

    def convert(self, suite: str, file: str, number: int, raw: str, font_location: Path | None, case_dir: Path) -> tuple[dict, Path | None]:
        """The case object (without `id`) for one upstream line, and the
        font it uses inside the HarfBuzz tree (None for a system font).
        `font_location` overrides where the case file points for the font
        (a committed copy)."""
        line = raw.strip()
        font_field, options, unicodes, expected = line.split(";")
        case: dict = {}
        tree_font: Path | None = None
        if font_field.startswith("/"):
            path, _, sha1 = font_field.partition("@")
            case["font"] = path
        else:
            tree_font = Path(os.path.normpath(self.data_dir / suite / "tests" / font_field))
            target = font_location or tree_font
            case["font"] = Path(os.path.relpath(target, case_dir)).as_posix()
            if tree_font.is_file():
                case["font_sha256"] = self.font_hash(tree_font)
        case["unicodes"] = format_unicodes(parse_unicodes(unicodes))
        settings = parse_hb_options(split_options(options))
        if settings:
            case["options"] = settings
        written = expected.strip()
        case["expected"] = written if written not in ("", "*") and not has_glyph_names(written) else "oracle"
        source = {"suite": suite, "file": file, "line": number, "case": case_identity(line), "harfbuzz": self.label}
        if font_field.startswith("/") and "@" in font_field:
            source["font_sha1"] = font_field.partition("@")[2]
        source["expected"] = written
        case["source"] = source
        return case, tree_font


def case_json(case: dict) -> str:
    order = ["id", "kind", "font", "font_sha256", "text", "unicodes", "options", "expected", "milestone", "area", "needs", "reason", "source"]
    ordered = {k: case[k] for k in order if k in case}
    return json.dumps(ordered, ensure_ascii=False)


def write_jsonc(header: list[str], cases: list[dict]) -> str:
    lines = [f"// {h}" if h else "//" for h in header]
    lines += ["{", '  "schema": 1,', '  "cases": [']
    for index, case in enumerate(cases):
        lines.append("    " + case_json(case) + ("," if index + 1 < len(cases) else ""))
    lines += ["  ]", "}", ""]
    return "\n".join(lines)


def import_hb_tests(checkout: Path, suites: list[str], only: list[str], dest_root: Path, label: str) -> int:
    data = checkout / "test" / "shape" / "data"
    if not data.is_dir():
        print(f"no HarfBuzz test data under {rel(checkout)}; fetch it first (fetch harfbuzz-14.6.0)", file=sys.stderr)
        return 1
    converter = Converter(data, label)
    written = cases_total = 0
    for suite in suites:
        source_dir = data / suite / "tests"
        if not source_dir.is_dir():
            print(f"no suite {suite} in {rel(data)}", file=sys.stderr)
            return 1
        dest_dir = dest_root / suite
        for source in sorted(source_dir.glob("*.tests")):
            if only and not any(o in source.stem for o in only):
                continue
            cases = []
            seen: set[str] = set()
            for number, raw in enumerate(source.read_text(encoding="utf-8").split("\n"), start=1):
                if not is_case_line(raw):
                    continue
                case, _ = converter.convert(suite, source.name, number, raw, None, dest_dir)
                name = "c" + case["source"]["case"][:12]
                repeat = 2
                while name in seen:  # identical lines: number the repeats
                    name = f"c{case['source']['case'][:12]}-{repeat}"
                    repeat += 1
                seen.add(name)
                cases.append({"id": name, **case})
            header = [
                f"Imported from HarfBuzz {label} test/shape/data/{suite}/tests/{source.name}",
                "by scripts/fetch_corpus.py import-hb-tests; re-import rather than edit.",
                "Ids are hashes of the normalised upstream line; `source` gives its line.",
            ]
            target = dest_dir / (source.stem + ".jsonc")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(write_jsonc(header, cases), encoding="utf-8")
            written += 1
            cases_total += len(cases)
    print(f"imported {cases_total} cases in {written} files into {rel(dest_root)}")
    return 0


# ------------------------------------------------------------------ curated


def load_curated(path: Path) -> tuple[dict, list[str]]:
    data = load_jsonc(path)
    problems = []
    if not isinstance(data, dict):
        return {}, ["curated.jsonc must hold an object"]
    if data.get("schema") != 1:
        problems.append(f"unknown schema {data.get('schema')!r}")
    ids: set[str] = set()
    keys: set[tuple] = set()
    for index, entry in enumerate(data.get("entries", [])):
        where = f"entry {index} ({entry.get('id', '?')})"
        missing = [f for f in CURATED_FIELDS if f not in entry]
        if missing:
            problems.append(f"{where}: missing {', '.join(missing)}")
            continue
        name = entry["id"]
        if not name or name.startswith("line-") or any(c in name for c in " \t/;~\\\""):
            problems.append(f"{where}: bad id")
        if name in ids:
            problems.append(f"{where}: duplicate id")
        ids.add(name)
        if entry["suite"] not in SUITES:
            problems.append(f"{where}: unknown suite {entry['suite']!r}")
        if "/" in entry["file"] or not entry["file"].endswith(".tests"):
            problems.append(f"{where}: file must be a .tests file name")
        if not isinstance(entry["line"], int) or entry["line"] < 1:
            problems.append(f"{where}: line must be a positive integer")
        if not isinstance(entry["gating"], bool):
            problems.append(f"{where}: gating must be true or false")
        if not entry["milestone"] or not all(c.isalnum() or c in "-." for c in entry["milestone"]):
            problems.append(f"{where}: milestone must be a short tag such as M3")
        if not isinstance(entry["needs"], list) or not all(isinstance(n, str) for n in entry["needs"]):
            problems.append(f"{where}: needs must be a list of strings")
        if not str(entry["reason"]).strip():
            problems.append(f"{where}: empty reason")
        key = (entry["suite"], entry["file"], entry["case"])
        if key in keys:
            problems.append(f"{where}: the same case is curated twice")
        keys.add(key)
    return data, problems


def locate(entry: dict, lines: list[str]) -> tuple[int | None, str]:
    """The 1-based line of a curated case in its upstream file: the recorded
    line when its hash matches, otherwise the nearest line with that hash."""
    line = entry["line"]
    if line <= len(lines) and is_case_line(lines[line - 1]) and case_identity(lines[line - 1]) == entry["case"]:
        return line, ""
    matches = [n for n, raw in enumerate(lines, start=1) if is_case_line(raw) and case_identity(raw) == entry["case"]]
    if not matches:
        return None, f"{entry['id']}: no case with hash {entry['case']} in {entry['suite']}/tests/{entry['file']} (changed or removed upstream)"
    best = min(matches, key=lambda n: (abs(n - line), n))
    return best, f"{entry['id']}: moved from line {line} to {best}; update curated.jsonc"


def import_curated(checkout: Path, label: str, check: bool, pin: bool) -> int:
    data_dir = checkout / "test" / "shape" / "data"
    if not data_dir.is_dir():
        print(f"no HarfBuzz test data under {rel(checkout)}; fetch it first (fetch harfbuzz-14.6.0)", file=sys.stderr)
        return 1
    curated, problems = load_curated(CURATED)
    cap = int(curated.get("font_size_cap", 65536))
    pins: dict[str, dict] = dict(curated.get("fonts", {}))
    notes: list[str] = []
    outputs: dict[Path, str | bytes] = {}
    groups: dict[Path, list[dict]] = {}
    group_title: dict[Path, str] = {}
    used_fonts: dict[str, Path] = {}
    upstream: dict[tuple[str, str], list[str]] = {}
    converter = Converter(data_dir, label)
    committed_fonts: set[str] = set()

    for entry in curated.get("entries", []):
        if not all(f in entry for f in CURATED_FIELDS):
            continue
        suite, file = entry["suite"], entry["file"]
        source = data_dir / suite / "tests" / file
        if (suite, file) not in upstream:
            if not source.is_file():
                problems.append(f"{entry['id']}: no file {suite}/tests/{file} in {rel(checkout)}")
                upstream[(suite, file)] = []
            else:
                upstream[(suite, file)] = source.read_text(encoding="utf-8").split("\n")
        lines = upstream[(suite, file)]
        if not lines:
            continue
        number, note = locate(entry, lines)
        if number is None:
            problems.append(note)
            continue
        if note:
            notes.append(note)
        font_field = lines[number - 1].strip().split(";")[0]
        if font_field.startswith(("/", '"')) or "@" in font_field:
            problems.append(f"{entry['id']}: font {font_field!r} is not a font in the HarfBuzz tree")
            continue
        font = Path(os.path.normpath(source.parent / font_field))
        try:
            font_key = font.relative_to(data_dir).as_posix()
        except ValueError:
            problems.append(f"{entry['id']}: font {font_field!r} points outside test/shape/data")
            continue
        if not font.is_file():
            problems.append(f"{entry['id']}: font {font_key} is missing from {rel(checkout)}")
            continue
        used_fonts[font_key] = font
        # Only gating cases get a committed copy: pending (scored) cases read
        # the fetched corpus and are skipped without it.
        location = CURATED_DIRS["fonts"] / suite / font.name if entry["gating"] and font.stat().st_size <= cap else None
        if location is not None:
            committed_fonts.add(font_key)
        if entry["gating"]:
            case_file = CURATED_DIRS["gating"] / f"{suite}.jsonc"
            group_title[case_file] = f"Gating cases from the {suite} suite."
        else:
            case_file = CURATED_DIRS["pending"] / f"{entry['milestone']}.jsonc"
            group_title[case_file] = f"Scored cases tagged {entry['milestone']}: in scope, not passing yet."
        case, _ = converter.convert(suite, file, number, lines[number - 1], location, case_file.parent)
        case.update({"id": entry["id"], "milestone": entry["milestone"], "area": entry["area"], "reason": entry["reason"]})
        if entry["needs"]:
            case["needs"] = entry["needs"]
        groups.setdefault(case_file, []).append(case)

    for font_key, font in sorted(used_fonts.items()):
        digest = converter.font_hash(font)
        size = font.stat().st_size
        pinned = pins.get(font_key)
        if pinned is None:
            if pin:
                pins[font_key] = {"sha256": digest, "size": size}
            else:
                problems.append(f"font {font_key} has no pin in curated.jsonc (run with --pin-fonts after review)")
                continue
        elif pinned.get("sha256") != digest or pinned.get("size") != size:
            problems.append(f"font {font_key}: sha256 {digest} ({size} bytes) differs from the pin {pinned.get('sha256')} ({pinned.get('size')} bytes)")
            continue
        if font_key in committed_fonts:
            suite = font_key.split("/", 1)[0]
            outputs[CURATED_DIRS["fonts"] / suite / font.name] = font.read_bytes()
            outputs[CURATED_DIRS["fonts"] / suite / "COPYING"] = (data_dir / SUITE_LICENCE[suite]).resolve().read_bytes()
    unused = sorted(set(pins) - set(used_fonts))
    if unused:
        if pin:
            for font_key in unused:
                del pins[font_key]
        else:
            problems.append("pins for fonts no curated case uses: " + ", ".join(unused) + " (run with --pin-fonts)")

    header = [
        f"Curated from HarfBuzz {label} test/shape/data by scripts/fetch_corpus.py",
        "import-hb-tests --curated, from tests/cases/curated.jsonc; edit that file",
        "and re-import rather than editing this one. `source` names the upstream",
        "line and its hash; `source.expected` is HarfBuzz's own expectation (glyph",
        "names are not compared; the oracle records are the reference).",
    ]
    for case_file, cases in sorted(groups.items()):
        outputs[case_file] = write_jsonc(header + ["", group_title[case_file]], cases)

    if problems:
        for problem in problems:
            print(problem, file=sys.stderr)
        print(f"{len(problems)} problems; nothing written", file=sys.stderr)
        return 1

    changes = []
    for path, content in sorted(outputs.items()):
        raw = content.encode("utf-8") if isinstance(content, str) else content
        if not path.exists() or path.read_bytes() != raw:
            changes.append(("write", path, raw))
    for root in CURATED_DIRS.values():
        if root.exists():
            for path in sorted(p for p in root.rglob("*") if p.is_file()):
                if path not in outputs:
                    changes.append(("remove", path, b""))
    new_curated = dict(curated)
    new_curated["fonts"] = {k: pins[k] for k in sorted(pins)}
    curated_text = CURATED_HEADER + json.dumps(new_curated, indent=2, ensure_ascii=False) + "\n"
    if curated_text != CURATED.read_text(encoding="utf-8"):
        if pin:
            changes.append(("write", CURATED, curated_text.encode("utf-8")))
        else:
            print("note: tests/cases/curated.jsonc is not in canonical form (indent 2, sorted font pins); --pin-fonts rewrites it")
    for note in notes:
        print(f"note: {note}")
    if check:
        for action, path, _ in changes:
            print(f"would {action} {rel(path)}")
        print(f"curated import is {'out of date' if changes else 'current'}")
        return 1 if changes else 0
    for action, path, raw in changes:
        if action == "write":
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
        else:
            path.unlink()
    for root in CURATED_DIRS.values():
        if root.exists():
            for directory in sorted((p for p in root.rglob("*") if p.is_dir()), reverse=True):
                if not any(directory.iterdir()):
                    directory.rmdir()
    gating = sum(len(c) for f, c in groups.items() if f.parent == CURATED_DIRS["gating"])
    pending = sum(len(c) for f, c in groups.items() if f.parent == CURATED_DIRS["pending"])
    committed = sorted(committed_fonts)
    print(
        f"{gating + pending} curated cases: {gating} gating, {pending} pending in "
        f"{sum(1 for f in groups if f.parent == CURATED_DIRS['pending'])} scored files; {len(used_fonts)} fonts "
        f"({len(committed)} copied, {sum(pins[k]['size'] for k in committed)} bytes; "
        f"{len(used_fonts) - len(committed)} referenced in the corpus); {len(changes)} files changed"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list")
    fetch_cmd = sub.add_parser("fetch")
    fetch_cmd.add_argument("ids", nargs="*")
    fetch_cmd.add_argument("--tag", action="append", default=[])
    verify_cmd = sub.add_parser("verify")
    verify_cmd.add_argument("ids", nargs="*")
    imp = sub.add_parser("import-hb-tests")
    imp.add_argument("--checkout", type=Path, default=CORPUS_DIR / "harfbuzz-14.6.0", help="extracted HarfBuzz release or checkout")
    imp.add_argument("--label", default=None, help="version named in the header (default: checkout directory name)")
    imp.add_argument("--suite", action="append", default=[], help="in-house, aots or text-rendering-tests (repeatable)")
    imp.add_argument("--file", action="append", default=[], help="only .tests files whose name contains this (repeatable)")
    imp.add_argument("--dest", type=Path, default=CASES_DIR / "harfbuzz")
    imp.add_argument("--curated", action="store_true", help="import only the cases in tests/cases/curated.jsonc")
    imp.add_argument("--check", action="store_true", help="with --curated, write nothing; fail if an output would change")
    imp.add_argument("--pin-fonts", action="store_true", help="with --curated, pin newly used fonts and drop unused pins")
    args = parser.parse_args()

    entries = load_manifest()
    if args.command == "list":
        for entry in entries:
            state = "fetched" if download_path(entry).exists() else "-"
            print(f"{entry['id']:28} {entry['kind']:8} {state:8} {','.join(entry['tags'])}")
        return 0
    if args.command in ("fetch", "verify"):
        chosen = [e for e in entries if (not args.ids or e["id"] in args.ids)]
        if args.command == "fetch" and args.tag:
            chosen = [e for e in chosen if set(args.tag) & set(e["tags"])]
        missing = set(args.ids) - {e["id"] for e in entries}
        if missing:
            print("unknown entries: " + ", ".join(sorted(missing)), file=sys.stderr)
            return 1
        return fetch(chosen) if args.command == "fetch" else verify(chosen)
    label = args.label or args.checkout.resolve().name.removeprefix("harfbuzz-")
    if args.curated:
        if args.suite or args.file:
            parser.error("--curated takes its cases from tests/cases/curated.jsonc; drop --suite and --file")
        return import_curated(args.checkout.resolve(), label, args.check, args.pin_fonts)
    if args.check or args.pin_fonts:
        parser.error("--check and --pin-fonts go with --curated")
    return import_hb_tests(args.checkout.resolve(), args.suite or ["in-house"], args.file, args.dest.resolve(), label)


if __name__ == "__main__":
    sys.exit(main())
