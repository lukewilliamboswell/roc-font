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

The oracle runs in tools/oracle/.venv under `python -I` (tools/oracle/extract.py);
this script itself needs only the standard library. A case whose expected
column is written in glyph-id notation must agree with its record; `*` and
`?` expectations, and HarfBuzz expectations that use glyph names, are not
compared.
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
    ORACLE_DIR,
    ROOT,
    Case,
    case_files,
    format_unicodes,
    has_glyph_names,
    load_records,
    parse_case_file,
    parse_unicodes,
    record_key,
    rel,
    sha256_file,
    write_records,
)

VENV = Path(os.environ.get("ROC_FONT_ORACLE_VENV", ORACLE_DIR / ".venv"))
REQUIREMENTS = ORACLE_DIR / "requirements.txt"
OTS_PIN = ORACLE_DIR / "ots.json"
EXTRACT = ORACLE_DIR / "extract.py"


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


# ------------------------------------------------------------------- oracle


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


def make_record(case: Case, key: str, font_sha: str, tools: dict, extractor: int, response: dict) -> dict:
    return {
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


def fill_expected(path: Path, results: dict[int, str]) -> int:
    lines = path.read_text(encoding="utf-8").split("\n")
    changed = 0
    for number, result in results.items():
        fields = lines[number - 1].split(";")
        if len(fields) == 4 and fields[3].strip() == "?":
            fields[3] = result
            lines[number - 1] = ";".join(fields)
            changed += 1
    if changed:
        path.write_text("\n".join(lines), encoding="utf-8")
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("cases", nargs="*", help="case files, or substrings of their paths under tests/cases")
    parser.add_argument("--setup", action="store_true", help="create the oracle venv, install the pins, fetch OTS")
    parser.add_argument("--no-ots", action="store_true", help="with --setup, do not fetch ots-sanitize")
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
    files = case_files(args.cases)
    if not files:
        print("no case files selected", file=sys.stderr)
        return 1

    font_hashes: dict[Path, str] = {}
    plan: list[tuple[Path, dict, list]] = []  # (case file, kept records, pending work)
    requests: list[dict] = []
    problems: list[str] = []
    counts = {"cases": 0, "kept": 0, "recorded": 0, "font-missing": 0, "pruned": 0}
    for path in files:
        cases, file_problems = parse_case_file(path)
        problems += file_problems
        old = load_records(path)
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
            tools = tools_for[case.kind]
            key = record_key(case, font_hashes[font], tools, extractor)
            existing = old.get(case.id)
            if existing and existing["key"] == key and not args.force:
                kept[case.id] = existing
                counts["kept"] += 1
                continue
            if args.check:
                problems.append(f"{case.id}: record {'stale' if existing else 'missing'}")
                continue
            pending.append((case, key, font_hashes[font], tools, len(requests)))
            requests.append({"font": str(font), "kind": case.kind, "options": list(case.options), "unicodes": parse_unicodes(case.unicodes)})
        counts["pruned"] += len(set(old) - {c.id for c in cases})
        plan.append((path, kept, pending))

    if args.check:
        for problem in problems:
            print(problem)
        print(f"{counts['cases']} cases, {counts['kept']} records current, {len(problems)} problems, {counts['font-missing']} fonts missing")
        return 1 if problems else 0

    responses = run_oracle(requests)
    changed_files = 0
    expectation_errors = []
    for path, kept, pending in plan:
        records = dict(kept)
        fills: dict[int, str] = {}
        for case, key, font_sha, tools, index in pending:
            records[case.id] = make_record(case, key, font_sha, tools, extractor, responses[index])
            counts["recorded"] += 1
        cases, _ = parse_case_file(path)
        for case in cases:
            record = records.get(case.id)
            if not record or record["status"] != "ok":
                continue
            expected = case.expected.strip()
            if expected == "?":
                fills[case.line] = record["result"]
            elif expected != "*" and not has_glyph_names(expected) and expected != record["result"]:
                expectation_errors.append(f"{case.rel_file}:{case.line} ({case.id}): expected {expected} but the oracle gives {record['result']}")
        if write_records(path, records.values()):
            changed_files += 1
        if args.fill_expected and fills:
            print(f"{rel(path)}: filled {fill_expected(path, fills)} expectations")

    for problem in problems + expectation_errors:
        print(problem)
    unsupported = sum(1 for r in responses if r["status"] == "unsupported")
    errors = sum(1 for r in responses if r["status"] == "error")
    print(
        f"{counts['cases']} cases: {counts['kept']} kept, {counts['recorded']} recorded "
        f"({unsupported} unsupported by the oracle, {errors} errors), {counts['font-missing']} fonts missing, "
        f"{counts['pruned']} records pruned, {changed_files} record files changed"
    )
    tools_text = ", ".join(f"{k} {v}" for kind in ("shape", "read") for k, v in sorted(tools_for[kind].items()))
    print(f"oracle: extractor {extractor}; {tools_text}")
    return 1 if problems or expectation_errors else 0


if __name__ == "__main__":
    sys.exit(main())
