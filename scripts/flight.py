"""Test what you fly: every consumer check imports the bundle roc-font ships.

`roc bundle package/main.roc` makes the artifact users import by URL. The
checks build it once, serve it on a loopback address for the duration of a
run, and give every roc command that compiles a consumer of the package
(the API tests, fuzz targets, the conformance driver, the benchmark
programs, the examples) the arguments

    --replace-dep ./package/main.roc http://127.0.0.1:<port>/<hash>.tar.zst

so the consumer's `"../package/main.roc"` dependency resolves to the served
bundle, fetched and hash-checked exactly as a user's download is. roc
resolves OLD against the current directory, so consumers run roc from the
repository root (or from the mirror below).

Only `roc check`, `roc test`, `roc docs` and `roc bundle` of
package/main.roc itself read the package's source: they check it, run its
own expects (the only source-level tests) and build the artifact.

The package cache is shared: a bundle's URL ends in its content hash, which
roc verifies on download and names its cache entry by, so a cached entry
can only ever hold the same bytes and a stale bundle cannot be masked. An
entry this run created is removed at the end so edits do not accumulate
6 MB entries (re-fetching from loopback costs milliseconds).

A parent process shares its served bundle with child scripts through
ROC_FONT_BUNDLE_URL; a script started on its own serves its own. The
mirror (`make_mirror`) is an independent copy of the checkout without the
package's .roc files, whose package/main.roc is a sentinel that does not
compile, so a consumer step run there fails unless it took the served
bundle. (roc needs --replace-dep's OLD file to exist, hence a sentinel
rather than nothing.) scripts/all_tests.py runs every consumer step there.

`roc test` of an app that imports the package by path also runs the
package's expects; through the bundle it does not, so consumer expect
counts exclude them.

As a command, it serves a bundle around another command:

    python3 -I scripts/flight.py [--bundle FILE] -- COMMAND...

with ROC_FONT_BUNDLE_URL set for the command. Standard library only.
"""

from __future__ import annotations

import argparse
import contextlib
import http.server
import os
import re
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
from pathlib import Path
from typing import Iterator, Sequence

ROOT = Path(__file__).resolve().parents[1]
TMP_ROOT = Path(os.environ.get("ROC_FONT_TMPDIR", ROOT / ".roc-font-tmp")).resolve()
# The dependency every consumer names, spelled as roc's --replace-dep OLD
# wants it: relative to the current directory, which is the repository root.
PACKAGE = "./package/main.roc"
URL_ENV = "ROC_FONT_BUNDLE_URL"
# The checkout a mirror stands for, so reports name its git revision.
CHECKOUT_ENV = "ROC_FONT_CHECKOUT"
BUNDLE_NAME = re.compile(r"[1-9A-HJ-NP-Za-km-z]+\.tar\.zst")
SENTINEL = (
    "## Not roc-font: the checks' mirror of the checkout replaces the package\n"
    "## with this file. A consumer that compiles it took the source tree\n"
    "## instead of the served bundle (scripts/flight.py).\n"
    "this file is deliberately not Roc\n"
)
# Top-level entries the mirror leaves out: version control, and generated
# or session state. Of package/ it keeps only data files (the default fonts
# and licences, which conformance cases read as plain files); every .roc
# file is left out and main.roc becomes the sentinel.
MIRROR_SKIP = {".git", ".claude", ".blueprint", ".docs-out", ".roc-fuzz", "dist",
               "generated-docs", "__pycache__"}


def replace_dep(url: str) -> list[str]:
    """The roc arguments that make a consumer import `url` instead of the source."""
    return ["--replace-dep", PACKAGE, url]


def checkout() -> Path:
    """The checkout under test (the real one when running in a mirror)."""
    return Path(os.environ.get(CHECKOUT_ENV, ROOT)).resolve()


def roc_cache_dir() -> Path:
    base = os.environ.get("XDG_CACHE_HOME")
    default = Path.home() / ("Library/Caches" if sys.platform == "darwin" else ".cache")
    return (Path(base) if base else default) / "roc" / "packages"


def build_bundle(roc: str, out: Path) -> Path:
    """`roc bundle package/main.roc` into a fresh `out`; the one archive."""
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    done = subprocess.run([roc, "bundle", "package/main.roc", "--output-dir", str(out)], cwd=ROOT,
                          capture_output=True, text=True, errors="replace", check=False)
    archives = sorted(out.glob("*.tar.zst"))
    if done.returncode != 0 or len(archives) != 1:
        raise RuntimeError(f"roc bundle failed (exit {done.returncode}, {len(archives)} archives):\n"
                           + done.stdout + done.stderr)
    return archives[0]


class _Bundle(http.server.BaseHTTPRequestHandler):
    """Serves one file at one path; everything else is 404."""

    path_served = ""
    body = b""

    def do_GET(self) -> None:  # noqa: N802 (http.server's name)
        if self.path != self.path_served:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/zstd")
        self.send_header("Content-Length", str(len(self.body)))
        self.end_headers()
        self.wfile.write(self.body)

    def log_message(self, *args: object) -> None:
        pass


@contextlib.contextmanager
def serve(bundle: Path, prune_cache: bool = True) -> Iterator[str]:
    """Serve `bundle` on loopback; yields its URL. With `prune_cache`, the
    package-cache entry for this bundle is removed afterwards if this run
    created it."""
    if not BUNDLE_NAME.fullmatch(bundle.name):
        raise ValueError(f"{bundle.name} is not a roc bundle name (<hash>.tar.zst)")
    entry = roc_cache_dir() / bundle.name.removesuffix(".tar.zst")
    cached_before = entry.exists()
    handler = type("Handler", (_Bundle,), {"path_served": "/" + bundle.name, "body": bundle.read_bytes()})
    with socketserver.ThreadingTCPServer(("127.0.0.1", 0), handler) as server:
        server.daemon_threads = True
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            yield f"http://127.0.0.1:{server.server_address[1]}/{bundle.name}"
        finally:
            server.shutdown()
    if prune_cache and not cached_before:
        shutil.rmtree(entry, ignore_errors=True)
        with contextlib.suppress(FileNotFoundError):
            Path(f"{entry}.deps").unlink()


@contextlib.contextmanager
def flight(roc: str, *, source: bool = False, bundle: Path | None = None,
           work: Path | None = None) -> Iterator[list[str]]:
    """The roc arguments that point consumers at the package under test.

    The served bundle by default: the parent's (ROC_FONT_BUNDLE_URL) when
    set, else `bundle`, else one built from package/ into `work`. With
    `source`, no arguments: consumers compile package/ directly (for quick
    local iteration only; the checks never do this)."""
    if source:
        yield []
        return
    inherited = os.environ.get(URL_ENV)
    if inherited and bundle is None:
        yield replace_dep(inherited)
        return
    with contextlib.ExitStack() as stack:
        if bundle is None:
            if work is None:
                # Private, so scripts run side by side never share a bundle directory.
                TMP_ROOT.mkdir(parents=True, exist_ok=True)
                work = Path(stack.enter_context(tempfile.TemporaryDirectory(prefix="flight-", dir=TMP_ROOT)))
            bundle = build_bundle(roc, work / "bundle")
        url = stack.enter_context(serve(bundle.resolve()))
        print(f"flight: consumers import {url} ({PACKAGE} replaced)", flush=True)
        yield replace_dep(url)


def make_mirror(dest: Path, root: Path = ROOT) -> Path:
    """A copy of `root` at `dest` without the package's Roc sources: files
    are independent copies, package/ keeps only its
    data files, and package/main.roc is a sentinel that does not compile.
    Consumers run here prove they used the bundle."""
    root, dest = root.resolve(), dest.resolve()
    if dest == root or root.is_relative_to(dest):
        raise ValueError(f"refusing to mirror {root} into {dest}")
    if dest.exists():
        shutil.rmtree(dest)
    skip = {root / name for name in MIRROR_SKIP} | {TMP_ROOT, dest}
    for directory, subdirs, files in os.walk(root):
        here = Path(directory)
        target = dest / here.relative_to(root)
        target.mkdir(parents=True, exist_ok=True)
        kept = []
        for name in sorted(subdirs):
            path = here / name
            if path in skip or name == "__pycache__":
                continue
            if path.is_symlink():
                os.symlink(os.readlink(path), target / name)
            else:
                kept.append(name)
        subdirs[:] = kept
        in_package = here == root / "package" or here.is_relative_to(root / "package")
        for name in files:
            path = here / name
            if in_package and name.endswith(".roc"):
                continue
            if path.is_symlink():
                os.symlink(os.readlink(path), target / name)
                continue
            # Consumer files must stay consistent with the bundle prepared
            # for this run while implementation work continues. Hard links
            # allow in-place checkout edits to change an active mirror.
            shutil.copy2(path, target / name)
    (dest / "package").mkdir(exist_ok=True)
    (dest / "package" / "main.roc").write_text(SENTINEL, encoding="utf-8")
    return dest


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--roc", default=os.environ.get("ROC", "roc"), help="compiler (default: $ROC or roc)")
    parser.add_argument("--bundle", type=Path, help="serve this bundle instead of building one from package/")
    parser.add_argument("command", nargs="+", help="the command to run with ROC_FONT_BUNDLE_URL set")
    args = parser.parse_args(argv)
    roc = str(Path(args.roc).expanduser().resolve()) if "/" in args.roc else args.roc
    with flight(roc, bundle=args.bundle) as dep:
        env = dict(os.environ, **{URL_ENV: dep[-1]})
        return subprocess.run(args.command, env=env, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
