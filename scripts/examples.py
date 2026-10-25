"""Check the examples, and build and test the examples archive a release
attaches. Standard library only.

    python3 scripts/examples.py check              # run every example, compare with tests/examples.json
    python3 scripts/examples.py check --update     # rewrite the recorded output after an intended change
    python3 scripts/examples.py package --version 0.1.0 --bundle dist/<hash>.tar.zst --output-dir dist
    python3 scripts/examples.py test-archive --archive dist/roc-font-examples-0.1.0.zip --bundle dist/<hash>.tar.zst

`check` builds every app under examples/ against the package bundle `roc
bundle` makes from the working tree, served on loopback in place of
`../package/main.roc` (scripts/flight.py; `--source` compiles package/
directly instead, for quick local iteration only), and runs each case recorded for it in tests/examples.json (its arguments and
standard input, from the repository root), comparing standard output,
standard error and exit status exactly. Every example must have a case, and
every recorded app must exist, so nothing is skipped silently. The example
in README.md must be examples/measure.roc, with the release's
`{package-url}` as its dependency, followed by its recorded output.

`package` writes roc-font-examples-<version>.zip in the layout of
roc-automation's shared nightly compatibility runner: one root directory
holding README.md, spec.json (schema 1: the release, the bundle URL and the
recorded cases) and examples/. The archived examples differ from the
repository's only in the package dependency, which names the release's
bundle URL; the script checks that.

`test-archive` validates and extracts an archive, serves the bundle from a
loopback address in place of its release URL (`--replace-dep`), and builds
and runs every case with an empty Roc package cache, so the bundle is
fetched and verified and never found from an earlier run. The archive is
never reformatted or edited.

The compiler is `roc` on PATH, or ROC.
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import flight  # noqa: E402

ROOT = Path(os.environ.get("ROC_FONT_ROOT", Path(__file__).resolve().parents[1])).resolve()
SPEC = ROOT / "tests" / "examples.json"
EXAMPLES = ROOT / "examples"
NAME = "roc-font"
# The one line that differs between an example in the repository and in the archive.
LOCAL_DEPENDENCY = '\tfont: "../package/main.roc",'
SAFE_MEMBER = re.compile(r"^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*/?$")
ZIP_TIME = (1980, 1, 1, 0, 0, 0)
CASE_TIMEOUT = 60
COMPILE_TIMEOUT = 600


def roc() -> str:
    command = os.environ.get("ROC", "roc")
    return str(Path(command).expanduser().resolve()) if "/" in command else command


def say(status: str, message: str) -> None:
    print(f"{status:<5} {message}", flush=True)


def load_spec(path: Path) -> dict:
    spec = json.loads(path.read_text(encoding="utf-8"))
    apps = spec.get("apps")
    if not isinstance(apps, list) or not apps:
        raise SystemExit(f"{path}: no apps")
    paths = [app["path"] for app in apps]
    if len(set(paths)) != len(paths):
        raise SystemExit(f"{path}: an app is listed twice")
    for app in apps:
        names = [case["name"] for case in app["cases"]]
        if not names or len(set(names)) != len(names):
            raise SystemExit(f"{path}: {app['path']} needs cases with distinct names")
        for case in app["cases"]:
            missing = {"name", "args", "stdin", "stdout", "stderr", "exit_code"} - set(case)
            if missing:
                raise SystemExit(f"{path}: {app['path']} case {case['name']} lacks {', '.join(sorted(missing))}")
    return spec


def example_files(root: Path) -> list[Path]:
    """Every file an example may use: the apps and any sibling modules or data."""
    files = sorted(p for p in (root / "examples").rglob("*") if p.is_file() and "__pycache__" not in p.parts)
    for path in files:
        rel = path.relative_to(root).as_posix()
        if not SAFE_MEMBER.match(rel):
            raise SystemExit(f"{rel}: example file names use ASCII letters, digits, '.', '_' and '-' only")
    return files


def run_case(executable: Path, case: dict, cwd: Path, env: dict[str, str] | None = None) -> dict:
    try:
        done = subprocess.run([str(executable), *case["args"]], cwd=cwd, input=case["stdin"].encode("utf-8"),
                              capture_output=True, timeout=CASE_TIMEOUT, env=env, check=False)
    except subprocess.TimeoutExpired:
        return {"stdout": "", "stderr": f"timed out after {CASE_TIMEOUT}s", "exit_code": -1}
    return {"stdout": done.stdout.decode("utf-8", "replace"), "stderr": done.stderr.decode("utf-8", "replace"),
            "exit_code": done.returncode}


def compare(label: str, case: dict, actual: dict) -> bool:
    ok = True
    for field in ("stdout", "stderr"):
        if actual[field] != case[field]:
            ok = False
            diff = difflib.unified_diff(case[field].splitlines(keepends=True), actual[field].splitlines(keepends=True),
                                        f"expected {field}", f"actual {field}")
            sys.stdout.write("".join(diff))
    if actual["exit_code"] != case["exit_code"]:
        ok = False
        print(f"      exit status {actual['exit_code']}, expected {case['exit_code']}")
    say("PASS" if ok else "FAIL", label)
    return ok


def compile_app(path: str, cwd: Path, out: Path, extra: list[str], env: dict[str, str] | None = None) -> bool:
    for argv in ([roc(), "check", path, "--no-cache", *extra],
                 [roc(), "build", path, "--no-cache", "--opt=dev", f"--output={out}", *extra]):
        done = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, errors="replace",
                              timeout=COMPILE_TIMEOUT, env=env, check=False)
        if done.returncode != 0:
            sys.stdout.write(done.stdout + done.stderr)
            say("FAIL", f"{' '.join(argv[1:3])}")
            return False
    return True


def run_suite(spec: dict, cwd: Path, work: Path, extra: list[str], env: dict[str, str] | None = None,
              update: bool = False) -> int:
    failures = 0
    for number, app in enumerate(spec["apps"]):
        exe = work / f"example-{number}"
        if not compile_app(app["path"], cwd, exe, extra, env):
            failures += len(app["cases"])
            continue
        for case in app["cases"]:
            actual = run_case(exe, case, cwd, env)
            label = f"{app['path']} [{case['name']}]"
            if update:
                if any(case[field] != actual[field] for field in actual):
                    case.update(actual)
                    say("NEW", label)
                else:
                    say("PASS", label)
            elif not compare(label, case, actual):
                failures += 1
    return failures


# ----------------------------------------------------------------- check


def readme_problems(spec: dict) -> list[str]:
    """README.md's example is examples/measure.roc as a user writes it (the
    dependency is the release's `{package-url}`), followed by its output."""
    readme_text = (ROOT / "README.md").read_text(encoding="utf-8")
    source = (EXAMPLES / "measure.roc").read_text(encoding="utf-8")
    shown = source.replace(LOCAL_DEPENDENCY, '\tfont: "{package-url}",')
    problems = []
    if f"```roc\n{shown}```" not in readme_text:
        problems.append("README.md's example differs from examples/measure.roc (with font: \"{package-url}\")")
    output = next(app["cases"][0]["stdout"] for app in spec["apps"] if app["path"] == "examples/measure.roc")
    if f"```text\n{output}```" not in readme_text:
        problems.append("README.md's example output differs from the output recorded for examples/measure.roc")
    # The manual includes the example's source; its output is written out.
    manual = (ROOT / "docs" / "index.adoc").read_text(encoding="utf-8")
    if "include::../examples/measure.roc[]" not in manual or f"[source,text]\n----\n{output}----" not in manual:
        problems.append("docs/index.adoc's Getting started no longer shows examples/measure.roc and its recorded output")
    return problems


def command_check(args: argparse.Namespace) -> int:
    spec = load_spec(SPEC)
    listed = {app["path"] for app in spec["apps"]}
    apps = {p.relative_to(ROOT).as_posix() for p in EXAMPLES.glob("*.roc")}
    problems = [f"{p} has no case in tests/examples.json" for p in sorted(apps - listed)]
    problems += [f"{p} is recorded but does not exist" for p in sorted(listed - apps)]
    problems += readme_problems(spec)
    for problem in problems:
        say("FAIL", problem)
    if problems:
        return 1
    with tempfile.TemporaryDirectory(prefix="roc-font-examples-") as work, \
            flight.flight(roc(), source=args.source) as dep:
        failures = run_suite(spec, ROOT, Path(work), dep, update=args.update)
    if args.update:
        SPEC.write_text(json.dumps(spec, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        say("DONE", f"rewrote {SPEC.relative_to(ROOT)}")
        return 1 if failures else 0
    total = sum(len(app["cases"]) for app in spec["apps"])
    say("DONE" if not failures else "FAIL", f"{total - failures} of {total} example cases match")
    return 1 if failures else 0


# ----------------------------------------------------------------- package


def bundle_url(repository: str, version: str, bundle: Path) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise SystemExit(f"not an owner/name repository: {repository}")
    if not re.fullmatch(r"[1-9A-HJ-NP-Za-km-z]+\.tar\.zst", bundle.name):
        raise SystemExit(f"{bundle.name} is not a roc bundle name (<hash>.tar.zst)")
    return f"https://github.com/{repository}/releases/download/{version}/{bundle.name}"


def archived_source(text: str, url: str, rel: str) -> str:
    lines = text.split("\n")
    hits = [i for i, line in enumerate(lines) if line == LOCAL_DEPENDENCY]
    if len(hits) != 1:
        raise SystemExit(f"{rel}: expected exactly one line {LOCAL_DEPENDENCY.strip()!r}, found {len(hits)}")
    lines[hits[0]] = f'\tfont: "{url}",'
    return "\n".join(lines)


def only_dependency_differs(original: str, archived: str, url: str) -> bool:
    a, b = original.split("\n"), archived.split("\n")
    if len(a) != len(b):
        return False
    changed = [(x, y) for x, y in zip(a, b) if x != y]
    return changed == [(LOCAL_DEPENDENCY, f'\tfont: "{url}",')]


def readme(version: str, url: str, spec: dict) -> str:
    apps = "\n".join(f"- `{app['path']}`" for app in spec["apps"])
    return f"""# roc-font {version} examples

The examples of roc-font {version}, each depending on that release's bundle:

    {url}

Run one from this directory with the latest Roc nightly (the release
notes name the nightly the release was tested with):

    roc examples/measure.roc

The examples:

{apps}

`spec.json` records the arguments, input and exact output of each example
as tested before the release was published.
"""


def command_package(args: argparse.Namespace) -> int:
    bundle = Path(args.bundle)
    url = bundle_url(args.repository, args.version, bundle)
    spec = load_spec(SPEC)
    root_name = f"{NAME}-examples-{args.version}"
    members: dict[str, bytes] = {}
    for path in example_files(ROOT):
        rel = path.relative_to(ROOT).as_posix()
        data = path.read_bytes()
        if path.suffix == ".roc":
            original = data.decode("utf-8")
            if "../package/main.roc" in original:
                archived = archived_source(original, url, rel)
                if not only_dependency_differs(original, archived, url):
                    raise SystemExit(f"{rel}: the archived copy differs in more than the package dependency")
                data = archived.encode("utf-8")
        members[rel] = data
    archived_spec = {"schema_version": 1, "release": args.version, "dependencies": [url],
                     "apps": [{"path": app["path"],
                               "cases": [{k: case[k] for k in ("name", "args", "stdin", "stdout", "stderr", "exit_code")}
                                         for case in app["cases"]]}
                              for app in spec["apps"]]}
    members["spec.json"] = (json.dumps(archived_spec, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    members["README.md"] = readme(args.version, url, spec).encode("utf-8")
    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)
    target = out / f"{root_name}.zip"
    directories = {f"{root_name}/"} | {f"{root_name}/{Path(rel).parent.as_posix()}/" for rel in members if "/" in rel}
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(directories):
            info = zipfile.ZipInfo(name, ZIP_TIME)
            info.external_attr = (stat.S_IFDIR | 0o755) << 16 | 0x10
            info.create_system = 3
            archive.writestr(info, b"")
        for rel in sorted(members):
            info = zipfile.ZipInfo(f"{root_name}/{rel}", ZIP_TIME)
            info.external_attr = (stat.S_IFREG | 0o644) << 16
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, members[rel])
    say("DONE", f"{target} ({len(members)} files) names {url}")
    return 0


# ----------------------------------------------------------------- test-archive


def extract(archive_path: Path, into: Path) -> Path:
    root_name = archive_path.name.removesuffix(".zip")
    with zipfile.ZipFile(archive_path) as archive:
        seen: set[str] = set()
        for info in archive.infolist():
            name = info.filename
            mode = info.external_attr >> 16
            if (not name.startswith(f"{root_name}/") or not SAFE_MEMBER.match(name) or name.lower() in seen
                    or info.flag_bits & 0x1 or stat.S_ISLNK(mode)
                    or any(part in ("", ".", "..") for part in name.rstrip("/").split("/"))):
                raise SystemExit(f"{archive_path.name}: unsafe or unexpected member {name!r}")
            seen.add(name.lower())
        for info in archive.infolist():
            target = into / info.filename
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(info))
    return into / root_name


def command_test_archive(args: argparse.Namespace) -> int:
    archive_path, bundle = Path(args.archive).resolve(), Path(args.bundle).resolve()
    with tempfile.TemporaryDirectory(prefix="roc-font-archive-") as temporary:
        work = Path(temporary)
        root = extract(archive_path, work / "suite")
        spec = load_spec(root / "spec.json")
        dependencies = spec.get("dependencies", [])
        if spec.get("schema_version") != 1 or len(dependencies) != 1 or not dependencies[0].endswith("/" + bundle.name):
            raise SystemExit("spec.json must be schema 1 and name exactly this bundle as its dependency")
        url = dependencies[0]
        # The archived examples differ from the checkout's only in the dependency.
        for path in sorted((root / "examples").rglob("*")):
            rel = path.relative_to(root).as_posix()
            original = ROOT / rel
            if path.is_file() and original.is_file() and path.read_bytes() != original.read_bytes():
                if not only_dependency_differs(original.read_text(encoding="utf-8"), path.read_text(encoding="utf-8"), url):
                    raise SystemExit(f"{rel}: the archived copy differs from the checkout in more than the dependency")
        with flight.serve(bundle, prune_cache=False) as served:
            say("SERVE", f"{served} in place of {url}")
            env = dict(os.environ, XDG_CACHE_HOME=str(work / "cache"))
            failures = run_suite(spec, root, work, ["--replace-dep", url, served], env)
    total = sum(len(app["cases"]) for app in spec["apps"])
    say("DONE" if not failures else "FAIL", f"{total - failures} of {total} archived example cases match")
    return 1 if failures else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    check = sub.add_parser("check", help="run the examples against the working tree")
    check.add_argument("--update", action="store_true", help="rewrite the recorded output")
    check.add_argument("--source", action="store_true",
                       help="build against package/ sources instead of the served bundle (quick local iteration)")
    package = sub.add_parser("package", help="write the examples archive for a release")
    package.add_argument("--version", required=True)
    package.add_argument("--bundle", required=True, help="the release's .tar.zst bundle")
    package.add_argument("--output-dir", required=True)
    package.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", "lukewilliamboswell/roc-font"))
    test = sub.add_parser("test-archive", help="test an examples archive, unchanged, against its bundle")
    test.add_argument("--archive", required=True)
    test.add_argument("--bundle", required=True)
    args = parser.parse_args(argv)
    return {"check": command_check, "package": command_package, "test-archive": command_test_archive}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
