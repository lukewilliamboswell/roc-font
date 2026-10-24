#!/usr/bin/env python3
"""Fetch the pinned external font corpus, and import HarfBuzz's shaping tests.

    python3 scripts/fetch_corpus.py list                    # entries and whether fetched
    python3 scripts/fetch_corpus.py fetch                   # every entry
    python3 scripts/fetch_corpus.py fetch --tag malformed   # entries with a tag
    python3 scripts/fetch_corpus.py fetch inter-variable-4.1 source-sans-3.052
    python3 scripts/fetch_corpus.py verify                  # re-hash what is fetched
    python3 scripts/fetch_corpus.py import-hb-tests --suite in-house [--file latin]

Entries live in tests/corpus.json; downloads go to tests/corpus/<id>/
(not committed). Every download, licence and listed archive member is
checked against its SHA-256 and a mismatch fails the run. An entry marked
`"verified": false` (hashes not yet confirmed by a download) is refused.

`import-hb-tests` copies HarfBuzz `.tests` files from a fetched HarfBuzz
release (default: the `harfbuzz-14.6.0` entry) into tests/cases/harfbuzz/
<suite>/<name>.cases, rewriting each relative font path so it still points
at the fetched font. Nothing else in a line changes, so the files stay in
HarfBuzz's format.

Standard library only.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tarfile
import urllib.request
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import CASES_DIR, CORPUS_DIR, ROOT, rel, sha256_file  # noqa: E402

MANIFEST = ROOT / "tests" / "corpus.json"


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


def import_hb_tests(checkout: Path, suites: list[str], only: list[str], dest_root: Path, label: str) -> int:
    data = checkout / "test" / "shape" / "data"
    if not data.is_dir():
        print(f"no HarfBuzz test data under {rel(checkout)}; fetch it first (fetch harfbuzz-14.6.0)", file=sys.stderr)
        return 1
    written = 0
    for suite in suites:
        source_dir = data / suite / "tests"
        if not source_dir.is_dir():
            print(f"no suite {suite} in {rel(data)}", file=sys.stderr)
            return 1
        dest_dir = dest_root / suite
        for source in sorted(source_dir.glob("*.tests")):
            if only and not any(o in source.stem for o in only):
                continue
            lines = [
                f"# Imported from HarfBuzz {label} test/shape/data/{suite}/tests/{source.name}",
                "# by scripts/fetch_corpus.py import-hb-tests; re-import rather than edit.",
            ]
            for raw in source.read_text(encoding="utf-8").split("\n"):
                lines.append(rewrite_line(raw, source_dir, dest_dir))
            while lines and not lines[-1].strip():
                lines.pop()
            target = dest_dir / (source.stem + ".cases")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("\n".join(lines) + "\n", encoding="utf-8")
            written += 1
    print(f"imported {written} files into {rel(dest_root)}")
    return 0


def rewrite_line(raw: str, source_dir: Path, dest_dir: Path) -> str:
    """Point a case line's relative font path at the same font from the new
    location. Disabled cases (`#` directly followed by the path) are
    rewritten too; comments and directives are copied unchanged."""
    prefix, body = ("#", raw[1:]) if raw.startswith("#") and not raw.startswith("# ") else ("", raw)
    fields = body.split(";")
    if len(fields) != 4 or not fields[0] or fields[0].startswith(("/", '"/', "@", " ")):
        return raw
    font = os.path.normpath(source_dir / fields[0])
    fields[0] = Path(os.path.relpath(font, dest_dir)).as_posix()
    return prefix + ";".join(fields)


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
    return import_hb_tests(args.checkout.resolve(), args.suite or ["in-house"], args.file, args.dest.resolve(), label)


if __name__ == "__main__":
    sys.exit(main())
