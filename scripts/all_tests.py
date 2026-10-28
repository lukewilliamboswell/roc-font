#!/usr/bin/env python3
"""Run every roc-font check, in order, and report each one.

Steps (select with --only, drop with --skip, list with --list):

    compiler          reports the compiler in use (`roc version`; debug builds warn)
    unicode-data      pinned Unicode generators agree with committed source
    fmt               roc fmt --check on every directory holding .roc files
    check             roc check package/main.roc; then, against the served
                      bundle, the API test app, every fuzz target, the
                      conformance driver and the benchmark programs
    test              roc test package/main.roc (the package's own expects,
                      the only tests of its source); then, against the served
                      bundle, the API test app (tests/api/main.roc) and the
                      driver's Case.roc (dev backend)
    fuzz-smoke        scripts/run_fuzz.py smoke (native builds, seeded; with
                      --smoke only the whole-pipeline targets font-read and
                      font-shape, 200 inputs each)
    examples          scripts/examples.py check: every example's recorded output
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

Test what you fly: before the steps, the package is bundled once with
`roc bundle`, served on a loopback address (scripts/flight.py) and every
consumer step (check and test of the consumers, fuzz-smoke, examples,
conformance, bench) runs in a mirror of the checkout whose package/main.roc
is a sentinel that does not compile, with `--replace-dep` pointing at the
served bundle. A consumer that compiled package/ sources instead fails.
--bundle FILE serves a given bundle (the release's asset) instead;
--source compiles package/ in place, for quick local iteration only.

Each step ends PASS, FAIL, SKIP (with the reason), WARN (passed with a
caveat) or KNOWN (a failure recorded as known; it still fails the run
unless --allow-known is given). The exit status is 0 only when no step
failed.

--smoke is what CI runs: only the two whole-pipeline fuzz targets and a
benchmark pass prove they build and run, so pull requests stay fast. The allocation ratchet, comparison
programs and fuzz campaigns are local (architecture §7.3, §9).

The compiler is $ROC, or `roc` on PATH. Standard library only.
"""

from __future__ import annotations

import argparse
import contextlib
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

sys.path.insert(0, str(Path(__file__).resolve().parent))
import flight  # noqa: E402


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
    # Where consumer steps run, and the roc arguments that point them at the
    # served bundle (flight.replace_dep). With --source: ROOT and none.
    consumer_root: Path = ROOT
    dep: list[str] = field(default_factory=list)
    url: str | None = None


# ----------------------------------------------------------------- helpers


def resolve_command(command: str) -> str:
    if "/" in command or "\\" in command:
        return str(Path(command).expanduser().resolve())
    return command


def run(command: Sequence[str], *, env: dict[str, str] | None = None, cwd: Path = ROOT) -> tuple[int, str]:
    where = "" if cwd == ROOT else f"(in {cwd.relative_to(ROOT) if cwd.is_relative_to(ROOT) else cwd}) "
    print(f"  + {where}{' '.join(str(part) for part in command)}", flush=True)
    try:
        completed = subprocess.run(
            [str(part) for part in command], cwd=cwd, env=env, check=False,
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
    """The environment of a consumer script: the served bundle, the shared
    working directory and the real checkout (for reports' git revision)."""
    env = os.environ.copy()
    env["ROC"] = ctx.roc
    env["ROC_FONT_TMPDIR"] = str(TMP_ROOT)
    env[flight.CHECKOUT_ENV] = str(ROOT)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    if ctx.url:
        env[flight.URL_ENV] = ctx.url
    else:
        env.pop(flight.URL_ENV, None)
    return env


def run_all(ctx: Context, commands: Sequence[Sequence[str]], cwd: Path = ROOT,
            accept: Callable[[str], bool] | None = None,
            env: dict[str, str] | None = None) -> Result:
    """Run each command; one fails on a non-zero exit unless `accept`
    accepts its output."""
    outputs: list[str] = []
    failed: list[str] = []
    for command in commands:
        code, output = run(command, cwd=cwd, env=env)
        outputs.append(f"$ {' '.join(command)}\n{output.rstrip()}")
        if code != 0 and not (accept and accept(output)):
            failed.append(" ".join(command))
    text = "\n".join(outputs)
    if failed:
        return Result("FAIL", f"{len(failed)} of {len(commands)} failed: " + "; ".join(failed), text)
    return Result("PASS", f"{len(commands)} command(s)", text)


API_TESTS = "tests/api/main.roc"
# The consumers of the package, compiled against the served bundle.
DRIVER = "tools/driver/main.roc"
BENCH_APPS = (
    "bench/roc/font.roc", "bench/roc/alloc.roc",
    "bench/roc/myanmar.roc", "bench/roc/myanmar-alloc.roc",
    "bench/arabic/bench.roc", "bench/arabic/alloc.roc",
    "tests/fonts/complex/bench.roc", "tests/fonts/complex/alloc.roc",
)


def consumer_test_modules() -> list[str]:
    # The tests of the public API: an app that imports the package, as users
    # do, and the test-only builders in tests/support/.
    api = [API_TESTS] if (ROOT / API_TESTS).is_file() else []
    # The conformance harness's protocol parser carries its own expects.
    driver = ROOT / "tools" / "driver" / "Case.roc"
    return api + ([str(driver.relative_to(ROOT))] if driver.is_file() else [])


def consumer_apps() -> list[str]:
    apps = [API_TESTS, *fuzz_sources(), *BENCH_APPS]
    return [app for app in apps if (ROOT / app).is_file()]


def only_platform_problems(ctx: Context) -> Callable[[str], bool]:
    """Accepts roc output whose problems all lie inside the cached basic-cli
    platform (the nightly reports some there; CONTRIBUTING.md, compiler
    notes), never one in this repository or in the roc-font bundle."""
    from conformance import reported_problems  # scripts/ is on sys.path

    package = ctx.url.rsplit("/", 1)[-1] if ctx.url else "source"

    def accept(output: str) -> bool:
        located, ours = reported_problems(output, package)
        return bool(located) and not ours
    return accept


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


def step_compiler(ctx: Context) -> Result:
    """Reports the compiler in use. Nothing pins it: CI and local work use
    the latest Roc nightly, so this step records which one ran."""
    code, output = run([ctx.roc, "version"])
    if code != 0:
        return Result("FAIL", f"`{ctx.roc} version` failed", output)
    match = re.search(r"version\s+(\S+)", output)
    actual = match.group(1) if match else output.strip()
    if actual.startswith("debug-"):
        return Result(
            "WARN",
            f"{ctx.roc} is a local debug build ({actual}); results may differ from a nightly "
            "(formatting already does). CI uses the latest nightly; set ROC to it.",
            output,
        )
    return Result("PASS", f"{actual} ({ctx.roc})", output)


def step_fmt(ctx: Context) -> Result:
    dirs = [name for name in ROC_DIRS if (ROOT / name).is_dir() and any((ROOT / name).rglob("*.roc"))]
    return run_all(ctx, [[ctx.roc, "fmt", "--check", f"{name}/"] for name in dirs])


def merge(results: Sequence[Result]) -> Result:
    failed = [r for r in results if r.status == "FAIL"]
    text = "\n".join(r.output for r in results)
    if failed:
        return Result("FAIL", "; ".join(r.detail for r in failed), text)
    return Result("PASS", "; ".join(r.detail for r in results), text)


def sentinel_control(ctx: Context) -> Result:
    """The mirror's package/main.roc must make a source build fail; otherwise
    a passing consumer step would prove nothing."""
    code, output = run([ctx.roc, "check", API_TESTS], cwd=ctx.consumer_root)
    if code == 0:
        return Result("FAIL", "the mirror's sentinel package/main.roc compiled; consumer steps would not prove "
                      "they used the bundle", output)
    return Result("PASS", "sentinel control: a source build fails in the mirror")


def step_check(ctx: Context) -> Result:
    source = run_all(ctx, [[ctx.roc, "check", "package/main.roc"]])
    source.detail = "package source: " + source.detail
    consumers = run_all(ctx, [[ctx.roc, "check", path, *ctx.dep] for path in consumer_apps()], cwd=ctx.consumer_root)
    consumers.detail = ("consumers against the bundle: " if ctx.dep else "consumers against source: ") + consumers.detail
    parts = [source, consumers]
    if (ROOT / DRIVER).is_file():
        driver = run_all(ctx, [[ctx.roc, "check", DRIVER, *ctx.dep]], cwd=ctx.consumer_root,
                         accept=only_platform_problems(ctx))
        driver.detail = "driver: " + driver.detail
        parts.append(driver)
    return merge(parts)


def count_expects(result: Result) -> int:
    return sum(int(c) for c in re.findall(r"All \((\d+)\) tests passed", result.output))


def step_test(ctx: Context) -> Result:
    cache = ["--no-cache"] if ctx.args.no_cache else []
    # The package's own expects (in every module package/main.roc reaches):
    # the only tests that compile package/ source.
    source = run_all(ctx, [[ctx.roc, "test", *cache, "package/main.roc"]])
    if source.status == "PASS":
        source.detail = f"package source: {count_expects(source)} expects"
    modules = consumer_test_modules()
    if not modules:
        return Result("FAIL", f"no consumer test modules found ({API_TESTS})")
    consumers = run_all(ctx, [[ctx.roc, "test", *ctx.dep, *cache, module] for module in modules], cwd=ctx.consumer_root)
    if consumers.status == "PASS":
        consumers.detail = (f"{'bundle' if ctx.dep else 'source'}: {len(modules)} consumer modules, "
                            f"{count_expects(consumers)} expects")
    return merge([source, consumers])


SMOKE_FUZZ_RUNS = 200
# The whole-pipeline targets; the narrow per-feature targets run locally.
SMOKE_FUZZ_TARGETS = ["font-read", "font-shape"]


def step_fuzz_smoke(ctx: Context) -> Result:
    command = [sys.executable, "scripts/run_fuzz.py", "smoke", "--roc", ctx.roc]
    if not ctx.url:
        command.append("--source")
    if ctx.args.smoke:
        command += SMOKE_FUZZ_TARGETS
    runs = ctx.args.fuzz_runs or (SMOKE_FUZZ_RUNS if ctx.args.smoke else None)
    if runs:
        command.append(f"--runs={runs}")
    code, output = run(command, env=child_env(ctx), cwd=ctx.consumer_root)
    summary = output[output.find("fuzz smoke summary"):] if "fuzz smoke summary" in output else ""
    if code != 0:
        return Result("FAIL", "a fuzz target failed or did not build; see the crash instructions above", output)
    return Result("PASS", " / ".join(line.split()[0] + " " + line.split()[1] for line in summary.splitlines()[1:] if line.strip()), output)


def optional_script(ctx: Context, script: str, arguments: Sequence[str], why_missing: str) -> Result:
    path = ROOT / "scripts" / script
    if not path.is_file():
        return Result("SKIP", f"scripts/{script} does not exist yet ({why_missing})")
    command = [sys.executable, f"scripts/{script}", *arguments, *([] if ctx.url else ["--source"])]
    code, output = run(command, env=child_env(ctx), cwd=ctx.consumer_root)
    against = "the served bundle" if ctx.url else "package/ source"
    return Result("PASS" if code == 0 else "FAIL", f"exit {code}, against {against}", output)


def step_examples(ctx: Context) -> Result:
    return optional_script(ctx, "examples.py", ["check"], "the examples' recorded output")


def step_unicode_data(ctx: Context) -> Result:
    # Generated shaping properties are pinned to the reference shaper's
    # Unicode version. Check generated source and its embedded licence.
    generators = sorted((ROOT / "tools" / "ucd").glob("generate*.py"))
    return run_all(ctx, [[sys.executable, str(path), "--check"] for path in generators],
                   env=child_env(ctx))


def step_conformance(ctx: Context) -> Result:
    main = optional_script(ctx, "conformance.py", [], "oracle conformance, architecture §7.1")
    # Feature-specific native drivers consume cached JSONC/JSONL data too.
    # They inherit the same served bundle in the source-sentinel mirror.
    statuses = [f"general font cases: {main.status}"]
    outputs = [main.output]
    passed = main.status == "PASS"
    for feature in ("math", "outlines-carets", "color-images", "color", "positioning/context-budget"):
        code, output = run([sys.executable, f"tests/fonts/{feature}/verify.py"],
                           env=child_env(ctx), cwd=ctx.consumer_root)
        passed = passed and code == 0
        statuses.append(f"{feature}: exit {code}")
        outputs.append(output)
    return Result("PASS" if passed else "FAIL", "; ".join(statuses), "\n".join(outputs))


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


# Steps that compile consumers of the package, against the served bundle.
CONSUMER_STEPS = ("check", "test", "fuzz-smoke", "examples", "conformance", "bench")

STEPS: dict[str, Callable[[Context], Result]] = {
    "compiler": step_compiler,
    "unicode-data": step_unicode_data,
    "fmt": step_fmt,
    "check": step_check,
    "test": step_test,
    "fuzz-smoke": step_fuzz_smoke,
    "examples": step_examples,
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
    parser.add_argument("--no-cache", action="store_true", help="pass --no-cache to roc test")
    parser.add_argument("--fuzz-runs", type=int, help="inputs per fuzz target in the smoke step")
    parser.add_argument("--smoke", action="store_true",
                        help="CI mode: short fuzz smoke, benchmark smoke without the ratchet")
    parser.add_argument("--bundle", type=Path,
                        help="serve this bundle to the consumer steps instead of bundling package/ (a release asset)")
    parser.add_argument("--source", action="store_true",
                        help="consumer steps compile package/ in place instead of the served bundle (quick local iteration)")
    parser.add_argument("--verbose", action="store_true", help="print each step's full output")
    parser.add_argument("--list", action="store_true", help="list the steps and exit")
    args = parser.parse_args(argv)

    if args.list:
        for name in STEPS:
            print(name)
        return 0

    if args.source and args.bundle:
        parser.error("--source and --bundle exclude each other")
    only, skip = parse_steps(args.only), set(parse_steps(args.skip))
    selected = [name for name in STEPS if (not only or name in only)]
    ctx = Context(roc=args.roc, args=args)
    with contextlib.ExitStack() as stack:
        if not args.source and any(name in CONSUMER_STEPS and name not in skip for name in selected):
            print("\n== flight", flush=True)
            try:
                ctx.dep = stack.enter_context(flight.flight(ctx.roc, bundle=args.bundle, work=WORK / "flight"))
            except RuntimeError as problem:
                print(problem)
                print("\nchecks FAILED: could not bundle the package for the consumer steps")
                return 1
            ctx.url = ctx.dep[-1]
            ctx.consumer_root = flight.make_mirror(WORK / "mirror")
            control = sentinel_control(ctx)
            print(f"   {control.status}: consumer steps run in {ctx.consumer_root}, against {ctx.url}; "
                  f"{control.detail}", flush=True)
            if control.status != "PASS":
                print(tail(control.output, 40))
                print("\nchecks FAILED: the mirror cannot prove consumer steps use the bundle")
                return 1
        return run_steps(ctx, selected, skip)


def run_steps(ctx: Context, selected: list[str], skip: set[str]) -> int:
    args = ctx.args
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
