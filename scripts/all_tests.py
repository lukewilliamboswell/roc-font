#!/usr/bin/env python3
"""Run every roc-font check, in order, and report each one.

Steps (select with --only, drop with --skip, list with --list):

    roc-version       the compiler matches .roc-version (debug builds warn)
    fmt               roc fmt --check on every directory holding .roc files
    check             roc check package/main.roc, the API test app and every fuzz target
    test              roc test on the API test app (tests/api/main.roc), every
                      in-package package/*Tests.roc and the driver's Case.roc
                      (dev backend)
    test-interpreter  the same with --opt=interpreter
    fuzz-smoke        scripts/run_fuzz.py smoke (native builds, seeded;
                      200 inputs per target with --smoke)
    conformance       scripts/conformance.py, when present
    bench             scripts/bench.py --check --quick, when present (with
                      --smoke: one Roc-only pass over Inter, no ratchet)
    docs              roc docs shows exactly the public API (scripts/public_api.json)
    bundle            tools/default-fonts/verify.py passes, and roc bundle holds
                      the package modules plus exactly the default fonts and
                      licences pinned in tools/default-fonts/pins.json (byte
                      for byte), no other font, test module or fuzz target, and
                      stays under roc's 10 MB package limit
    diff-check        git diff --check, plus the same check on untracked files

Each step ends PASS, FAIL, SKIP (with the reason), WARN (passed with a
caveat) or KNOWN (a failure recorded as known; it still fails the run
unless --allow-known is given). The exit status is 0 only when no step
failed.

--smoke is what CI runs: fuzzing and benchmarks only prove they build and
run, so pull requests stay fast. The allocation ratchet, comparison
programs and fuzz campaigns are local (architecture §7.3, §9).

The compiler is $ROC, or `roc` on PATH. Standard library only.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Sequence


ROOT = Path(__file__).resolve().parents[1]
TMP_ROOT = Path(os.environ.get("ROC_FONT_TMPDIR", ROOT / ".roc-font-tmp")).resolve()
WORK = TMP_ROOT / "all-tests"
PUBLIC_API = ROOT / "scripts" / "public_api.json"
ROC_DIRS = ("package", "fuzz", "tools", "bench", "tests", "examples")
FONT_SUFFIXES = (".ttf", ".otf", ".ttc", ".otc", ".woff", ".woff2", ".dfont", ".pfb")
FONT_MAGICS = (b"\x00\x01\x00\x00", b"OTTO", b"true", b"ttcf", b"wOFF", b"wOF2", b"typ1")


@dataclass
class Result:
    status: str  # PASS, FAIL, SKIP, WARN, KNOWN
    detail: str = ""
    output: str = ""


@dataclass
class Context:
    roc: str
    args: argparse.Namespace
    notes: list[str] = field(default_factory=list)


# ----------------------------------------------------------------- helpers


def resolve_command(command: str) -> str:
    if "/" in command or "\\" in command:
        return str(Path(command).expanduser().resolve())
    return command


def run(command: Sequence[str], *, env: dict[str, str] | None = None) -> tuple[int, str]:
    print(f"  + {' '.join(str(part) for part in command)}", flush=True)
    try:
        completed = subprocess.run(
            [str(part) for part in command], cwd=ROOT, env=env, check=False,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace",
        )
    except OSError as problem:
        return 127, f"could not run {command[0]}: {problem}"
    return completed.returncode, completed.stdout or ""


def tail(text: str, lines: int = 30) -> str:
    kept = text.rstrip().splitlines()
    if len(kept) <= lines:
        return "\n".join(kept)
    return "\n".join([f"... ({len(kept) - lines} earlier lines)", *kept[-lines:]])


def fresh_dir(path: Path) -> Path:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True)
    return path


def child_env(ctx: Context) -> dict[str, str]:
    env = os.environ.copy()
    env["ROC"] = ctx.roc
    return env


def run_all(ctx: Context, commands: Sequence[Sequence[str]]) -> Result:
    outputs: list[str] = []
    failed: list[str] = []
    for command in commands:
        code, output = run(command)
        outputs.append(f"$ {' '.join(command)}\n{output.rstrip()}")
        if code != 0:
            failed.append(" ".join(command))
    text = "\n".join(outputs)
    if failed:
        return Result("FAIL", f"{len(failed)} of {len(commands)} failed: " + "; ".join(failed), text)
    return Result("PASS", f"{len(commands)} command(s)", text)


API_TESTS = "tests/api/main.roc"


def test_modules() -> list[str]:
    # The tests of the public API: an app that imports package/main.roc, as
    # consumers do, and the test-only builders in tests/support/.
    api = [API_TESTS] if (ROOT / API_TESTS).is_file() else []
    # In-package tests of internal modules, for what the public API cannot
    # observe; they use inline bytes or committed fixtures, never the builders.
    modules = sorted(str(path.relative_to(ROOT)) for path in (ROOT / "package").glob("*Tests.roc"))
    # The conformance harness's protocol parser carries its own expects.
    driver = ROOT / "tools" / "driver" / "Case.roc"
    return api + modules + ([str(driver.relative_to(ROOT))] if driver.is_file() else [])


def fuzz_sources() -> list[str]:
    sys.path.insert(0, str(ROOT / "scripts"))
    sys.dont_write_bytecode = True
    try:
        import run_fuzz  # type: ignore
    finally:
        sys.path.pop(0)
    sources = []
    for config in run_fuzz.TARGETS.values():
        try:
            sources.append(str(config.source().relative_to(ROOT)))
        except ValueError:
            pass
    return sources


# ----------------------------------------------------------------- steps


def step_roc_version(ctx: Context) -> Result:
    pin_file = ROOT / ".roc-version"
    if not pin_file.is_file():
        return Result("FAIL", ".roc-version is missing")
    pinned = pin_file.read_text(encoding="utf-8").strip()
    code, output = run([ctx.roc, "version"])
    if code != 0:
        return Result("FAIL", f"`{ctx.roc} version` failed", output)
    match = re.search(r"version\s+(\S+)", output)
    actual = match.group(1) if match else output.strip()
    if actual == pinned:
        return Result("PASS", f"{actual} ({ctx.roc})", output)
    if actual.startswith("debug-"):
        return Result(
            "WARN",
            f"{ctx.roc} is a local debug build ({actual}); the project is tested with {pinned}. "
            "Results may differ (formatting already does); set ROC to the pinned nightly.",
            output,
        )
    if ctx.args.allow_roc_mismatch:
        return Result("WARN", f"{actual} differs from the pinned {pinned} (--allow-roc-mismatch)", output)
    return Result("FAIL", f"{actual} differs from the pinned {pinned}; set ROC or update .roc-version deliberately", output)


def step_fmt(ctx: Context) -> Result:
    dirs = [name for name in ROC_DIRS if (ROOT / name).is_dir() and any((ROOT / name).rglob("*.roc"))]
    return run_all(ctx, [[ctx.roc, "fmt", "--check", f"{name}/"] for name in dirs])


def step_check(ctx: Context) -> Result:
    files = ["package/main.roc", API_TESTS, *fuzz_sources()]
    return run_all(ctx, [[ctx.roc, "check", path] for path in files])


def tests_with(ctx: Context, extra: Sequence[str]) -> Result:
    modules = test_modules()
    if not modules:
        return Result("FAIL", f"no test modules found ({API_TESTS}, package/*Tests.roc)")
    cache = ["--no-cache"] if ctx.args.no_cache else []
    result = run_all(ctx, [[ctx.roc, "test", *extra, *cache, module] for module in modules])
    counts = re.findall(r"All \((\d+)\) tests passed", result.output)
    if result.status == "PASS":
        result.detail = f"{len(modules)} modules, {sum(int(c) for c in counts)} expects"
    return result


def step_test(ctx: Context) -> Result:
    return tests_with(ctx, [])


def step_test_interpreter(ctx: Context) -> Result:
    return tests_with(ctx, ["--opt=interpreter"])


SMOKE_FUZZ_RUNS = 200


def step_fuzz_smoke(ctx: Context) -> Result:
    command = [sys.executable, "scripts/run_fuzz.py", "smoke", "--roc", ctx.roc]
    runs = ctx.args.fuzz_runs or (SMOKE_FUZZ_RUNS if ctx.args.smoke else None)
    if runs:
        command.append(f"--runs={runs}")
    print(f"  + {' '.join(command)}", flush=True)
    completed = subprocess.run(command, cwd=ROOT, env=child_env(ctx), check=False,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    output = completed.stdout or ""
    summary = output[output.find("fuzz smoke summary"):] if "fuzz smoke summary" in output else ""
    if completed.returncode != 0:
        return Result("FAIL", "a fuzz target failed or did not build; see the crash instructions above", output)
    return Result("PASS", " / ".join(line.split()[0] + " " + line.split()[1] for line in summary.splitlines()[1:] if line.strip()), output)


def optional_script(ctx: Context, script: str, arguments: Sequence[str], why_missing: str) -> Result:
    path = ROOT / "scripts" / script
    if not path.is_file():
        return Result("SKIP", f"scripts/{script} does not exist yet ({why_missing})")
    command = [sys.executable, f"scripts/{script}", *arguments]
    print(f"  + {' '.join(command)}", flush=True)
    completed = subprocess.run(command, cwd=ROOT, env=child_env(ctx), check=False,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    status = "PASS" if completed.returncode == 0 else "FAIL"
    return Result(status, f"exit {completed.returncode}", completed.stdout or "")


def step_conformance(ctx: Context) -> Result:
    return optional_script(ctx, "conformance.py", [], "oracle conformance, architecture §7.1")


def step_bench(ctx: Context) -> Result:
    if ctx.args.smoke:
        arguments = ["--quick", "--langs", "roc", "--only", "inter", "--no-allocations",
                     "--repetitions", "1", "--label", "smoke"]
        return optional_script(ctx, "bench.py", arguments, "benchmark smoke run, architecture §9")
    return optional_script(ctx, "bench.py", ["--check", "--quick"], "allocation ratchet, architecture §9.2")


DOC_ITEM_RE = re.compile(r'class="sidebar-(?:value|type|type-name)" href="#([A-Za-z0-9_.]+)"')
DOC_MODULE_RE = re.compile(r'data-module-name="([A-Za-z0-9_.]+)"')


def step_docs(ctx: Context) -> Result:
    out = fresh_dir(WORK / "docs")
    code, output = run([ctx.roc, "docs", "package/main.roc", f"--output={out}"])
    if code != 0:
        return Result("FAIL", "roc docs failed", output)
    pages = sorted(out.rglob("*.html"))
    html = "".join(page.read_text(encoding="utf-8", errors="replace") for page in pages)
    shown = set(DOC_ITEM_RE.findall(html)) | set(DOC_MODULE_RE.findall(html))
    if not shown:
        return Result("FAIL", "found no documented items; the docs HTML layout may have changed", output)
    api = json.loads(PUBLIC_API.read_text(encoding="utf-8"))
    public, known = set(api["public"]), set(api["known_internal"])
    unexpected = sorted(shown - public - known)
    missing = sorted(public - shown)
    stale = sorted(known - shown)
    leaking = sorted(shown & known)
    lines = [f"{len(shown)} items shown: {len(shown & public)} public, {len(leaking)} known internal leaks"]
    if unexpected:
        lines.append("not public and not listed as a known leak: " + ", ".join(unexpected))
    if missing:
        lines.append("public but not documented: " + ", ".join(missing))
    if stale:
        lines.append("listed as known leaks but no longer shown (remove from scripts/public_api.json): " + ", ".join(stale))
    if leaking:
        lines.append("known internal leaks: " + ", ".join(leaking))
    report = "\n".join(lines)
    if unexpected or missing or stale:
        return Result("FAIL", lines[0] + "; see output", report)
    if leaking:
        return Result("KNOWN", f"{len(leaking)} internal helpers appear as items of Font "
                      "(listed in scripts/public_api.json known_internal)", report)
    return Result("PASS", lines[0], report)


def decompress_zstd(path: Path) -> bytes | None:
    try:
        from compression import zstd  # type: ignore  # Python 3.14+
        return zstd.decompress(path.read_bytes())
    except ImportError:
        pass
    if shutil.which("zstd") is None:
        return None
    completed = subprocess.run(["zstd", "-dc", str(path)], capture_output=True, check=False)
    return completed.stdout if completed.returncode == 0 else None


PINS = ROOT / "tools" / "default-fonts" / "pins.json"
# `roc build` refuses a dependency larger than this, decompressed (its
# --max-package-mb default).
MAX_PACKAGE_BYTES = 10 * 1024 * 1024


def pinned_files() -> dict[str, str]:
    """The pinned default fonts and licences, by their path in the bundle
    (relative to package/), with their SHA-256."""
    pins = json.loads(PINS.read_text(encoding="utf-8"))
    out: dict[str, str] = {}
    for face in pins["faces"]:
        for entry in (face, face["licence"]):
            path = Path(entry["file"])
            out[str(path.relative_to("package"))] = entry["sha256"]
    return out


def step_bundle(ctx: Context) -> Result:
    import hashlib

    code, verified = run([sys.executable, "tools/default-fonts/verify.py"])
    if code != 0:
        return Result("FAIL", "tools/default-fonts/verify.py failed", verified)
    out = fresh_dir(WORK / "bundle")
    code, output = run([ctx.roc, "bundle", "package/main.roc", "--output-dir", str(out)])
    if code != 0:
        return Result("FAIL", "roc bundle failed", output)
    archives = sorted(out.glob("*.tar.zst"))
    if len(archives) != 1:
        return Result("FAIL", f"expected one .tar.zst, found {len(archives)}", output)
    data = decompress_zstd(archives[0])
    if data is None:
        return Result("SKIP", "cannot decompress zstd: needs Python 3.14 or the zstd command", output)
    pinned = pinned_files()
    problems: list[str] = []
    names: list[str] = []
    seen: set[str] = set()
    total = 0
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for member in archive.getmembers():
            names.append(member.name)
            if not member.isfile():
                continue
            name = member.name.removeprefix("./")
            base = Path(name).name
            content = archive.extractfile(member).read()  # type: ignore[union-attr]
            total += len(content)
            if name in pinned:
                seen.add(name)
                if hashlib.sha256(content).hexdigest() != pinned[name]:
                    problems.append(f"{member.name} differs from its pin in tools/default-fonts/pins.json")
                continue
            if base.lower().endswith(FONT_SUFFIXES) or content[:4] in FONT_MAGICS:
                problems.append(f"{member.name} is a font that is not pinned")
            if base.endswith("Tests.roc") or base == "FontBuild.roc" or base.startswith("fuzz"):
                problems.append(f"{member.name} is a test module or fuzz target")
            if not base.endswith(".roc"):
                problems.append(f"{member.name} is neither a Roc module nor a pinned default font or licence")
    for name in sorted(set(pinned) - seen):
        problems.append(f"{name} is pinned but missing from the bundle (is it imported?)")
    if total > MAX_PACKAGE_BYTES:
        problems.append(f"the bundle holds {total} bytes, over roc's {MAX_PACKAGE_BYTES}-byte package limit")
    report = f"{archives[0].name}: {total} bytes decompressed, " + ", ".join(sorted(names))
    if problems:
        return Result("FAIL", "; ".join(problems), report)
    return Result("PASS", f"{len(names)} files, {total} bytes ({archives[0].stat().st_size} compressed), {len(seen)} pinned font and licence files", report)


def step_diff_check(ctx: Context) -> Result:
    outputs: list[str] = []
    bad = False
    for command in (["git", "diff", "--check"], ["git", "diff", "--cached", "--check"]):
        code, output = run(command)
        outputs.append(output)
        bad = bad or code != 0
    # git diff --check ignores untracked files; check each one against /dev/null.
    code, listing = run(["git", "ls-files", "--others", "--exclude-standard", "-z", "--",
                         ".", f":(exclude){TMP_ROOT.relative_to(ROOT) if TMP_ROOT.is_relative_to(ROOT) else '.roc-font-tmp'}"])
    untracked = [name for name in listing.split("\0") if name]
    for name in untracked:
        completed = subprocess.run(["git", "diff", "--no-index", "--check", "--", os.devnull, name],
                                   cwd=ROOT, capture_output=True, text=True, errors="replace", check=False)
        # Exit status bit 2 means whitespace problems; bit 1 only that the files differ.
        if completed.returncode & 2:
            bad = True
            outputs.append(completed.stdout)
    text = "\n".join(part.rstrip() for part in outputs if part.strip())
    detail = f"tracked changes and {len(untracked)} untracked files"
    return Result("FAIL" if bad else "PASS", detail, text)


STEPS: dict[str, Callable[[Context], Result]] = {
    "roc-version": step_roc_version,
    "fmt": step_fmt,
    "check": step_check,
    "test": step_test,
    "test-interpreter": step_test_interpreter,
    "fuzz-smoke": step_fuzz_smoke,
    "conformance": step_conformance,
    "bench": step_bench,
    "docs": step_docs,
    "bundle": step_bundle,
    "diff-check": step_diff_check,
}


# ----------------------------------------------------------------- main


def parse_steps(text: str | None) -> list[str]:
    if not text:
        return []
    names = [name.strip() for name in text.split(",") if name.strip()]
    unknown = [name for name in names if name not in STEPS]
    if unknown:
        raise SystemExit(f"unknown step(s): {', '.join(unknown)}; choose from {', '.join(STEPS)}")
    return names


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--roc", default=resolve_command(os.environ.get("ROC", "roc")), help="compiler (default: $ROC or roc)")
    parser.add_argument("--only", help="comma-separated steps to run")
    parser.add_argument("--skip", help="comma-separated steps to leave out")
    parser.add_argument("--allow-known", action="store_true", help="accept KNOWN failures (exit 0 if nothing else failed)")
    parser.add_argument("--allow-roc-mismatch", action="store_true", help="warn instead of failing on another release compiler")
    parser.add_argument("--no-cache", action="store_true", help="pass --no-cache to roc test")
    parser.add_argument("--fuzz-runs", type=int, help="inputs per fuzz target in the smoke step")
    parser.add_argument("--smoke", action="store_true",
                        help="CI mode: short fuzz smoke, benchmark smoke without the ratchet")
    parser.add_argument("--verbose", action="store_true", help="print each step's full output")
    parser.add_argument("--list", action="store_true", help="list the steps and exit")
    args = parser.parse_args(argv)

    if args.list:
        for name in STEPS:
            print(name)
        return 0

    only, skip = parse_steps(args.only), set(parse_steps(args.skip))
    selected = [name for name in STEPS if (not only or name in only)]
    ctx = Context(roc=args.roc, args=args)
    results: list[tuple[str, Result]] = []
    for name in STEPS:
        if name not in selected:
            continue
        if name in skip:
            results.append((name, Result("SKIP", "--skip")))
            continue
        print(f"\n== {name}", flush=True)
        try:
            result = STEPS[name](ctx)
        except Exception as problem:  # report and carry on with the other steps
            result = Result("FAIL", f"step raised {type(problem).__name__}: {problem}")
        if args.verbose or result.status in ("FAIL", "KNOWN", "WARN"):
            if result.output.strip():
                print(tail(result.output, 10_000 if args.verbose else 40))
        print(f"   {result.status}: {result.detail}", flush=True)
        results.append((name, result))

    print("\nSummary")
    width = max(len(name) for name, _ in results) if results else 0
    for name, result in results:
        print(f"  {name:<{width}}  {result.status:<5}  {result.detail}")
    failed = [name for name, result in results if result.status == "FAIL"]
    known = [name for name, result in results if result.status == "KNOWN"]
    if known and not args.allow_known:
        print(f"\nKNOWN failures ({', '.join(known)}) still fail the run; pass --allow-known to accept them.")
    ok = not failed and (args.allow_known or not known)
    print("\nall checks passed" if ok else "\nchecks FAILED: " + ", ".join(failed + ([] if args.allow_known else known)))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
