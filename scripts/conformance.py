#!/usr/bin/env python3
"""Compare roc-font with recorded oracle results (architecture §7.1).

Builds the native driver (tools/driver/main.roc) when its sources or the
package changed, runs every selected case file through it in one process,
and compares each result with the case's record in tests/oracle/records/ by
string equality. No oracle needs to be installed.

Outcomes per case:

    agree           the driver's result equals the record
    known           differs, and tests/known-failures.json lists the case
    FAIL            differs and is not listed
    STALE           listed in known-failures.json but now agrees (remove it)
    MISSING-RECORD  no record, or the record's key no longer matches the case
                    or font (run scripts/record_oracle.py)
    MISSING-FONT    a font inside the repository is missing
    BAD-EXPECTATION the case's own glyph-id expectation differs from its record
    unsupported     the driver or the oracle cannot honour an option yet
    skipped         the font is in tests/corpus/ and has not been fetched, or is
                    an absolute system font path that does not exist here

The run fails on FAIL, STALE, MISSING-RECORD, MISSING-FONT and BAD-EXPECTATION, and on
known-failures entries naming cases that do not exist; `--strict` also fails
on unsupported cases. The script never edits tests/known-failures.json.

    python3 scripts/conformance.py                 # every case file
    python3 scripts/conformance.py inter reading   # case files matching these
    python3 scripts/conformance.py --diff          # show expected and actual
    python3 scripts/conformance.py --interpreter   # run the driver with --opt=interpreter
    python3 scripts/conformance.py --explain       # add the reader's problems to differences

Standard library only. The compiler is $ROC, or `roc` on PATH.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import (  # noqa: E402
    DRIVER_DIR,
    ROOT,
    TMP_ROOT,
    case_files,
    has_glyph_names,
    is_corpus_font,
    load_known_failures,
    load_records,
    parse_case_file,
    record_key,
    rel,
    roc_command,
    roc_version,
    sha256_file,
)

DRIVER_BIN = TMP_ROOT / "conformance" / "driver"
FAILING = ("FAIL", "STALE", "MISSING-RECORD", "MISSING-FONT", "BAD-EXPECTATION")


def driver_sources() -> list[Path]:
    return sorted(DRIVER_DIR.glob("*.roc")) + sorted((ROOT / "package").glob("*.roc"))


def reported_problems(output: str) -> tuple[list[str], list[str]]:
    """Files roc reported problems in, and those outside the cached platform.

    Some nightlies report problems inside the cached basic-cli platform and
    exit non-zero although the binary is built (or the interpreter ran).
    That is accepted; a problem reported in this repository's files never is.
    """
    located = re.findall(r"^── [✗●] .*? ─+ (\S+?):\d+:\d+", output, flags=re.MULTILINE)
    return located, [path for path in located if "/.cache/roc/packages/" not in path]


def build_driver(roc: str, force: bool) -> int:
    if not force and DRIVER_BIN.exists():
        built = DRIVER_BIN.stat().st_mtime
        if all(p.stat().st_mtime <= built for p in driver_sources()):
            return 0
    DRIVER_BIN.parent.mkdir(parents=True, exist_ok=True)
    if DRIVER_BIN.exists():
        DRIVER_BIN.unlink()
    command = [roc, "build", str(DRIVER_DIR / "main.roc"), f"--output={DRIVER_BIN}"]
    print("+ " + " ".join(command), flush=True)
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    output = completed.stdout + completed.stderr
    located, ours = reported_problems(output)
    if not DRIVER_BIN.exists() or ours or (completed.returncode != 0 and not located):
        print(output)
        print("building the driver failed", file=sys.stderr)
        return completed.returncode or 1
    if completed.returncode != 0:
        print(f"  note: roc exited {completed.returncode} for {len(located)} problems reported inside the cached platform; the driver was built")
    return 0


def run_driver(command_prefix: list[str], files: list[Path], explain: bool) -> tuple[dict[tuple[str, int], str], dict[tuple[str, int], str]]:
    command = command_prefix + (["--explain"] if explain else []) + [rel(p) for p in files]
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    located, ours = reported_problems(completed.stderr)
    if completed.returncode != 0 and (ours or not located):
        print(completed.stdout[-2000:] + completed.stderr[-2000:])
        raise SystemExit(f"driver exited with {completed.returncode}")
    results: dict[tuple[str, int], str] = {}
    explanations: dict[tuple[str, int], str] = {}
    for line in completed.stdout.splitlines():
        where, sep, rest = line.partition("\t")
        if not sep:
            continue  # interpreter chatter, never a result line
        result, _, why = rest.partition("\t")
        file, _, number = where.rpartition(":")
        if number.isdigit():
            results[(file, int(number))] = result
            if why:
                explanations[(file, int(number))] = why
    return results, explanations


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("cases", nargs="*", help="case files, or substrings of their paths under tests/cases")
    parser.add_argument("--diff", action="store_true", help="print expected and actual for every difference")
    parser.add_argument("--verbose", action="store_true", help="also list known failures and unsupported cases")
    parser.add_argument("--strict", action="store_true", help="fail on unsupported cases too")
    parser.add_argument("--rebuild", action="store_true", help="rebuild the driver even if it looks current")
    parser.add_argument("--no-build", action="store_true", help="use the existing driver binary")
    parser.add_argument("--interpreter", action="store_true", help="run the driver with `roc --opt=interpreter`")
    parser.add_argument("--explain", action="store_true", help="show the reader's problems for rejected fonts")
    args = parser.parse_args()

    roc = roc_command()
    if args.interpreter:
        prefix = [roc, str(DRIVER_DIR / "main.roc"), "--opt=interpreter", "--"]
    else:
        if not args.no_build and build_driver(roc, args.rebuild) != 0:
            return 1
        prefix = [str(DRIVER_BIN)]

    files = case_files(args.cases)
    if not files:
        print("no case files selected", file=sys.stderr)
        return 1
    known = {entry["id"]: entry["reason"] for entry in load_known_failures()}

    cases = []
    problems = []
    for path in files:
        parsed, file_problems = parse_case_file(path)
        cases += parsed
        problems += file_problems
    results, explanations = run_driver(prefix, files, args.explain)

    outcomes: list[tuple[str, object, str]] = []  # (outcome, case, note)
    font_hashes: dict[Path, str] = {}
    records_by_file = {path.resolve(): load_records(path) for path in files}
    for case in cases:
        font = case.font_path
        if not font.is_file():
            if is_corpus_font(font):
                outcomes.append(("skipped", case, "font not fetched (scripts/fetch_corpus.py)"))
            elif case.font.startswith("/"):
                outcomes.append(("skipped", case, "system font not installed"))
            else:
                outcomes.append(("MISSING-FONT", case, f"no font at {rel(font)}"))
            continue
        record = records_by_file[case.file].get(case.id)
        actual = results.get((case.rel_file, case.line), "error:no-driver-output")
        if record is None:
            outcomes.append(("MISSING-RECORD", case, "no record"))
            continue
        if font.is_file():
            if font not in font_hashes:
                font_hashes[font] = sha256_file(font)
            provenance = record["provenance"]
            if record["key"] != record_key(case, font_hashes[font], provenance["tools"], provenance["extractor"]):
                outcomes.append(("MISSING-RECORD", case, "record key is stale (case or font changed)"))
                continue
        if record["status"] != "ok":
            outcomes.append(("unsupported", case, f"oracle: {record['detail']}"))
            continue
        expected = record["result"]
        written = case.expected.strip()
        if written not in ("*", "?") and not has_glyph_names(written) and written != expected:
            outcomes.append(("BAD-EXPECTATION", case, f"case says {written}, record says {expected}"))
            continue
        if actual.startswith("unsupported:"):
            outcomes.append(("unsupported", case, f"driver: {actual}"))
            continue
        agrees = actual == expected
        if case.id in known:
            outcomes.append(("STALE" if agrees else "known", case, known[case.id]))
        else:
            outcomes.append(("agree" if agrees else "FAIL", case, ""))
        if not agrees:
            why = explanations.get((case.rel_file, case.line))
            extra = f"\n    expected {expected}\n    actual   {actual}" + (f"\n    reader   {why}" if why else "")
            outcomes[-1] = outcomes[-1][:2] + (outcomes[-1][2] + extra,)

    selected_ids = {c.id for c in cases}
    selected_stems = {c.id.rsplit("/", 1)[0] for c in cases}
    unknown = sorted(i for i in known if i.rsplit("/", 1)[0] in selected_stems and i not in selected_ids)
    if not args.cases:
        unknown = sorted(i for i in known if i not in selected_ids)

    counts = Counter(outcome for outcome, _, _ in outcomes)
    for outcome, case, note in outcomes:
        show = outcome in FAILING or (args.verbose and outcome in ("known", "unsupported", "skipped"))
        if show:
            first, _, rest = note.partition("\n")
            print(f"{outcome:15} {case.id}  ({case.rel_file}:{case.line}) {first}")
            if rest and (args.diff or outcome == "FAIL"):
                print(rest)
    for case_id in unknown:
        print(f"{'STALE':15} {case_id}  listed in tests/known-failures.json but no such case")
    for problem in problems:
        print(f"{'FORMAT':15} {problem}")

    order = ["agree", "known", "FAIL", "STALE", "MISSING-RECORD", "MISSING-FONT", "BAD-EXPECTATION", "unsupported", "skipped"]
    summary = ", ".join(f"{counts.get(name, 0)} {name.lower()}" for name in order)
    print(f"{len(cases)} cases in {len(files)} files: {summary}; {len(unknown)} unknown known-failure ids")
    print(f"driver: {'interpreter' if args.interpreter else rel(DRIVER_BIN)}; roc: {roc_version(roc)}")
    failed = any(counts.get(name) for name in FAILING) or unknown or problems
    if args.strict and counts.get("unsupported"):
        failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
