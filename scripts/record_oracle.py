#!/usr/bin/env python3
"""Record oracle results for the conformance cases in tests/cases/.

Each case gets one record in tests/oracle/records/<case file>.jsonl, keyed by
a SHA-256 over everything that can change it: the font bytes, the case kind,
options and code points, the versions of the oracle tools that answer it and
the extractor version (see scripts/_common.py, record_key). A record is
recomputed only when its key changes; `--force` recomputes every record and
must reproduce the files byte for byte.

    python3 scripts/record_oracle.py --setup      # once: venv, pinned wheels, OTS
    python3 scripts/record_oracle.py              # record what changed
    python3 scripts/record_oracle.py inter        # only case files matching "inter"
    python3 scripts/record_oracle.py --force      # re-record everything
    python3 scripts/record_oracle.py --check      # fail if any record is missing or stale
    python3 scripts/record_oracle.py --fill-expected inter   # write results into `?` expectations
    python3 scripts/record_oracle.py --setup-chrome  # once: pinned Puppeteer and Chrome (needs npm)
    python3 scripts/record_oracle.py chrome       # the Chrome width cases (tests/cases/chrome.jsonc)

The oracle runs in tools/oracle/.venv under `python -I` (tools/oracle/extract.py);
this script itself needs only the standard library. A case whose expected
column is written in glyph-id notation must agree with its record; `*` and
`?` expectations, and HarfBuzz expectations that use glyph names, are not
compared.

Cases come only from scripts/_common.py (parse_case_file and the Case
dataclass); this script never parses case files. Each case's `kind` selects
its oracle: `shape`, `read` and the font-fact kinds (`coords`, `advances`,
`metrics`, `extents`) go to tools/oracle/extract.py, and `width`
cases are answered by a pinned Chrome
through Puppeteer (tools/oracle/chrome/width.mjs): the text's advance width
in font units with the browser's default features, `width:<n>`. Their keys
come from tools/oracle/chrome/pin.json, so `--check` needs no Node. When Node
or the pinned Puppeteer is not installed, width cases keep their records and
are reported as skipped.

Every request on a variable font, and every case with location fields,
carries the resolved location (scripts/_common.py, resolve_location): each
axis at the value the case selects, `wght` 400 and `wdth` 100 when it
selects none (roc-font's Regular default, not HarfBuzz's default instance).
The location is part of the record and its key.

A case file named by path outside tests/cases keeps its records beside it,
in `<name>-records.jsonl`.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import (  # noqa: E402
    CASES_DIR,
    ORACLE_DIR,
    ROOT,
    Case,
    canonical_json,
    case_files,
    case_stem,
    format_unicodes,
    has_glyph_names,
    load_records,
    parse_case_file,
    parse_unicodes,
    record_key,
    rel,
    resolve_location,
    sha256_bytes,
    sha256_file,
    write_records,
)

VENV = Path(os.environ.get("ROC_FONT_ORACLE_VENV", ORACLE_DIR / ".venv"))
REQUIREMENTS = ORACLE_DIR / "requirements.txt"
OTS_PIN = ORACLE_DIR / "ots.json"
EXTRACT = ORACLE_DIR / "extract.py"
CHROME_DIR = ORACLE_DIR / "chrome"
CHROME_PIN = CHROME_DIR / "pin.json"
CHROME_EXTRACT = CHROME_DIR / "width.mjs"

# Case kinds and the oracle that answers each. The kind is a field of the
# Case that scripts/_common.py parses; this script never reads case files.
ORACLE_KINDS = ("shape", "read", "coords", "advances", "metrics", "extents")
CHROME_KINDS = ("width",)


def in_cases_dir(path: Path) -> bool:
    try:
        path.resolve().relative_to(CASES_DIR.resolve())
        return True
    except ValueError:
        return False


def records_file(case_file: Path) -> Path:
    """Records of a case file outside tests/cases sit beside it."""
    return case_file.resolve().with_name(case_stem(case_file).rsplit("/", 1)[-1] + "-records.jsonl")


def load_records_for(case_file: Path) -> dict[str, dict]:
    if in_cases_dir(case_file):
        return load_records(case_file)
    path = records_file(case_file)
    if not path.exists():
        return {}
    return {r["id"]: r for r in (json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip())}


def write_records_for(case_file: Path, records) -> bool:
    if in_cases_dir(case_file):
        return write_records(case_file, records)
    path = records_file(case_file)
    text = "".join(canonical_json(r) + "\n" for r in sorted(records, key=lambda r: r["id"]))
    old = path.read_text(encoding="utf-8") if path.exists() else None
    if old == text:
        return False
    path.write_text(text, encoding="utf-8")
    return True


def select_case_files(selectors: list[str]) -> list[Path]:
    """case_files, plus case files named by path outside tests/cases."""
    chosen = case_files(selectors)
    for selector in selectors:
        candidate = Path(selector)
        if candidate.is_file() and not in_cases_dir(candidate):
            chosen.append(candidate.resolve())
    return chosen


def venv_python() -> Path:
    return VENV / ("Scripts/python.exe" if os.name == "nt" else "bin/python")


def pinned_versions() -> dict[str, str]:
    pins = {}
    for line in REQUIREMENTS.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if "==" in line and not line.startswith("#"):
            name, version = line.split("==", 1)
            pins[name.strip().lower()] = version.split()[0].rstrip("\\").strip()
    return pins


# -------------------------------------------------------------------- setup


def setup(fetch_ots: bool) -> int:
    if not venv_python().exists():
        print(f"creating {rel(VENV)}", flush=True)
        made = subprocess.run([sys.executable, "-m", "venv", str(VENV)], check=False)
        if made.returncode != 0:
            # Debian and Ubuntu ship venv without ensurepip; a pip from
            # elsewhere can still install into a pip-less venv.
            shutil.rmtree(VENV, ignore_errors=True)
            subprocess.run([sys.executable, "-m", "venv", "--without-pip", str(VENV)], check=True)
    has_pip = subprocess.run([str(venv_python()), "-I", "-m", "pip", "--version"], capture_output=True, check=False).returncode == 0
    pip = [str(venv_python()), "-I", "-m", "pip"] if has_pip else [sys.executable, "-m", "pip", "--python", str(venv_python())]
    install = pip + ["install", "--no-deps", "--require-hashes", "--only-binary=:all:", "-r", str(REQUIREMENTS)]
    print("+ " + " ".join(install), flush=True)
    if subprocess.run(install, check=False).returncode != 0:
        print("installing the pinned oracle libraries failed", file=sys.stderr)
        return 1
    if fetch_ots:
        return setup_ots()
    return 0


def setup_ots() -> int:
    pin = json.loads(OTS_PIN.read_text(encoding="utf-8"))
    key = f"{platform.system()}-{platform.machine()}"
    asset = pin["assets"].get(key)
    if not asset:
        print(f"no pinned ots-sanitize build for {key}; reading cases will use fontTools", file=sys.stderr)
        return 0
    cache = ORACLE_DIR / ".cache"
    target = cache / asset["directory"] / "ots-sanitize"
    if target.exists():
        print(f"ots-sanitize {pin['version']} already in {rel(target)}")
        return 0
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / Path(asset["url"]).name
    print(f"fetching {asset['url']}")
    with urllib.request.urlopen(asset["url"], timeout=120) as response:
        archive.write_bytes(response.read())
    digest = sha256_file(archive)
    if digest != asset["sha256"]:
        archive.unlink()
        print(f"ots archive sha256 {digest} does not match the pin {asset['sha256']}", file=sys.stderr)
        return 1
    with zipfile.ZipFile(archive) as bundle:
        member = f"{asset['directory']}/ots-sanitize"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(bundle.read(member))
    target.chmod(0o755)
    archive.unlink()
    print(f"installed ots-sanitize {pin['version']} at {rel(target)}")
    return 0


def setup_chrome() -> int:
    """Install the pinned Puppeteer (and the Chrome build it pins) into
    tools/oracle/chrome/node_modules. The width cases' font is the corpus
    entry inter-4.1 (scripts/fetch_corpus.py fetch inter-4.1)."""
    npm = shutil.which("npm")
    if not npm:
        print("npm is not installed; width cases will be skipped", file=sys.stderr)
        return 1
    command = [npm, "ci", "--no-audit", "--no-fund", "--prefix", str(CHROME_DIR)]
    print("+ " + " ".join(command), flush=True)
    if subprocess.run(command, check=False).returncode != 0:
        print("installing the pinned Puppeteer failed", file=sys.stderr)
        return 1
    return 0


def oracle_versions() -> dict:
    if not venv_python().exists():
        raise SystemExit(f"no oracle environment at {rel(VENV)}; run: python3 scripts/record_oracle.py --setup")
    completed = subprocess.run([str(venv_python()), "-I", str(EXTRACT), "versions"], capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        raise SystemExit("oracle extractor failed:\n" + completed.stderr)
    info = json.loads(completed.stdout)
    pins = pinned_versions()
    wrong = [f"{name} {info['installed'].get(name)} (pinned {version})" for name, version in sorted(pins.items()) if info["installed"].get(name) != version]
    if wrong:
        raise SystemExit("installed oracle versions differ from tools/oracle/requirements.txt: " + ", ".join(wrong))
    ots = info["tools"]["read"].get("ots-sanitize")
    if ots is not None:
        pinned_ots = json.loads(OTS_PIN.read_text(encoding="utf-8"))["version"]
        if ots != pinned_ots:
            raise SystemExit(f"ots-sanitize {ots} differs from the pin {pinned_ots} in tools/oracle/ots.json")
    return info


def run_oracle(requests: list[dict]) -> list[dict]:
    if not requests:
        return []
    payload = "".join(json.dumps(r, sort_keys=True) + "\n" for r in requests)
    completed = subprocess.run(
        [str(venv_python()), "-I", str(EXTRACT), "run"], input=payload, capture_output=True, text=True, check=False, cwd=ROOT
    )
    if completed.returncode != 0:
        raise SystemExit("oracle extractor failed:\n" + completed.stderr)
    responses = [json.loads(line) for line in completed.stdout.splitlines() if line.strip()]
    if len(responses) != len(requests):
        raise SystemExit(f"oracle answered {len(responses)} of {len(requests)} requests:\n{completed.stderr}")
    return responses


def chrome_pin() -> dict:
    pin = json.loads(CHROME_PIN.read_text(encoding="utf-8"))
    return {"extractor": pin["extractor"], "tools": {"chrome": pin["chrome"], "puppeteer": pin["puppeteer"]}}


def chrome_unavailable() -> str | None:
    """Why width cases cannot be recorded here, or None when they can."""
    node = shutil.which("node")
    if not node:
        return "node is not installed"
    if not (CHROME_DIR / "node_modules" / "puppeteer").is_dir():
        return "Puppeteer is not installed (python3 scripts/record_oracle.py --setup-chrome)"
    completed = subprocess.run([node, str(CHROME_EXTRACT), "versions"], capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        return "the Chrome extractor failed: " + completed.stderr.strip()
    if json.loads(completed.stdout) != chrome_pin():
        return f"the Chrome extractor reports {completed.stdout.strip()}, not the pins in {rel(CHROME_PIN)}"
    return None


def run_chrome(requests: list[dict]) -> list[dict]:
    if not requests:
        return []
    payload = "".join(json.dumps(r, sort_keys=True) + "\n" for r in requests)
    completed = subprocess.run(
        [shutil.which("node") or "node", str(CHROME_EXTRACT), "run"], input=payload, capture_output=True, text=True, check=False, cwd=ROOT
    )
    if completed.returncode != 0:
        raise SystemExit("Chrome extractor failed:\n" + completed.stderr)
    responses = [json.loads(line) for line in completed.stdout.splitlines() if line.strip()]
    if len(responses) != len(requests):
        raise SystemExit(f"Chrome answered {len(responses)} of {len(requests)} requests:\n{completed.stderr}")
    return responses


def make_record(case: Case, key: str, font_sha: str, tools: dict, extractor: int, response: dict, location: dict | None) -> dict:
    record = {
        "detail": response["detail"],
        "font": rel(case.font_path),
        "font_sha256": font_sha,
        "id": case.id,
        "key": key,
        "kind": case.kind,
        "options": list(case.options),
        "provenance": {"backend": response["backend"], "extractor": extractor, "tools": tools},
        "result": response["result"],
        "status": response["status"],
        "unicodes": format_unicodes(parse_unicodes(case.unicodes)),
    }
    # Only cases that have them carry these, so older records keep their bytes.
    if case.glyphs is not None:
        record["glyphs"] = case.glyphs if isinstance(case.glyphs, str) else list(case.glyphs)
    if location is not None:
        record["location"] = location
    return record


def fill_expected(path: Path, results: dict[str, str]) -> int:
    """Write results (keyed by case id) into `"expected": "?"` fields;
    scripts/_common.py owns writing case files."""
    import _common

    return _common.fill_expected(path, results)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("cases", nargs="*", help="case files, or substrings of their paths under tests/cases")
    parser.add_argument("--setup", action="store_true", help="create the oracle venv, install the pins, fetch OTS")
    parser.add_argument("--no-ots", action="store_true", help="with --setup, do not fetch ots-sanitize")
    parser.add_argument("--setup-chrome", action="store_true", help="install the pinned Puppeteer and Chrome with npm")
    parser.add_argument("--force", action="store_true", help="re-record every selected case")
    parser.add_argument("--check", action="store_true", help="record nothing; fail if a record is missing or stale")
    parser.add_argument("--fill-expected", action="store_true", help="write results into expectations that are `?`")
    parser.add_argument(
        "--allow-fonttools-read",
        action="store_true",
        help="record reading cases with fontTools when ots-sanitize is absent (changes their keys)",
    )
    args = parser.parse_args()

    if args.setup:
        return setup(not args.no_ots)
    if args.setup_chrome:
        return setup_chrome()

    info = oracle_versions()
    if "ots-sanitize" not in info["tools"]["read"] and not (args.allow_fonttools_read or args.check):
        print(
            "ots-sanitize is not installed, so reading cases would be re-recorded with the fontTools fallback.\n"
            "Run `python3 scripts/record_oracle.py --setup`, or pass --allow-fonttools-read deliberately.",
            file=sys.stderr,
        )
        return 1
    extractor = info["extractor"]
    tools_for = info["tools"]
    chrome = chrome_pin()
    files = select_case_files(args.cases)
    if not files:
        print("no case files selected", file=sys.stderr)
        return 1

    font_hashes: dict[Path, str] = {}
    locations: dict[tuple[Path, int, str], dict | None] = {}
    plan: list[tuple[Path, dict, list]] = []  # (case file, kept records, pending work)
    requests: list[dict] = []
    width_requests: list[dict] = []
    chrome_missing: str | None = None
    chrome_checked = False
    problems: list[str] = []
    counts = {"cases": 0, "kept": 0, "recorded": 0, "font-missing": 0, "pruned": 0, "width-skipped": 0}
    for path in files:
        cases, file_problems = parse_case_file(path)
        problems += file_problems
        old = load_records_for(path)
        kept: dict[str, dict] = {}
        pending = []
        for case in cases:
            counts["cases"] += 1
            font = case.font_path
            if not font.is_file():
                counts["font-missing"] += 1
                if case.id in old:
                    kept[case.id] = old[case.id]
                continue
            if font not in font_hashes:
                font_hashes[font] = sha256_file(font)
            kind = case.kind
            if kind not in ORACLE_KINDS + CHROME_KINDS:
                problems.append(f"{case.id}: no oracle answers case kind {kind!r}")
                continue
            tools = chrome["tools"] if kind in CHROME_KINDS else tools_for[kind]
            case_extractor = chrome["extractor"] if kind in CHROME_KINDS else extractor[kind]
            location_key = (font, case.face, canonical_json(case.location), tuple(case.settings.get("variations", [])))
            if location_key not in locations:
                locations[location_key] = resolve_location(case, font.read_bytes())
            location = locations[location_key]
            key = record_key(case, font_hashes[font], tools, case_extractor, location)
            existing = old.get(case.id)
            if existing and existing["key"] == key and not args.force:
                kept[case.id] = existing
                counts["kept"] += 1
                continue
            if args.check:
                problems.append(f"{case.id}: record {'stale' if existing else 'missing'}")
                continue
            request = {"font": str(font), "kind": kind, "options": list(case.options), "unicodes": parse_unicodes(case.unicodes)}
            if location is not None:
                request["location"] = location
            if case.glyphs is not None:
                request["glyphs"] = case.glyphs if isinstance(case.glyphs, str) else list(case.glyphs)
            if kind in CHROME_KINDS:
                if not chrome_checked:
                    chrome_missing, chrome_checked = chrome_unavailable(), True
                if chrome_missing:
                    counts["width-skipped"] += 1
                    if existing:
                        kept[case.id] = existing
                    continue
                pending.append((case, key, font_hashes[font], tools, case_extractor, "width", len(width_requests), location))
                width_requests.append(request)
                continue
            pending.append((case, key, font_hashes[font], tools, case_extractor, "oracle", len(requests), location))
            requests.append(request)
        counts["pruned"] += len(set(old) - {c.id for c in cases})
        plan.append((path, kept, pending))

    if args.check:
        for problem in problems:
            print(problem)
        print(f"{counts['cases']} cases, {counts['kept']} records current, {len(problems)} problems, {counts['font-missing']} fonts missing")
        return 1 if problems else 0

    responses = run_oracle(requests)
    width_responses = run_chrome(width_requests)
    answers = {"oracle": responses, "width": width_responses}
    changed_files = 0
    expectation_errors = []
    for path, kept, pending in plan:
        records = dict(kept)
        fills: dict[str, str] = {}
        for case, key, font_sha, tools, case_extractor, source, index, location in pending:
            records[case.id] = make_record(case, key, font_sha, tools, case_extractor, answers[source][index], location)
            counts["recorded"] += 1
        cases, _ = parse_case_file(path)
        for case in cases:
            record = records.get(case.id)
            if not record or record["status"] != "ok":
                continue
            expected = case.expected.strip()
            if expected == "?":
                fills[case.id] = record["result"]
            elif expected != "*" and not has_glyph_names(expected) and expected != record["result"]:
                expectation_errors.append(f"{case.rel_file}:{case.line} ({case.id}): expected {expected} but the oracle gives {record['result']}")
        if write_records_for(path, records.values()):
            changed_files += 1
        if args.fill_expected and fills:
            print(f"{rel(path)}: filled {fill_expected(path, fills)} expectations")

    for problem in problems + expectation_errors:
        print(problem)
    unsupported = sum(1 for r in responses + width_responses if r["status"] == "unsupported")
    errors = sum(1 for r in responses + width_responses if r["status"] == "error")
    print(
        f"{counts['cases']} cases: {counts['kept']} kept, {counts['recorded']} recorded "
        f"({unsupported} unsupported by the oracle, {errors} errors), {counts['font-missing']} fonts missing, "
        f"{counts['pruned']} records pruned, {changed_files} record files changed"
    )
    tools_text = ", ".join(f"{k} {v}" for kind in ("shape", "read") for k, v in sorted(tools_for[kind].items()))
    versions_text = ", ".join(f"{kind} {v}" for kind, v in sorted(extractor.items()))
    print(f"oracle: extractor {versions_text}; {tools_text}")
    if width_requests or counts["width-skipped"]:
        chrome_text = ", ".join(f"{k} {v}" for k, v in sorted(chrome["tools"].items()))
        print(f"width oracle: extractor {chrome['extractor']}; {chrome_text}")
    if counts["width-skipped"]:
        print(f"{counts['width-skipped']} width cases skipped: {chrome_missing}")
    return 1 if problems or expectation_errors else 0


if __name__ == "__main__":
    sys.exit(main())
