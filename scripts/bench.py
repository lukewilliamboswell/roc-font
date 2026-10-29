#!/usr/bin/env python3
"""Benchmark roc-font against HarfBuzz, ttf-parser, rustybuzz and fontTools,
and hold Roc allocation counts to a ratchet.

Every implementation is a small program speaking one protocol: it reads one
case file from stdin (`<operation>\\n<font length>\\n<font bytes><text>`),
prepares it outside the timed region, runs the operation N times (its last
argument) with the clock running only around that loop, and prints
{"iterations", "elapsed_ns", "successes", "checksum"} as one JSON line.

Modes:

    python3 scripts/bench.py --quick              timing smoke run, about two minutes
    python3 scripts/bench.py                      full timing comparison
    python3 scripts/bench.py --check              allocation ratchet only (fast)
    python3 scripts/bench.py --check --update-baseline
                                                  record new allocation counts
    python3 scripts/bench.py --update-baseline    full run: record allocation
                                                  counts and time ratios

Allocation counts come from bench/roc/alloc.roc built with `roc build --fuzz --opt=speed`
(roc-fuzz's Fuzz.measure_allocs!). They are deterministic for one compiler
and input, and are compared exactly with bench/baseline.json: any increase or
decrease fails until --update-baseline records it. The baseline records its
compiler; nothing pins the compiler (work uses the latest nightly), so after a
compiler change the ratchet says so and the baseline is re-recorded. Elapsed
time is compared only as a ratio against the other implementations measured
in the same run.

The Roc programs import the package bundle `roc bundle` makes, served on
loopback (scripts/flight.py), never package/ sources; `--source` compiles
package/ directly for quick local iteration only.

Reports go to .roc-font-tmp/bench/<label>/ (or $ROC_FONT_TMPDIR/bench/).
See docs/benchmarks.adoc.
"""
from __future__ import annotations

import argparse
import dataclasses
import datetime
import hashlib
import io
import json
import math
import os
import platform
import random
import re
import shutil
import statistics
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import flight  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / "bench"
BASELINE = BENCH / "baseline.json"
TMP_ROOT = Path(os.environ.get("ROC_FONT_TMPDIR", ROOT / ".roc-font-tmp")).resolve()
DEFAULT_OUT = TMP_ROOT / "bench"
INTER = ROOT / "tests" / "fonts" / "Inter-Regular-metrics.ttf"
CORPUS_DIR = ROOT / "tests" / "corpus"
CORPUS_MANIFEST = ROOT / "tests" / "corpus.json"
SCHEMA_VERSION = 1
OPS = ("read", "cmap", "advance", "kerning", "shape", "labels", "plan-labels")
SIZES = {"small": 512, "medium": 4096, "large": 32768}
# Label counts for the `labels` and `plan-labels` operations.
LABEL_COUNTS = {"small": 16, "medium": 128, "large": 1024}
FONTTOOLS_PIN = "4.61.1"


# ---------------------------------------------------------------------------
# Inputs: fonts and texts

def seed_for(name: str) -> int:
    """A fixed seed per input, independent of Python's hash randomisation."""
    return int.from_bytes(hashlib.sha256(name.encode()).digest()[:8], "big")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# Words that exercise Inter's default features: f-ligatures and contextual
# alternates (arrows, case-sensitive punctuation), kerning pairs, digits and
# a few accented letters. Nothing HarfBuzz would treat specially (no
# controls, no Unicode spaces), so checksums can agree across implementations.
WORDS = ("office", "affinity", "fjord", "waffle", "shuffle", "fluffy", "difficult", "efficient",
         "the", "of", "and", "a", "to", "in", "font", "glyph", "kerning", "shaping", "text", "pure",
         "Roc", "AVATAR", "Today", "Typography", "Wave", "Yolk", "LATTE", "Tempo", "VAT",
         "->", "=>", "<-", "-->", "1/2", "3x4", "12:30", "2026", "#1", "(a)", "[b]", "*A*",
         "café", "naïve", "über", "Zürich", "fiancée", "“quoted”", "‘single’", "—", "…")


def words_text(name: str, size: int) -> bytes:
    """Words and punctuation up to `size` bytes, never cutting a character."""
    rng = random.Random(seed_for(name))
    out, length = [], 0
    while True:
        word = rng.choice(WORDS)
        sep = rng.choice((" ", " ", " ", " ", ", ", ". "))
        piece = (word + sep).encode()
        if length + len(piece) > size:
            break
        out.append(piece)
        length += len(piece)
    return b"".join(out)


# Short Latin labels as a diagram or a form measures them: one to three
# words, a few with an f-ligature, kerning pairs or digits.
LABEL_WORDS = ("Start", "End", "Yes", "No", "OK", "Cancel", "Save", "Load", "User", "Server", "Database",
               "Request", "Response", "Error", "Retry", "Wait", "Login", "Logout", "Cache", "Queue",
               "Worker", "Config", "Profile", "Settings", "Offline", "Valid?", "Done", "Step 1", "Step 2",
               "API", "Auth", "Token", "Payment", "Order", "Invoice", "Tax", "AVA", "Yearly", "Week 12")


def labels_text(name: str, count: int) -> bytes:
    """`count` labels of one to three words, one per line."""
    rng = random.Random(seed_for(name))
    labels = [" ".join(rng.choice(LABEL_WORDS) for _ in range(rng.choice((1, 1, 2, 2, 3)))) for _ in range(count)]
    return "\n".join(labels).encode()


def sweep_text(name: str, code_points: list[int], count: int | None = None) -> bytes:
    rng = random.Random(seed_for(name))
    cps = list(code_points)
    rng.shuffle(cps)
    if count is not None:
        cps = cps[:count]
    return "".join(map(chr, cps)).encode()


def bmp_sweep() -> bytes:
    """Every scalar from U+0020 to U+2FFF except C1 controls, shuffled."""
    return sweep_text("cmap-sweep", [c for c in range(0x20, 0x3000) if not 0x7F <= c <= 0x9F])


def random_text(name: str, alphabet: list[str], size: int) -> bytes:
    rng = random.Random(seed_for(name))
    out, length = [], 0
    while True:
        piece = rng.choice(alphabet).encode()
        if length + len(piece) > size:
            break
        out.append(piece)
        length += len(piece)
    return b"".join(out)


@dataclasses.dataclass(frozen=True)
class FontInput:
    id: str
    kind: str  # committed | generated | corpus | corpus-malformed
    data: bytes
    origin: str


@dataclasses.dataclass(frozen=True)
class Case:
    font: FontInput
    op: str
    text_name: str  # "" for read
    text: bytes
    size: str  # small | medium | large | sweep | font

    @property
    def id(self) -> str:
        return f"{self.font.id}/{self.op}" + (f"/{self.text_name}" if self.text_name else "")

    @property
    def data(self) -> bytes:
        return f"{self.op}\n{len(self.font.data)}\n".encode() + self.font.data + self.text

    @property
    def optional(self) -> bool:
        return self.font.kind.startswith("corpus")


# Adversarial fonts, generated with fontTools from fixed recipes. head
# created/modified are fixed, so the bytes (and the SHA-256 recorded in the
# baseline for every case) are reproducible for one fontTools version.
HUGE_CMAP_GLYPHS = 30000
MANY_KERN_GLYPHS = 300
LIGA_LOOKUPS = 100
LIGA_PER_LETTER = 20
LETTERS = [chr(ord("a") + i) for i in range(26)]


def _build_font(names: list[str], cmap: dict[int, str], fea: str | None = None) -> bytes:
    from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
    from fontTools.fontBuilder import FontBuilder
    from fontTools.pens.ttGlyphPen import TTGlyphPen

    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap(cmap)
    pen = TTGlyphPen(None)
    pen.moveTo((50, 0))
    pen.lineTo((50, 700))
    pen.lineTo((450, 700))
    pen.lineTo((450, 0))
    pen.closePath()
    box = pen.glyph()
    # Outlines for the first glyphs only, so table sizes are dominated by the
    # structure under test rather than by glyf.
    fb.setupGlyf({n: (box if 0 < i <= 128 else TTGlyphPen(None).glyph()) for i, n in enumerate(names)})
    fb.setupHorizontalMetrics({n: (500 + (i % 7) * 10, 50) for i, n in enumerate(names)})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable({"familyName": "RocFontBench", "styleName": "Regular"})
    fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
    fb.setupPost(keepGlyphNames=False)
    if fea:
        addOpenTypeFeaturesFromString(fb.font, fea)
    fb.updateHead(created=0x7C25B080, modified=0x7C25B080)
    out = io.BytesIO()
    fb.save(out)
    return out.getvalue()


def huge_cmap_font() -> bytes:
    """30000 format 12 groups of one character each (stride 2 in plane 1,
    glyphs in reverse order so no two groups merge), plus ASCII."""
    n = HUGE_CMAP_GLYPHS
    names = [".notdef"] + [f"g{i}" for i in range(1, n + 1)]
    cmap = {0x10000 + 2 * i: names[n - i] for i in range(n)}
    cmap.update({0x20 + i: names[i + 1] for i in range(95)})
    return _build_font(names, cmap)


def many_kern_font() -> bytes:
    """A GPOS pair adjustment (format 1) for every ordered pair of 300 glyphs:
    90000 pairs, split over subtables by fontTools to fit 16-bit offsets."""
    n = MANY_KERN_GLYPHS
    names = [".notdef"] + [f"g{i}" for i in range(1, n + 1)]
    cmap = {0x4E00 + i: names[i + 1] for i in range(n)}
    rng = random.Random(seed_for("many-kern-pairs"))
    lines = [f"pos {names[a]} {names[b]} {rng.randrange(-80, 80)};"
             for a in range(1, n + 1) for b in range(1, n + 1)]
    return _build_font(names, cmap, "feature kern {\n" + "\n".join(lines) + "\n} kern;\n")


def many_liga_font() -> bytes:
    """100 ligature lookups in `liga`, each with 20 three-letter ligatures
    for every first letter: 52000 ligatures, many lookups over every run."""
    outs = [f"lig{i}" for i in range(LIGA_LOOKUPS * 26 * LIGA_PER_LETTER)]
    names = [".notdef", "space"] + LETTERS + outs
    cmap = {0x20: "space"} | {ord(c): c for c in LETTERS}
    rng = random.Random(seed_for("many-ligature-lookups"))
    fea, k = [], 0
    for lookup in range(LIGA_LOOKUPS):
        fea.append(f"lookup L{lookup} {{")
        for first in LETTERS:
            seen: set[tuple[str, str]] = set()
            while len(seen) < LIGA_PER_LETTER:
                seen.add((rng.choice(LETTERS), rng.choice(LETTERS)))
            for second, third in sorted(seen):
                fea.append(f"  sub {first} {second} {third} by {outs[k]};")
                k += 1
        fea.append(f"}} L{lookup};")
    fea.append("feature liga {")
    fea += [f"  lookup L{lookup};" for lookup in range(LIGA_LOOKUPS)]
    fea.append("} liga;")
    return _build_font(names, cmap, "\n".join(fea) + "\n")


GENERATED_FONTS = {
    "adv-huge-cmap": huge_cmap_font,
    "adv-many-kern-pairs": many_kern_font,
    "adv-many-ligature-lookups": many_liga_font,
}


def fonttools_version() -> str | None:
    try:
        import fontTools
    except ImportError:
        return None
    return getattr(fontTools, "version", "unknown")


def corpus_fonts(notes: dict[str, str]) -> list[FontInput]:
    """Fonts listed in tests/corpus.json and fetched into tests/corpus/ by
    scripts/fetch_corpus.py: single-file entries, and the named members of
    archive entries. Archives without named members (whole test suites) are
    left to the conformance tests. A file whose SHA-256 does not match its
    pin is skipped. Fonts tagged `malformed` get the `read` case only."""
    if not CORPUS_MANIFEST.exists():
        notes["corpus"] = "tests/corpus.json absent; no corpus fonts"
        return []
    try:
        entries = json.loads(CORPUS_MANIFEST.read_text()).get("entries", [])
    except (ValueError, AttributeError) as error:
        notes["corpus"] = f"tests/corpus.json unreadable: {error}"
        return []
    fonts, missing = [], []
    for entry in entries:
        entry_id = str(entry.get("id", ""))
        kind = "corpus-malformed" if "malformed" in entry.get("tags", []) else "corpus"
        if entry.get("kind") == "file":
            name = entry.get("filename") or str(entry.get("url", "")).rsplit("/", 1)[-1]
            files = {name: entry.get("sha256")}
        else:
            files = dict(entry.get("members", {}))
        for name, digest in sorted(files.items()):
            if Path(name).suffix.lower() not in (".ttf", ".otf"):
                continue
            path = CORPUS_DIR / entry_id / name
            if not path.is_file():
                missing.append(entry_id)
                continue
            data = path.read_bytes()
            if digest and str(digest).lower() != sha256(data):
                notes[f"corpus/{entry_id}"] = f"{name} does not match its SHA-256 in tests/corpus.json; skipped"
                continue
            font_id = f"corpus-{entry_id}" if len(files) == 1 else \
                f"corpus-{entry_id}-" + re.sub(r"[^A-Za-z0-9.]+", "-", Path(name).stem).lower()
            fonts.append(FontInput(font_id, kind, data, str(path.relative_to(ROOT))))
    if missing:
        notes["corpus"] = (f"not fetched: {', '.join(sorted(set(missing)))} "
                           "(python3 scripts/fetch_corpus.py adds them)")
    return fonts


def build_cases(notes: dict[str, str]) -> list[Case]:
    """The whole benchmark matrix. Every input is deterministic."""
    inter = FontInput("inter", "committed", INTER.read_bytes(), str(INTER.relative_to(ROOT)))
    words = {size: words_text(f"words-{size}", n) for size, n in SIZES.items()}
    cases = [Case(inter, "read", "", b"", "font"),
             Case(inter, "cmap", "bmp-sweep", bmp_sweep(), "sweep"),
             Case(inter, "advance", "words-medium", words["medium"], "medium")]
    for size, text in words.items():
        cases.append(Case(inter, "kerning", f"words-{size}", text, size))
        cases.append(Case(inter, "shape", f"words-{size}", text, size))
    for size, count in LABEL_COUNTS.items():
        text = labels_text(f"labels-{size}", count)
        cases.append(Case(inter, "labels", f"labels-{size}", text, size))
        cases.append(Case(inter, "plan-labels", f"labels-{size}", text, size))

    version = fonttools_version()
    if version is None:
        notes["adversarial fonts"] = "fontTools not importable; generated fonts skipped"
    else:
        if version != FONTTOOLS_PIN:
            notes["fontTools"] = f"{version} differs from pin {FONTTOOLS_PIN}; generated font hashes may differ"
        fonts = {name: FontInput(name, "generated", build(), f"scripts/bench.py {build.__name__} (fontTools {version})")
                 for name, build in GENERATED_FONTS.items()}
        cmap_font = fonts["adv-huge-cmap"]
        plane1 = list(range(0x10000, 0x10000 + 2 * HUGE_CMAP_GLYPHS + 2048))
        cases += [Case(cmap_font, "read", "", b"", "font"),
                  Case(cmap_font, "cmap", "plane1-sweep", sweep_text("plane1-sweep", plane1, 16384), "sweep")]
        kern_font = fonts["adv-many-kern-pairs"]
        cjk = [chr(0x4E00 + i) for i in range(MANY_KERN_GLYPHS)]
        cases.append(Case(kern_font, "read", "", b"", "font"))
        for size, n in SIZES.items():
            cases.append(Case(kern_font, "kerning", f"cjk-{size}", random_text(f"cjk-{size}", cjk, n), size))
        cases.append(Case(kern_font, "shape", "cjk-medium", random_text("cjk-medium", cjk, SIZES["medium"]), "medium"))
        liga_font = fonts["adv-many-ligature-lookups"]
        cases.append(Case(liga_font, "read", "", b"", "font"))
        for size, n in SIZES.items():
            cases.append(Case(liga_font, "shape", f"letters-{size}",
                              random_text(f"letters-{size}", LETTERS + [" "], n), size))

    for font in corpus_fonts(notes):
        cases.append(Case(font, "read", "", b"", "font"))
        if font.kind == "corpus":
            cases += [Case(font, "cmap", "bmp-sweep", bmp_sweep(), "sweep"),
                      Case(font, "shape", "words-medium", words["medium"], "medium")]
    return cases


def select(cases: list[Case], args) -> list[Case]:
    keep = {x for x in args.only.split(",") if x}
    ops = set(args.ops)

    def wanted(case: Case) -> bool:
        if case.op not in ops:
            return False
        if keep and not any(k in (case.id, case.font.id, case.size, case.op, case.font.kind, case.text_name)
                            for k in keep):
            return False
        return True

    return [c for c in cases if wanted(c)]


def write_cases(cases: list[Case], folder: Path) -> list[dict]:
    manifest = []
    folder.mkdir(parents=True, exist_ok=True)
    for case in cases:
        path = folder / (case.id.replace("/", "__") + ".case")
        path.write_bytes(case.data)
        manifest.append({"id": case.id, "op": case.op, "font": case.font.id, "font_kind": case.font.kind,
                         "font_origin": case.font.origin, "font_bytes": len(case.font.data),
                         "font_sha256": sha256(case.font.data), "text": case.text_name,
                         "text_bytes": len(case.text), "text_sha256": sha256(case.text),
                         "case_sha256": sha256(case.data), "path": path.name})
    return manifest


def case_path(case: Case, folder: Path) -> Path:
    return folder / (case.id.replace("/", "__") + ".case")


# ---------------------------------------------------------------------------
# Implementations

@dataclasses.dataclass(frozen=True)
class Impl:
    id: str  # lang/library
    lang: str
    command: list[str]
    ops: tuple[str, ...]
    notes: str


COMPARATORS = {
    "c/harfbuzz": (("read", "cmap", "advance", "shape"),
                   "system libharfbuzz via pkg-config: hb_face/hb_font creation plus loading cmap, hmtx, "
                   "GSUB and GPOS; hb_font_get_nominal_glyph; hb_font_get_glyph_h_advance; hb_shape"),
    "rust/ttf-parser": (("read", "cmap", "advance"),
                        "ttf-parser Face::parse plus GSUB/GPOS lookup lists; glyph_index; glyph_hor_advance"),
    "rust/rustybuzz": (("read", "shape"), "rustybuzz Face::from_slice; rustybuzz::shape"),
    "python/fonttools": (("read",), "fontTools TTFont plus ensureDecompiled (every table, outlines included)"),
}


def tool_version(command: list[str]) -> str:
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    lines = (result.stdout + result.stderr).strip().splitlines()
    return lines[0] if result.returncode == 0 and lines else ""


class Builder:
    def __init__(self, out: Path, roc: str, python: str, log, dep: list[str]):
        self.out = out
        self.roc = roc
        # flight.replace_dep arguments: the Roc programs import the served bundle.
        self.dep = dep
        self.python = python
        self.log = log
        self.skipped: dict[str, str] = {}
        self.versions: dict[str, object] = {}
        (out / "bin").mkdir(parents=True, exist_ok=True)
        (out / "logs").mkdir(parents=True, exist_ok=True)

    def run(self, name: str, command: list[str], cwd: Path = ROOT) -> bool:
        self.log(f"build {name}: {' '.join(command)}")
        try:
            result = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
        except OSError as error:
            self.skipped[name] = f"could not run {command[0]}: {error}"
            return False
        (self.out / "logs" / f"build-{name}.log").write_text(result.stdout + result.stderr)
        if result.returncode:
            self.skipped[name] = f"build failed: {(result.stdout + result.stderr)[-2000:]}"
        return result.returncode == 0

    def roc_version(self) -> str:
        if "roc" not in self.versions:
            self.versions["roc"] = tool_version([self.roc, "version"]) or "unknown"
            self.versions["roc_path"] = shutil.which(self.roc) or self.roc
            if "debug" in str(self.versions["roc"]):
                self.log(f"warning: {self.versions['roc']} is a debug compiler build; "
                         "set ROC to a release nightly for representative timings")
        return str(self.versions["roc"])

    def roc_impls(self) -> list[Impl]:
        self.roc_version()
        binary = self.out / "bin" / "roc-font"
        if not self.run("roc", [self.roc, "build", "--opt=speed", str(BENCH / "roc" / "font.roc"),
                                f"--output={binary}", *self.dep]):
            return []
        return [Impl("roc/roc-font", "roc", [str(binary)], OPS, "roc build --opt=speed")]

    def alloc_binary(self) -> Path | None:
        self.roc_version()
        binary = self.out / "bin" / "roc-alloc"
        if self.run("roc-alloc", [self.roc, "build", "--fuzz", "--opt=speed", str(BENCH / "roc" / "alloc.roc"), f"--output={binary}", *self.dep]):
            return binary
        return None

    def c_impls(self) -> list[Impl]:
        cc = os.environ.get("CC", "cc")
        if not shutil.which(cc) or not shutil.which("pkg-config"):
            self.skipped["c"] = "no C compiler or pkg-config"
            return []
        flags = subprocess.run(["pkg-config", "--cflags", "--libs", "harfbuzz"], capture_output=True, text=True)
        if flags.returncode:
            self.skipped["c"] = "pkg-config does not find harfbuzz"
            return []
        binary = self.out / "bin" / "c-harfbuzz"
        if not self.run("c", [cc, "-O2", "-o", str(binary), str(BENCH / "compare" / "c" / "harfbuzz.c"),
                              *flags.stdout.split()]):
            return []
        self.versions["harfbuzz"] = tool_version(["pkg-config", "--modversion", "harfbuzz"])
        self.versions["cc"] = tool_version([cc, "--version"])
        return self._impls("c", [str(binary)])

    def rust_impls(self) -> list[Impl]:
        if not shutil.which("cargo"):
            self.skipped["rust"] = "cargo not found"
            return []
        target = self.out / "rust-target"
        if not self.run("rust", ["cargo", "build", "--release", "--locked", "--target-dir", str(target)],
                        cwd=BENCH / "compare" / "rust"):
            return []
        self.versions["rustc"] = tool_version(["rustc", "--version"])
        lock = (BENCH / "compare" / "rust" / "Cargo.lock").read_text()
        self.versions["rust_crates"] = {n: v for n, v in re.findall(r'name = "([^"]+)"\nversion = "([^"]+)"', lock)
                                        if n in ("ttf-parser", "rustybuzz")}
        binary = target / "release" / "compare"
        return [Impl(name, "rust", [str(binary), name.split("/", 1)[1]], *COMPARATORS[name])
                for name in COMPARATORS if name.startswith("rust/")]

    def python_impls(self) -> list[Impl]:
        probe = subprocess.run([self.python, "-c", "import fontTools; print(fontTools.version)"],
                               capture_output=True, text=True)
        if probe.returncode:
            self.skipped["python"] = (f"fontTools not importable by {self.python}; "
                                      "pip install -r bench/compare/python/requirements.txt")
            return []
        version = probe.stdout.strip()
        self.versions["python"] = tool_version([self.python, "--version"])
        self.versions["fonttools"] = version
        if version != FONTTOOLS_PIN:
            self.log(f"warning: fontTools {version} differs from the pin {FONTTOOLS_PIN}")
        script = BENCH / "compare" / "python" / "compare.py"
        return [Impl("python/fonttools", "python", [self.python, str(script), "fonttools"],
                     *COMPARATORS["python/fonttools"])]

    def _impls(self, lang: str, command: list[str]) -> list[Impl]:
        return [Impl(name, lang, command, *COMPARATORS[name]) for name in COMPARATORS if name.startswith(lang + "/")]


# ---------------------------------------------------------------------------
# Measurement

class RunError(Exception):
    pass


_RUSAGE: dict[int, int] = {}


def _install_wait_hook() -> None:
    """Popen reaps children with waitpid; wrap it with wait4 to keep rusage."""
    if not hasattr(os, "wait4"):
        return
    original = os.waitpid

    def waitpid(pid: int, options: int):
        if pid > 0:
            got, status, usage = os.wait4(pid, options)
            if got:
                scale = 1 if sys.platform == "darwin" else 1024
                _RUSAGE[got] = usage.ru_maxrss * scale
            return got, status
        return original(pid, options)

    subprocess.os.waitpid = waitpid  # type: ignore[attr-defined]


def _gnu_time() -> str | None:
    """GNU time, if present. Linux carries a process's peak RSS across fork
    and exec, so a benchmark started straight from this (large) Python
    process reports the harness's peak; started from `time`, it reports its
    own plus a few MiB."""
    path = shutil.which("time") or ("/usr/bin/time" if Path("/usr/bin/time").exists() else None)
    if not path:
        return None
    try:
        probe = subprocess.run([path, "-f", "%M", "-o", os.devnull, "true"], capture_output=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return path if probe.returncode == 0 else None


GNU_TIME = _gnu_time()
RSS_SOURCE = ("GNU time %M of the batch process (includes about 2-4 MiB for time itself)" if GNU_TIME else
              "wait4 ru_maxrss; on Linux this includes the harness's own peak, so compare within a run only")


def run_once(command: list[str], data: bytes, iterations: int, timeout: float) -> dict:
    """Run one batch, returning its timing record plus the child's peak RSS."""
    rss_file = None
    if GNU_TIME:
        rss_file = TMP_ROOT / "bench" / f".rss-{os.getpid()}"
        rss_file.parent.mkdir(parents=True, exist_ok=True)
        command = [GNU_TIME, "-f", "%M", "-o", str(rss_file)] + command
    with subprocess.Popen(command + [str(iterations)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE) as proc:
        try:
            stdout, stderr = proc.communicate(data, timeout=timeout)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
            raise RunError(f"timed out after {timeout}s with {iterations} iterations")
        rss = _RUSAGE.pop(proc.pid, None)
        if rss_file is not None:
            try:
                rss = int(rss_file.read_text().split()[-1]) * 1024
            except (OSError, ValueError, IndexError):
                rss = None
        if proc.returncode:
            raise RunError(f"exit {proc.returncode}: {stderr.decode(errors='replace')[-500:]}")
    try:
        record = json.loads(stdout)
    except json.JSONDecodeError as error:
        raise RunError(f"bad output {stdout[:200]!r}") from error
    if record.get("iterations") != iterations or record.get("elapsed_ns", 0) <= 0:
        raise RunError(f"invalid timing record {record}")
    record["peak_rss_bytes"] = rss
    return record


def calibrate(first_ns: int, target_ns: int, max_iterations: int) -> int:
    """Iterations per batch so one batch takes about target_ns."""
    return max(1, min(max_iterations, math.ceil(target_ns / max(first_ns, 1))))


def summarize(per_op_ns: list[float]) -> dict:
    median = statistics.median(per_op_ns)
    return {
        "median_ns": median,
        "min_ns": min(per_op_ns),
        "max_ns": max(per_op_ns),
        "stdev_ns": statistics.stdev(per_op_ns) if len(per_op_ns) > 1 else 0.0,
        "spread_pct": 100 * (max(per_op_ns) - min(per_op_ns)) / median if median else 0.0,
    }


def measure(impl: Impl, case: Case, args) -> dict:
    record = {"impl": impl.id, "lang": impl.lang, "case": case.id, "op": case.op, "size": case.size,
              "font_bytes": len(case.font.data), "text_bytes": len(case.text)}
    data = case.data
    try:
        first = run_once(impl.command, data, 1, args.timeout)
        iterations = calibrate(first["elapsed_ns"], int(args.target_ms * 1e6), args.max_iterations)
        run_once(impl.command, data, iterations, args.timeout)  # warmup batch, discarded
        batches = [run_once(impl.command, data, iterations, args.timeout) for _ in range(args.repetitions)]
    except RunError as error:
        record["error"] = str(error)
        return record
    record.update(summarize([b["elapsed_ns"] / iterations for b in batches]))
    record["iterations"] = iterations
    record["accepted"] = batches[0]["successes"] == iterations
    # The checksum of a single operation, comparable across implementations.
    record["checksum"] = first["checksum"]
    if case.op != "read":
        bytes_per_op = len(case.text)
    else:
        bytes_per_op = len(case.font.data)
    record["mb_per_s"] = (bytes_per_op / 1e6) / (record["median_ns"] / 1e9) if record["median_ns"] else None
    rss = [b["peak_rss_bytes"] for b in batches if b.get("peak_rss_bytes")]
    record["peak_rss_bytes"] = max(rss) if rss else None
    record["batch_elapsed_ns"] = [b["elapsed_ns"] for b in batches]
    return record


FONT_REJECTED = "the font could not be read"
ALLOC_PATTERN = re.compile(r"ALLOCATION_DIAGNOSTIC allocations=(\d+) leaked=(\d+) result=(\w+) checksum=(\d+)")


def count_allocations(binary: Path, path: Path, timeout: float) -> dict:
    try:
        result = subprocess.run([str(binary), "replay", str(path)], capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"error": "allocation diagnostic timed out"}
    output = result.stdout + result.stderr
    match = ALLOC_PATTERN.search(output)
    if result.returncode != 77 or not match:
        error = re.search(r"ALLOCATION_DIAGNOSTIC error=(.*)", output)
        if error and error[1].startswith(FONT_REJECTED):
            # roc-font does not read this font, so the query cannot run; the
            # ratchet records that, and notices when it changes.
            return {"allocations": None, "leaked": None, "result": "font-rejected", "detail": error[1].strip()}
        detail = error[1] if error else output[-300:]
        return {"error": f"allocation diagnostic exit {result.returncode}: {detail}"}
    return {"allocations": int(match[1]), "leaked": int(match[2]), "result": match[3], "checksum": int(match[4])}


# ---------------------------------------------------------------------------
# The ratchet

RATCHETED = ("allocations", "leaked")


def load_baseline() -> dict:
    if not BASELINE.exists():
        return {}
    return json.loads(BASELINE.read_text())


def dump_baseline(baseline: dict) -> str:
    """Sorted keys, two-space indent, one trailing newline: a reviewable diff."""
    return json.dumps(baseline, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def ratchet(baseline: dict, measured: dict[str, dict], all_ids: set[str], compiler: str) -> list[dict]:
    """Compare measured allocation records with the baseline. Returns one
    finding per case that differs; `fail` findings make the check fail."""
    findings = []
    recorded = baseline.get("cases", {})
    for case_id in sorted(set(recorded) | set(measured)):
        old, new = recorded.get(case_id), measured.get(case_id)
        if new is None:
            if case_id in all_ids:
                continue  # in the matrix but filtered out of this run
            if old.get("optional"):
                findings.append({"case": case_id, "status": "skipped", "fail": False,
                                 "message": "optional corpus font not available in this checkout"})
            else:
                findings.append({"case": case_id, "status": "unmeasured", "fail": True,
                                 "message": "in the baseline but not in this run's matrix: its input is unavailable "
                                            "(generated fonts need fontTools) or the case was removed; if removal "
                                            "is intended, run --update-baseline"})
            continue
        if "error" in new:
            findings.append({"case": case_id, "status": "error", "fail": True, "message": new["error"]})
            continue
        if old is None:
            findings.append({"case": case_id, "status": "new", "fail": True,
                             "message": f"not in the baseline ({new['allocations']} allocations); "
                                        "run --update-baseline to record it"})
            continue
        if old.get("case_sha256") != new["case_sha256"]:
            findings.append({"case": case_id, "status": "input-changed", "fail": True,
                             "message": "the case input changed (font, text or generator); the counts are not "
                                        "comparable. Review, then run --update-baseline"})
            continue
        if (old.get("allocations") is None) != (new["allocations"] is None):
            now = "rejects" if new["allocations"] is None else "reads"
            findings.append({"case": case_id, "status": "font-acceptance-changed", "fail": True,
                             "message": f"roc-font now {now} this case's font; review, then run --update-baseline"})
            continue
        for key in RATCHETED:
            if old.get(key) == new[key]:
                continue
            worse = new[key] > old.get(key, 0)
            findings.append({"case": case_id, "status": "regression" if worse else "improvement", "fail": True,
                             "metric": key, "baseline": old.get(key), "measured": new[key],
                             "message": (f"{key} rose from {old.get(key)} to {new[key]}" if worse else
                                         f"{key} fell from {old.get(key)} to {new[key]}; lock it in with "
                                         "--update-baseline")})
    if any(f["fail"] for f in findings) and compiler_changed(baseline, compiler):
        # Listed first: after a compiler change, differing counts are expected.
        findings.insert(0, {"case": "-", "status": "compiler-changed", "fail": False,
                            "message": compiler_change_note(baseline, compiler)})
    return findings


def compiler_changed(baseline: dict, compiler: str) -> bool:
    base_compiler = baseline.get("compiler", {}).get("version")
    return bool(base_compiler) and base_compiler != compiler


def compiler_change_note(baseline: dict, compiler: str) -> str:
    """Allocation counts are compiler-specific, and nothing pins the
    compiler: CI and local work use the latest nightly. Differences measured
    with another compiler than the baseline's are expected and say nothing
    about this change on their own."""
    return (f"the baseline was recorded with {baseline['compiler']['version']}, this run used {compiler}. "
            "Allocation counts are compiler-specific, so differences are expected after a compiler change. "
            "Check that the same differences appear without your change (on the default branch), then "
            "re-baseline with this compiler: python3 scripts/bench.py --check --update-baseline")


def updated_baseline(baseline: dict, measured: dict[str, dict], cases: list[Case], filtered: bool,
                     versions: dict, ratios: dict | None, ratio_meta: dict | None) -> dict:
    old_cases = baseline.get("cases", {})
    by_id = {c.id: c for c in cases}
    new_cases: dict[str, dict] = {}
    if filtered:
        new_cases.update(old_cases)
    else:
        # Keep optional cases whose inputs are absent here, so a checkout
        # without the corpus does not erase them.
        new_cases.update({k: v for k, v in old_cases.items() if v.get("optional") and k not in by_id})
    for case_id, record in measured.items():
        if "error" in record:
            continue
        case = by_id[case_id]
        new_cases[case_id] = {
            "allocations": record["allocations"],
            "leaked": record["leaked"],
            **({"font_rejected": True} if record["allocations"] is None else {}),
            "case_sha256": record["case_sha256"],
            "font_sha256": sha256(case.font.data),
            "optional": case.optional,
        }
    result = {
        "schema": SCHEMA_VERSION,
        "about": "Allocation ratchet for scripts/bench.py --check; see docs/benchmarks.adoc. Counts are "
                 "roc_alloc plus roc_realloc calls made by one operation, measured with roc-fuzz "
                 "Fuzz.measure_allocs! in a `roc build --fuzz --opt=speed` binary.",
        "compiler": {"version": versions.get("roc", "unknown"), "build": "roc build --fuzz --opt=speed bench/roc/alloc.roc",
                     "roc_fuzz": "0.4.3"},
        "generator": {"fonttools": versions.get("fonttools_generator") or baseline.get("generator", {}).get("fonttools")},
        "cases": new_cases,
    }
    if ratios is not None:
        result["time_ratios"] = {**(ratio_meta or {}), "ratios": ratios}
    elif "time_ratios" in baseline:
        result["time_ratios"] = baseline["time_ratios"]
    return result


def sig2(x: float) -> float:
    """Two significant digits, so ratio updates are readable in review."""
    if x <= 0:
        return 0.0
    return float(f"{x:.2g}")


def time_ratios(results: list[dict]) -> dict[str, dict[str, float]]:
    """roc median / comparator median, per case and comparator."""
    by = {(r["impl"], r["case"]): r for r in results if "median_ns" in r}
    out: dict[str, dict[str, float]] = {}
    for (impl, case), r in sorted(by.items()):
        if impl == "roc/roc-font":
            continue
        mine = by.get(("roc/roc-font", case))
        if mine and mine["accepted"] and r["accepted"]:
            out.setdefault(case, {})[impl] = sig2(mine["median_ns"] / r["median_ns"])
    return out


def ratio_findings(baseline: dict, ratios: dict[str, dict[str, float]], tolerance: float) -> list[dict]:
    recorded = baseline.get("time_ratios", {}).get("ratios", {})
    findings = []
    for case, impls in sorted(ratios.items()):
        for impl, ratio in sorted(impls.items()):
            old = recorded.get(case, {}).get(impl)
            if old and ratio > old * (1 + tolerance):
                findings.append({"case": case, "impl": impl, "baseline": old, "measured": ratio,
                                 "message": f"roc/{impl} time ratio worsened from {old} to {ratio} "
                                            f"(tolerance {tolerance:.0%})"})
    return findings


# ---------------------------------------------------------------------------
# Reports

def geomean(values: list[float]) -> float | None:
    values = [v for v in values if v and v > 0]
    return math.exp(sum(map(math.log, values)) / len(values)) if values else None


def comparison(results: list[dict]) -> list[dict]:
    """Per operation and comparator: geometric mean over cases both accepted
    of roc median time / comparator median time."""
    by = {(r["impl"], r["case"]): r for r in results if "median_ns" in r}
    rows = []
    for op in OPS:
        roc = {case: r for (impl, case), r in by.items() if impl == "roc/roc-font" and r["op"] == op}
        impls = sorted({impl for (impl, case), r in by.items() if r["op"] == op and impl != "roc/roc-font"})
        for impl in impls:
            ratios, agree, cases = [], 0, 0
            for case, mine in roc.items():
                other = by.get((impl, case))
                if other and mine["accepted"] and other["accepted"]:
                    ratios.append(mine["median_ns"] / other["median_ns"])
                    cases += 1
                    agree += mine["checksum"] == other["checksum"]
            rows.append({"op": op, "impl": impl, "cases": cases, "roc_time_ratio": geomean(ratios),
                         "checksums_agree": agree})
    return rows


def fmt_ns(ns: float | None) -> str:
    if ns is None:
        return "-"
    for unit, scale in (("s", 1e9), ("ms", 1e6), ("µs", 1e3)):
        if ns >= scale:
            return f"{ns / scale:.3g} {unit}"
    return f"{ns:.3g} ns"


def fmt_ratio(ratio: float | None) -> str:
    if ratio is None:
        return "-"
    def num(x: float) -> str:
        return f"{x:,.0f}" if x >= 10 else f"{x:.2g}"
    return f"{num(ratio)}x slower" if ratio >= 1 else f"{num(1 / ratio)}x faster"


def markdown_report(report: dict) -> str:
    meta = report["metadata"]
    lines = [f"# roc-font benchmarks: {meta['label']}", "",
             f"- Date: {meta['date']}", f"- Machine: {meta['machine']['description']}",
             f"- OS: {meta['machine']['os']}", f"- Roc: {meta['versions'].get('roc', '?')}",
             f"- Commit: {meta['git']['commit'] or '(none)'}{' (dirty)' if meta['git']['dirty'] else ''}"]
    if meta.get("mode") == "timing":
        lines.append(f"- Mode: {'quick' if meta['quick'] else 'full'}, {meta['repetitions']} batches of about "
                     f"{meta['target_ms']} ms after a warmup batch")
    lines.append("")
    if meta["skipped"]:
        lines += ["Skipped: " + "; ".join(f"{k} ({v.splitlines()[0][:160]})" for k, v in sorted(meta["skipped"].items())), ""]
    if report.get("comparison"):
        lines += ["## Comparison", "",
                  "Geometric mean over cases both accepted of roc-font's median time over the library's. "
                  "\"3x slower\" means roc-font takes three times as long. *Agree* counts cases whose "
                  "single-operation checksum matched roc-font's.", "",
                  "| Operation | Library | Cases | roc-font is | Agree |", "| --- | --- | ---: | --- | ---: |"]
        for row in report["comparison"]:
            lines.append(f"| {row['op']} | {row['impl']} | {row['cases']} | {fmt_ratio(row['roc_time_ratio'])} | "
                         f"{row['checksums_agree']}/{row['cases']} |")
        lines.append("")
    if report.get("results"):
        lines += ["## Every measurement", "",
                  "| Case | Implementation | Median | Spread | MB/s | Peak RSS | Allocations | Checksum |",
                  "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
        allocs = report.get("allocations", {})
        for r in report["results"]:
            if "error" in r:
                lines.append(f"| {r['case']} | {r['impl']} | - | - | - | - | - | error: {r['error'][:80]} |")
                continue
            rss = f"{r['peak_rss_bytes'] / 2**20:.1f} MiB" if r.get("peak_rss_bytes") else "-"
            alloc = allocs.get(r["case"], {}).get("allocations", "-") if r["lang"] == "roc" else ""
            mbps = f"{r['mb_per_s']:.3g}" if r.get("mb_per_s") else "-"
            checksum = str(r["checksum"]) + ("" if r["accepted"] else " (rejected)")
            lines.append(f"| {r['case']} | {r['impl']} | {fmt_ns(r['median_ns'])} | {r['spread_pct']:.0f}% | "
                         f"{mbps} | {rss} | {alloc} | {checksum} |")
        lines.append("")
    lines += ["## Allocation ratchet", ""]
    allocs = report.get("allocations", {})
    if allocs:
        lines += ["| Case | Allocations | Leaked | Baseline |", "| --- | ---: | ---: | --- |"]
        base = report.get("baseline_cases", {})
        for case_id, record in sorted(allocs.items()):
            if "error" in record:
                lines.append(f"| {case_id} | - | - | error: {record['error'][:80]} |")
                continue
            old = base.get(case_id)
            status = "new" if old is None else ("same" if all(old.get(k) == record[k] for k in RATCHETED)
                                                 else f"was {old.get('allocations')}/{old.get('leaked')}")
            if record["allocations"] is None:
                lines.append(f"| {case_id} | font rejected | - | {status} |")
                continue
            lines.append(f"| {case_id} | {record['allocations']} | {record['leaked']} | {status} |")
        lines.append("")
    findings = report.get("ratchet", [])
    lines += ["Ratchet: " + ("passed" if not any(f["fail"] for f in findings) else "FAILED"), ""]
    lines += [f"- {f['case']}: {f['status']}: {f['message']}" for f in findings]
    for f in report.get("ratio_findings", []):
        lines.append(f"- {f['case']}: {f['message']}")
    return "\n".join(lines) + "\n"


def machine() -> dict:
    cpu = platform.processor()
    if Path("/proc/cpuinfo").exists():
        found = re.search(r"model name\s*:\s*(.*)", Path("/proc/cpuinfo").read_text())
        cpu = found[1] if found else cpu
    elif sys.platform == "darwin":
        cpu = tool_version(["sysctl", "-n", "machdep.cpu.brand_string"]) or cpu
    return {"description": f"{cpu} ({os.cpu_count()} CPUs, {platform.machine()})",
            "cpu": cpu, "cpus": os.cpu_count(), "arch": platform.machine(),
            "os": platform.platform(), "python": platform.python_version()}


def git_state() -> dict:
    commit = tool_version(["git", "-C", str(flight.checkout()), "rev-parse", "HEAD"])
    status = subprocess.run(["git", "-C", str(flight.checkout()), "status", "--porcelain", "--", "package", "bench", "scripts"],
                            capture_output=True, text=True).stdout
    return {"commit": commit, "dirty": bool(status.strip())}


# ---------------------------------------------------------------------------
# Command line

def parse_args(argv: list[str] | None = None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true",
                    help="allocation ratchet only: count allocations for every case and compare with the baseline")
    ap.add_argument("--update-baseline", action="store_true",
                    help="write bench/baseline.json from this run (allocations; time ratios too after a full run)")
    ap.add_argument("--quick", action="store_true", help="drop large texts, short batches; a smoke run")
    ap.add_argument("--label", default=None, help="report folder name (default: check, quick or full)")
    ap.add_argument("--output-dir", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--roc", default=os.environ.get("ROC", "roc"), help="Roc compiler (default: $ROC, then roc)")
    ap.add_argument("--python", default=sys.executable, help="interpreter with fontTools for the comparator")
    ap.add_argument("--ops", default=",".join(OPS), help="comma-separated operations: " + ",".join(OPS))
    ap.add_argument("--langs", default="roc,c,rust,python", help="comma-separated: roc,c,rust,python")
    ap.add_argument("--only", default="", help="comma-separated case ids, font ids, sizes, ops or text names")
    ap.add_argument("--repetitions", type=int, default=None)
    ap.add_argument("--target-ms", type=float, default=None, help="approximate duration of one batch")
    ap.add_argument("--max-iterations", type=int, default=1000000)
    ap.add_argument("--timeout", type=float, default=120.0, help="seconds allowed for one batch")
    ap.add_argument("--time-tolerance", type=float, default=0.25,
                    help="allowed worsening of a recorded time ratio in a full run (default 0.25)")
    ap.add_argument("--no-allocations", action="store_true", help="timing run without the allocation ratchet")
    ap.add_argument("--corpus-only", action="store_true", help="write the case files and manifest, then stop")
    ap.add_argument("--source", action="store_true",
                    help="build the Roc programs from package/ sources instead of the served bundle (quick local iteration)")
    args = ap.parse_args(argv)
    args.repetitions = args.repetitions or (3 if args.quick else 7)
    args.target_ms = args.target_ms or (20.0 if args.quick else 200.0)
    args.label = args.label or ("check" if args.check else "quick" if args.quick else "full")
    if args.repetitions < 1 or args.target_ms <= 0 or args.max_iterations < 1:
        ap.error("repetitions, target-ms and max-iterations must be positive")
    args.ops = tuple(o for o in args.ops.split(",") if o)
    unknown = set(args.ops) - set(OPS)
    if unknown:
        ap.error(f"unknown operations {sorted(unknown)}")
    args.langs = tuple(x for x in args.langs.split(",") if x)
    if (args.check or args.update_baseline) and args.no_allocations:
        ap.error("--check and --update-baseline measure allocations; drop --no-allocations")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    roc = str(Path(args.roc).expanduser().resolve()) if "/" in args.roc else args.roc
    with flight.flight(roc, source=args.source or args.corpus_only) as dep:
        return run(args, dep)


def run(args, dep: list[str]) -> int:
    out = args.output_dir.resolve() / args.label
    out.mkdir(parents=True, exist_ok=True)

    def log(message: str) -> None:
        print(message, file=sys.stderr, flush=True)

    notes: dict[str, str] = {}
    all_cases = build_cases(notes)
    all_ids = {c.id for c in all_cases}
    cases = select(all_cases, args)
    filtered = len(cases) != len(all_cases)
    case_dir = out / "cases"
    manifest = write_cases(cases, case_dir)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    for key, value in sorted(notes.items()):
        log(f"note: {key}: {value}")
    if args.corpus_only:
        log(f"wrote {len(cases)} cases to {case_dir}")
        return 0

    _install_wait_hook()
    builder = Builder(out, args.roc, args.python, log, dep)
    builder.versions["fonttools_generator"] = fonttools_version()
    baseline = load_baseline()
    sha_by_id = {m["id"]: m["case_sha256"] for m in manifest}

    # Allocation counts: deterministic, one replay per case.
    measured: dict[str, dict] = {}
    if args.check or not args.no_allocations:
        alloc = builder.alloc_binary()
        if alloc is None:
            log("error: the allocation diagnostic did not build; see logs/build-roc-alloc.log")
            return 2
        for case in cases:
            record = count_allocations(alloc, case_path(case, case_dir), args.timeout)
            record["case_sha256"] = sha_by_id[case.id]
            measured[case.id] = record
            log(f"alloc {case.id:52} " + (f"error: {record['error'][:100]}" if "error" in record else
                                          "font rejected by roc-font" if record["allocations"] is None else
                                          f"{record['allocations']:>8} allocations, {record['leaked']} leaked"))

    results: list[dict] = []
    impls: list[Impl] = []
    if not args.check:
        timed = [c for c in cases if not (args.quick and c.size == "large")]
        for lang in args.langs:
            impls += getattr(builder, f"{lang}_impls")()
        for case in timed:
            if measured.get(case.id, {}).get("result") == "font-rejected":
                log(f"time  {case.id:52} skipped: roc-font does not read this font")
                continue
            for impl in (i for i in impls if case.op in i.ops):
                record = measure(impl, case, args)
                if impl.lang == "roc" and FONT_REJECTED in record.get("error", ""):
                    log(f"time  {case.id:52} skipped: roc-font does not read this font")
                    break
                results.append(record)
                log(f"time  {case.id:52} {impl.id:18} " + (f"error: {record['error'][:80]}" if "error" in record else
                    f"{fmt_ns(record['median_ns']):>10} ±{record['spread_pct']:.0f}%"))

    compiler = builder.roc_version()
    findings = ratchet(baseline, measured, all_ids, compiler) if measured else []
    ratios = time_ratios(results) if results else {}
    full_timing = bool(results) and not args.quick and not filtered
    ratio_problems = ratio_findings(baseline, ratios, args.time_tolerance) if full_timing else []

    metadata = {
        "schema": SCHEMA_VERSION, "label": args.label, "mode": "check" if args.check else "timing",
        "quick": args.quick,
        "date": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "machine": machine(), "git": git_state(), "versions": builder.versions,
        "skipped": {**builder.skipped, **notes}, "repetitions": args.repetitions, "target_ms": args.target_ms,
        "implementations": [{"id": i.id, "ops": list(i.ops), "notes": i.notes} for i in impls],
        "cases": manifest,
        "peak_rss": RSS_SOURCE,
        "measurement": "in-process loop around one prepared operation; stdin, process start, preparation and "
                       "output are outside the timed region; median of per-operation time over batches",
    }
    report = {"metadata": metadata, "results": results, "comparison": comparison(results),
              "allocations": measured, "baseline_cases": baseline.get("cases", {}),
              "ratchet": findings, "ratio_findings": ratio_problems}
    (out / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    (out / "report.md").write_text(markdown_report(report))
    log(f"wrote {out / 'results.json'} and {out / 'report.md'}")

    if args.update_baseline:
        errors = [k for k, v in measured.items() if "error" in v]
        if errors:
            log(f"error: not updating the baseline; these cases failed: {', '.join(errors)}")
            return 1
        meta = None
        if full_timing:
            meta = {"tolerance": args.time_tolerance, "machine": machine()["description"],
                    "about": "roc-font median time / comparator median time, same run and machine"}
        new = updated_baseline(baseline, measured, cases, filtered, builder.versions,
                               ratios if full_timing else None, meta)
        before = dump_baseline(baseline) if baseline else ""
        after = dump_baseline(new)
        BASELINE.write_text(after)
        log(f"{'updated' if before != after else 'unchanged'}: {BASELINE.relative_to(ROOT)}")
        return 0

    for f in findings:
        log(f"ratchet {f['status']:>14}: {f['case']}: {f['message']}")
    for f in ratio_problems:
        log(f"time ratio: {f['case']}: {f['message']}")
    failed = any(f["fail"] for f in findings) or bool(ratio_problems)
    roc_errors = [r for r in results if r["lang"] == "roc" and "error" in r]
    if roc_errors or "roc" in builder.skipped:
        log("error: a Roc benchmark failed to build or run")
        failed = True
    if measured:
        ratchet_failed = any(f["fail"] for f in findings)
        log("ratchet: " + ("FAILED" if ratchet_failed else "passed")
            + ("" if baseline else " (no baseline yet; run --update-baseline)")
            + (" with a different compiler than the baseline's; see compiler-changed above"
               if ratchet_failed and compiler_changed(baseline, compiler) else ""))
    if not baseline and measured:
        failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
