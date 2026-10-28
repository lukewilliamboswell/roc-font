#!/usr/bin/env python3
"""Compare roc-font with recorded oracle results (architecture §7.1).

Builds the native driver (tools/driver/main.roc) against the package bundle
`roc bundle` makes, served on loopback (scripts/flight.py), when the driver
or the bundle changed (`--source` compiles package/ directly instead, for
quick local iteration only), parses the selected JSONC case files (scripts/_common.py),
streams every runnable case to the driver in one process over its line
protocol, and compares each result with the case's record in
tests/oracle/records/ by string equality. No oracle needs to be installed.
Options the driver cannot honour are answered here as `unsupported:<option>`
without being sent.

Case files are *gating* unless tests/scores.json declares them *scored* (by
a path prefix under tests/cases, such as `harfbuzz/` for the full HarfBuzz
import or `hb-pending/` for curated cases a later milestone will make
pass). Outcomes per gating case:

    agree           the driver's result equals the record (a width on a
                    variable font: within half a unit per glyph of Chrome's)
    known           differs, and tests/known-failures.json lists the case
    FAIL            differs and is not listed
    STALE           listed in known-failures.json but now agrees (remove it)
    MISSING-RECORD  no record, or the record's key no longer matches the case
                    or font (run scripts/record_oracle.py)
    MISSING-FONT    a font inside the repository is missing
    FONT-CHANGED    the font's SHA-256 differs from the case's `font_sha256` pin
    BAD-EXPECTATION the case's own glyph-id expectation differs from its record
    unsupported     the driver or the oracle cannot honour an option yet
    skipped         the font is in tests/corpus/ and has not been fetched, or is
                    an absolute system font path that does not exist here

Scored cases count as agree, differ, unsupported or skipped per suite (the
first two path components of the case file, such as `harfbuzz/in-house` or
`hb-pending/M4`); differences there never need a known-failures entry, and
an entry naming a scored case is an error. MISSING-RECORD, MISSING-FONT,
FONT-CHANGED and BAD-EXPECTATION fail in scored suites too. Each fully selected suite is
compared with its line in tests/scores.json, a ratchet like the allocation
baseline:

    SCORE-DROP      fewer cases agree than recorded: fails
    SCORE-CHANGED   more agree, or the same number but a different set, or
                    other counts moved: fails until `--update-scores`
    SCORE-NEW       a suite with no recorded score: fails until recorded
    SUITE-CHANGED   the suite's cases differ from the recorded ones (a
                    different import): fails until recorded

A scored suite declared in scores.json with no case files here (the HarfBuzz
import is local and git-ignored) is skipped with a note, never a failure, and
so is a suite whose skipped count differs from the recorded one (fonts not
fetched, or system fonts present). `--update-scores` records every fully run
suite and prints what changed.

The run fails on FAIL, STALE, MISSING-RECORD, MISSING-FONT, FONT-CHANGED,
BAD-EXPECTATION and the SCORE-/SUITE- outcomes, and on known-failures entries naming cases
that do not exist; `--strict` also fails on unsupported gating cases. The
script never edits tests/known-failures.json.

    python3 scripts/conformance.py                 # every case file
    python3 scripts/conformance.py inter reading   # case files matching these
    python3 scripts/conformance.py --diff          # show expected and actual
    python3 scripts/conformance.py --explain       # add the reader's problems to differences
    python3 scripts/conformance.py --update-scores # record scored suites' counts
    python3 scripts/conformance.py --json out.json # every case's outcome, for triage

Standard library only. The compiler is $ROC, or `roc` on PATH.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import flight  # noqa: E402
from _common import (  # noqa: E402
    CASES_DIR,
    DRIVER_DIR,
    ROOT,
    TMP_ROOT,
    case_files,
    driver_request,
    has_glyph_names,
    is_corpus_font,
    load_known_failures,
    load_records,
    parse_case_file,
    canonical_json,
    record_key,
    rel,
    resolve_location,
    roc_command,
    roc_version,
    sha256_bytes,
    sha256_file,
)

DRIVER_BIN = TMP_ROOT / "conformance" / "driver"
# The package the driver was built against: the bundle's name, or `source`.
DRIVER_PACKAGE = TMP_ROOT / "conformance" / "driver.package"
# Proven external matrices share this optimized driver, avoiding one
# identical native build per script while retaining exact comparisons.
EXTERNAL_CASES = (
    ROOT / "tests/fonts/complex/indic-cases.jsonc",
    ROOT / "tests/fonts/complex/khmer-cases.jsonc",
    ROOT / "tests/fonts/complex/vowel-cases.jsonc",
    ROOT / "tests/fonts/shaping/indic-wide/cases.jsonc",
    ROOT / "tests/fonts/complex/long-cases.jsonc",
    ROOT / "tests/fonts/shaping/myanmar/myanmar.jsonc",
    ROOT / "tests/fonts/shaping/tibetan/tibetan-cases.jsonc",
    ROOT / "tests/fonts/shaping/use-sinhala/sinhala-cases.jsonc",
    ROOT / "tests/fonts/shaping/use-joining/joining-cases.jsonc",
    ROOT / "tests/fonts/shaping/arabic-extra/extra-cases.jsonc",
    ROOT / "tests/fonts/shaping/arabic-fallback/fallback-cases.jsonc",
    ROOT / "tests/fonts/shaping/arabic-fallback/windows-cases.jsonc",
    ROOT / "tests/fonts/shaping/arabic-stretch/stretch-cases.jsonc",
    ROOT / "tests/fonts/shaping/fallback-marks/mark-cases.jsonc",
    ROOT / "tests/fonts/shaping/thai-legacy/long-cases.jsonc",
    ROOT / "tests/fonts/positioning/attachment-caps/attachment-cases.jsonc",
)
SCORES = ROOT / "tests" / "scores.json"
SCORES_ABOUT = (
    "Scored conformance suites (architecture §7.1). `scored` lists path prefixes under tests/cases whose case files are scored "
    "rather than gating; `suites` holds each suite's counts, written only by `scripts/conformance.py --update-scores`. "
    "agree_ids and case_ids are digests of the agreeing and of all case ids, so a changed set is caught at equal counts."
)
FAILING = ("FAIL", "STALE", "MISSING-RECORD", "MISSING-FONT", "FONT-CHANGED", "BAD-EXPECTATION")


def driver_sources(dep: list[str]) -> list[Path]:
    package = [] if dep else sorted((ROOT / "package").glob("*.roc"))
    return sorted(DRIVER_DIR.glob("*.roc")) + package


def reported_problems(output: str, package: str = "source") -> tuple[list[str], list[str]]:
    """Files roc reported problems in, and those outside the cached platform.

    Problems inside the cached basic-cli platform are identified separately
    for diagnostics. A native build must still exit successfully; neither
    platform errors nor errors in the bundle are accepted.
    """
    located = re.findall(r"^── [✗●] .*? ─+ (\S+?):\d+:\d+", output, flags=re.MULTILINE)
    bundle = package.removesuffix(".tar.zst")
    return located, [path for path in located
                     if "/.cache/roc/packages/" not in path or (package != "source" and bundle in path)]


def build_driver(roc: str, force: bool, dep: list[str]) -> int:
    """Build the driver against `dep` (flight.replace_dep arguments, or
    none for package/ sources) unless the binary is current."""
    package = dep[-1].rsplit("/", 1)[-1] if dep else "source"
    identity = package + " opt=speed"
    if not force and DRIVER_BIN.exists() and DRIVER_PACKAGE.is_file():
        built = DRIVER_BIN.stat().st_mtime
        if (DRIVER_PACKAGE.read_text(encoding="utf-8") == identity
                and all(p.stat().st_mtime <= built for p in driver_sources(dep))):
            return 0
    DRIVER_BIN.parent.mkdir(parents=True, exist_ok=True)
    for stale in (DRIVER_BIN, DRIVER_PACKAGE):
        if stale.exists():
            stale.unlink()
    command = [roc, "build", "--opt=speed", str(DRIVER_DIR / "main.roc"), f"--output={DRIVER_BIN}", *dep]
    print("+ " + " ".join(command), flush=True)
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    output = completed.stdout + completed.stderr
    located, ours = reported_problems(output, package)
    if not DRIVER_BIN.exists() or ours or completed.returncode != 0:
        print(output)
        print("building the driver failed", file=sys.stderr)
        return completed.returncode or 1
    DRIVER_PACKAGE.write_text(identity, encoding="utf-8")
    return 0


class Locations:
    """resolve_location per (font, face, location fields), each font read once."""

    def __init__(self) -> None:
        self.cache: dict[tuple, dict | None] = {}

    def of(self, case) -> dict | None:
        key = (case.font_path, case.face, canonical_json(case.location), tuple(case.settings.get("variations", [])))
        if key not in self.cache:
            self.cache[key] = resolve_location(case, case.font_path.read_bytes())
        return self.cache[key]


def width_tolerance(case, record: dict) -> float:
    """How far a width may be from Chrome's and still agree. Exact for a
    static font. At a variable font's location Chrome keeps each glyph's
    advance to 1/64 unit while HarfBuzz (and roc-font) round each to an
    integer, so the two agree within half a unit per glyph; the code point
    count stands for the glyph count (ligatures only lower it)."""
    location = record.get("location")
    if case.kind != "width" or not location or not location.get("axes"):
        return 0.0
    return len(case.scalars) / 2


def results_agree(case, record: dict, actual: str) -> bool:
    expected = record["result"]
    if actual == expected:
        return True
    tolerance = width_tolerance(case, record)
    if tolerance and expected.startswith("width:") and actual.startswith("width:"):
        try:
            return abs(float(actual[6:]) - float(expected[6:])) <= tolerance
        except ValueError:
            return False
    return False


def run_driver(command_prefix: list[str], cases: list, explain: bool, locations: Locations, guesses: dict[str, dict]) -> tuple[dict[str, str], dict[str, str], dict]:
    """Send every runnable case to the driver in one process (the line
    protocol of tools/driver/Case.roc, written by _common.driver_request).
    `guesses` holds each case's oracle record `detail` (the script and
    direction HarfBuzz guessed), which imported HarfBuzz cases shape with.
    Returns results and explanations by case id, and timing figures. A case
    the driver cannot honour gets `unsupported:<option>` without being sent."""
    results: dict[str, str] = {}
    explanations: dict[str, str] = {}
    lines = []
    for case in cases:
        if not case.font_path.is_file():
            continue
        line, unsupported = driver_request(case, str(case.font_path), locations.of(case), guess=guesses.get(case.id))
        if line is None:
            results[case.id] = f"unsupported:{unsupported}"
        else:
            lines.append(line)
    command = command_prefix + (["--explain"] if explain else [])
    started = time.perf_counter()
    completed = subprocess.run(command, cwd=ROOT, input="".join(l + "\n" for l in lines), capture_output=True, text=True, check=False)
    elapsed = time.perf_counter() - started
    located, ours = reported_problems(completed.stderr)
    if completed.returncode != 0 and (ours or not located):
        print(completed.stdout[-2000:] + completed.stderr[-2000:])
        raise SystemExit(f"driver exited with {completed.returncode}")
    answered = 0
    for out in completed.stdout.splitlines():
        tag, sep, rest = out.partition("\t")
        if not sep:
            continue  # compiler chatter, never a result line
        result, _, why = rest.partition("\t")
        results[tag] = result
        answered += 1
        if why:
            explanations[tag] = why
    return results, explanations, {"requests": len(lines), "answered": answered, "seconds": elapsed}


# ------------------------------------------------------------------ scoring


def load_scores() -> dict:
    if not SCORES.exists():
        return {"about": SCORES_ABOUT, "schema": 1, "scored": [], "suites": {}}
    data = json.loads(SCORES.read_text(encoding="utf-8"))
    if data.get("schema") != 1:
        raise SystemExit(f"{rel(SCORES)}: unknown schema {data.get('schema')!r}")
    for prefix in data.get("scored", []):
        if not prefix.endswith("/") or prefix.startswith("/"):
            raise SystemExit(f"{rel(SCORES)}: scored prefix {prefix!r} must be a directory under tests/cases ending in '/'")
    return data


def write_scores(data: dict) -> None:
    data["suites"] = {name: data["suites"][name] for name in sorted(data["suites"])}
    SCORES.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def suite_of(path: Path, prefixes: list[str]) -> str | None:
    """The scored suite a case file belongs to, or None when it gates: the
    prefix's directory plus one more path component, without `.jsonc`."""
    stem = path.resolve().relative_to(CASES_DIR).with_suffix("").as_posix()
    for prefix in prefixes:
        if stem.startswith(prefix):
            depth = prefix.rstrip("/").count("/") + 2
            return "/".join(stem.split("/")[:depth])
    return None


def ids_digest(ids: list[str]) -> str:
    return sha256_bytes("\n".join(sorted(ids)).encode("utf-8"))[:16]


def score_line(name: str, score: dict) -> str:
    return (
        f"{name}: {score['cases']} cases, {score['agree']} agree, {score['differ']} differ, "
        f"{score['unsupported']} unsupported, {score['skipped']} skipped"
    )


# --------------------------------------------------------------------- main


def classify(case, record, actual: str, font_hashes: dict[Path, str], locations: Locations) -> tuple[str, str]:
    """Outcome before known-failures are applied: one of agree, differ,
    unsupported, skipped, MISSING-RECORD, MISSING-FONT, BAD-EXPECTATION."""
    font = case.font_path
    if not font.is_file():
        if is_corpus_font(font):
            return "skipped", "font not fetched (scripts/fetch_corpus.py)"
        if case.font.startswith("/"):
            return "skipped", "system font not installed"
        return "MISSING-FONT", f"no font at {rel(font)}"
    if font not in font_hashes:
        font_hashes[font] = sha256_file(font)
    if case.font_sha256 and case.font_sha256 != font_hashes[font]:
        return "FONT-CHANGED", f"{rel(font)} has sha256 {font_hashes[font]}, the case pins {case.font_sha256}"
    if record is None:
        return "MISSING-RECORD", "no record"
    provenance = record["provenance"]
    if record["key"] != record_key(case, font_hashes[font], provenance["tools"], provenance["extractor"], locations.of(case)):
        return "MISSING-RECORD", "record key is stale (case or font changed)"
    if record["status"] != "ok":
        return "unsupported", f"oracle: {record['detail']}"
    expected = record["result"]
    written = case.expected.strip()
    if written not in ("*", "?") and not has_glyph_names(written) and written != expected:
        return "BAD-EXPECTATION", f"case says {written}, record says {expected}"
    if actual.startswith("unsupported:"):
        return "unsupported", f"driver: {actual}"
    return ("agree", "") if results_agree(case, record, actual) else ("differ", "")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("cases", nargs="*", help="case files, or substrings of their paths under tests/cases")
    parser.add_argument("--diff", action="store_true", help="print expected and actual for every difference")
    parser.add_argument("--verbose", action="store_true", help="also list known failures and unsupported gating cases")
    parser.add_argument("--strict", action="store_true", help="fail on unsupported gating cases too")
    parser.add_argument("--rebuild", action="store_true", help="rebuild the driver even if it looks current")
    parser.add_argument("--no-build", action="store_true", help="use the existing driver binary")
    parser.add_argument("--source", action="store_true",
                        help="build the driver from package/ sources instead of the served bundle (quick local iteration)")
    parser.add_argument("--explain", action="store_true", help="show the reader's problems for rejected fonts")
    parser.add_argument("--update-scores", action="store_true", help="record the counts of every fully run scored suite")
    parser.add_argument("--json", type=Path, help="write every case's outcome, expected and actual result to this file")
    args = parser.parse_args()

    roc = roc_command()
    if not args.no_build:
        with flight.flight(roc, source=args.source) as dep:
            if build_driver(roc, args.rebuild, dep) != 0:
                return 1
    prefix = [str(DRIVER_BIN)]

    files = case_files(args.cases)
    for path in EXTERNAL_CASES:
        if not args.cases or any(selector in str(path.relative_to(ROOT)) or Path(selector).resolve() == path.resolve() for selector in args.cases):
            files.append(path)
    for selector in args.cases:
        path = Path(selector)
        if path.is_file() and path.suffix == ".jsonc":
            files.append(path.resolve())
    files = sorted({p.resolve() for p in files})
    if not files:
        print("no case files selected", file=sys.stderr)
        return 1
    known = {entry["id"]: entry["reason"] for entry in load_known_failures()}
    scores = load_scores()
    prefixes = list(scores.get("scored", []))
    every_file_suite = {path.resolve(): suite_of(path, prefixes) for path in case_files()}

    cases = []
    problems = []
    for path in files:
        parsed, file_problems = parse_case_file(path)
        cases += parsed
        problems += file_problems
    ids = [case.id for case in cases]
    if len(ids) != len(set(ids)):
        print("duplicate case IDs across selected files; use distinct case-file basenames", file=sys.stderr)
        return 1
    locations = Locations()
    records_by_file = {path.resolve(): load_records(path) for path in files}
    guesses = {}
    for case in cases:
        record = records_by_file[case.file].get(case.id)
        if record is not None and record.get("status") == "ok" and isinstance(record.get("detail"), dict):
            guesses[case.id] = record["detail"]
    results, explanations, timing = run_driver(prefix, cases, args.explain, locations, guesses)

    outcomes: list[tuple[str, object, str]] = []  # gating: (outcome, case, note)
    scored: dict[str, Counter] = {}
    scored_ids: dict[str, dict[str, list[str]]] = {}
    scored_failures: list[tuple[str, object, str]] = []
    dump = []
    font_hashes: dict[Path, str] = {}
    for case in cases:
        record = records_by_file[case.file].get(case.id)
        actual = results.get(case.id, "error:no-driver-output")
        outcome, note = classify(case, record, actual, font_hashes, locations)
        suite = every_file_suite.get(case.file)
        if outcome == "differ":
            why = explanations.get(case.id)
            note = f"\n    expected {record['result']}\n    actual   {actual}" + (f"\n    reader   {why}" if why else "")
        if suite is not None:
            if outcome in FAILING:
                scored_failures.append((outcome, case, note))
            scored.setdefault(suite, Counter())[outcome] += 1
            scored_ids.setdefault(suite, {}).setdefault(outcome, []).append(case.id)
        elif outcome in ("agree", "differ"):
            agrees = outcome == "agree"
            if case.id in known:
                outcomes.append(("STALE" if agrees else "known", case, known[case.id] + ("" if agrees else note)))
            else:
                outcomes.append(("agree" if agrees else "FAIL", case, note))
        else:
            outcomes.append((outcome, case, note))
        if args.json:
            dump.append({
                "id": case.id,
                "file": case.rel_file,
                "line": case.line,
                "suite": suite,
                "outcome": outcome,
                "note": note.strip().split("\n")[0] if outcome != "differ" else "",
                "expected": record["result"] if record else None,
                "actual": actual,
            })

    gating_ids = {c.id for c in cases if every_file_suite.get(c.file) is None}
    scored_case_ids = {c.id for c in cases if every_file_suite.get(c.file) is not None}
    selected_stems = {c.id.rsplit("/", 1)[0] for c in cases}
    unknown = sorted(i for i in known if i.rsplit("/", 1)[0] in selected_stems and i not in gating_ids | scored_case_ids)
    if not args.cases:
        unknown = sorted(i for i in known if i not in gating_ids and i not in scored_case_ids)
    listed_scored = sorted(i for i in known if i in scored_case_ids)

    counts = Counter(outcome for outcome, _, _ in outcomes)
    for outcome, case, note in outcomes + scored_failures:
        show = outcome in FAILING or (args.verbose and outcome in ("known", "unsupported", "skipped"))
        if show:
            first, _, rest = note.partition("\n")
            print(f"{outcome:15} {case.id}  ({case.rel_file}:{case.line}) {first}")
            if rest and (args.diff or outcome == "FAIL"):
                print(rest)
    for case_id in unknown:
        print(f"{'STALE':15} {case_id}  listed in tests/known-failures.json but no such case")
    for case_id in listed_scored:
        print(f"{'STALE':15} {case_id}  listed in tests/known-failures.json but the case is scored; scored cases need no entry")
    for problem in problems:
        print(f"{'FORMAT':15} {problem}")

    score_failures, notes, updated = judge_scores(scores, scored, scored_ids, files, every_file_suite, args.update_scores)
    for line in score_failures:
        print(line)

    order = ["agree", "known", "FAIL", "STALE", "MISSING-RECORD", "MISSING-FONT", "FONT-CHANGED", "BAD-EXPECTATION", "unsupported", "skipped"]
    summary = ", ".join(f"{counts.get(name, 0)} {name.lower()}" for name in order)
    gating_files = sum(1 for p in files if every_file_suite.get(p.resolve()) is None)
    print(f"{len(gating_ids)} gating cases in {gating_files} files: {summary}; {len(unknown) + len(listed_scored)} bad known-failure ids")
    for name in sorted(scored):
        c = scored[name]
        extra = "".join(f", {c[k]} {k.lower()}" for k in FAILING if c.get(k))
        print(f"scored {name}: {sum(c.values())} cases, {c['agree']} agree, {c['differ']} differ, {c['unsupported']} unsupported, {c['skipped']} skipped{extra}")
    for note in notes:
        print(f"  note: {note}")
    if updated:
        write_scores(scores)
        print(f"updated {rel(SCORES)}: {', '.join(updated)}")
    print(
        f"driver: {rel(DRIVER_BIN)}, {timing['requests']} requests in one process, "
        f"{timing['seconds']:.2f} s; roc: {roc_version(roc)}"
    )
    if args.json:
        args.json.write_text(json.dumps(dump, indent=1) + "\n", encoding="utf-8")
    failed = (
        any(counts.get(name) for name in FAILING)
        or scored_failures
        or unknown
        or listed_scored
        or problems
        or (score_failures and not args.update_scores)
    )
    if args.strict and counts.get("unsupported"):
        failed = True
    return 1 if failed else 0


def judge_scores(
    scores: dict,
    scored: dict[str, Counter],
    scored_ids: dict[str, dict[str, list[str]]],
    files: list[Path],
    every_file_suite: dict[Path, str | None],
    update: bool,
) -> tuple[list[str], list[str], list[str]]:
    """Compare each fully run scored suite with tests/scores.json. Returns
    failure lines, notes, and the suites whose scores were (re)recorded."""
    failures: list[str] = []
    notes: list[str] = []
    updated: list[str] = []
    recorded: dict = scores.setdefault("suites", {})
    selected = {p.resolve() for p in files}
    present = {s for s in every_file_suite.values() if s is not None}
    for name in sorted(set(recorded) - present):
        notes.append(f"scored suite {name} has no case files here (not imported); skipped")
    for name in sorted(present):
        suite_files = {p for p, s in every_file_suite.items() if s == name}
        if name not in scored:
            continue
        if not suite_files <= selected:
            notes.append(f"scored suite {name} was only partly selected; its score is not compared")
            continue
        c = scored[name]
        ids = scored_ids[name]
        now = {
            "cases": sum(c.values()),
            "agree": c["agree"],
            "differ": c["differ"],
            "unsupported": c["unsupported"],
            "skipped": c["skipped"],
            "agree_ids": ids_digest(ids.get("agree", [])),
            "case_ids": ids_digest([i for group in ids.values() for i in group]),
        }
        if any(c.get(k) for k in FAILING):
            notes.append(f"scored suite {name} has cases that cannot be compared ({', '.join(k for k in FAILING if c.get(k))}); its score is not compared")
            continue
        before = recorded.get(name)
        if update:
            if before != now:
                change = "new" if before is None else f"agree {before['agree']} -> {now['agree']}"
                recorded[name] = now
                updated.append(f"{name} ({change})")
            continue
        if before is None:
            failures.append(f"{'SCORE-NEW':15} {score_line(name, now)}; record it with --update-scores")
            continue
        if before["case_ids"] != now["case_ids"] or before["cases"] != now["cases"]:
            failures.append(
                f"{'SUITE-CHANGED':15} {name}: {now['cases']} cases here, {before['cases']} when scored; "
                "re-import the pinned version, or review and run --update-scores"
            )
            continue
        if before["skipped"] != now["skipped"]:
            notes.append(f"scored suite {name}: {now['skipped']} cases skipped here, {before['skipped']} when scored; score not comparable, skipped")
            continue
        if now["agree"] < before["agree"]:
            failures.append(f"{'SCORE-DROP':15} {name}: {now['agree']} agree, {before['agree']} recorded (a regression)")
        elif now != before:
            what = (
                f"{now['agree']} agree, {before['agree']} recorded"
                if now["agree"] != before["agree"]
                else "same agree count but a different agreeing set or other counts"
            )
            failures.append(
                f"{'SCORE-CHANGED':15} {name}: {what} ({score_line(name, now).split(': ', 1)[1]}); "
                "review, then run --update-scores to lock it in"
            )
    return failures, notes, updated


if __name__ == "__main__":
    sys.exit(main())
