#!/usr/bin/env python3
"""Build and run the roc-font roc-fuzz targets.

Every target is built natively with `roc build --fuzz` and run through the
binary's supervised `ci` command, which writes a report, a log and any
reproducing failure inputs. Working state lives under `.roc-font-tmp/fuzz/`
(or `$ROC_FONT_TMPDIR/fuzz/`):

    bin/<target>                 built target binaries
    corpus/<target>/             evolving campaign corpus, reseeded on every run
    smoke-corpus/<target>/       seeds only, recreated for every smoke run
    runs/<target>/<mode>/        last run's report.json, summary.md, run.log
    crashes/<target>/<sha256>    harvested failure inputs

Typical use:

    python3 scripts/run_fuzz.py smoke              # every target, short, seeded
    python3 scripts/run_fuzz.py campaign font-read --seconds=1800
    python3 scripts/run_fuzz.py show font-read .roc-font-tmp/fuzz/crashes/font-read/<sha>
    python3 scripts/run_fuzz.py minimize font-read <input> <output>
    python3 scripts/run_fuzz.py check-pin          # verify the roc-fuzz pin

Targets import the package bundle `roc bundle` makes, served on loopback
(scripts/flight.py), never package/ sources; `--source` compiles package/
directly for quick local iteration only.

Every harvested crash must be distilled into a permanent `## fuzz
regression:` expect before the fix lands; see docs/fuzzing.adoc.

Standard library only; deterministic apart from the fuzzing itself (smoke
runs pass a fixed `--seed`).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))
import flight  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]
FUZZ_ROOT = ROOT / "fuzz"
TMP_ROOT = Path(os.environ.get("ROC_FONT_TMPDIR", ROOT / ".roc-font-tmp")).resolve()
WORK_ROOT = TMP_ROOT / "fuzz"

# The roc-fuzz platform every target must declare. The bundle name is the
# content hash roc checks on download; sha256 is the release asset's digest
# (verified against `gh release view 0.4.3 --repo lukewilliamboswell/roc-fuzz`
# and the cached download), and commit is the tag's commit.
ROC_FUZZ_RELEASE = {
    "version": "0.4.3",
    "commit": "1abb6f0f76fc3ed6016cdf5da4e16e8ed1cfdfc4",
    "bundle": "41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
    "sha256": "d9bae1e93e6e94f3fafb4040861402dbab90af247023461d8e5451db4a3ae0f2",
}
ROC_FUZZ_URL = (
    "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/"
    f"{ROC_FUZZ_RELEASE['version']}/{ROC_FUZZ_RELEASE['bundle']}"
)
PLATFORM_RE = re.compile(r'platform\s+"([^"]+)"')

# Real fonts used as seeds, from the committed fixtures and the fetched
# corpus (tests/corpus/, created by scripts/fetch_corpus.py; may be absent).
FONT_DIRS = (ROOT / "tests" / "fonts", ROOT / "tests" / "corpus")
FONT_SUFFIXES = (".ttf", ".otf", ".ttc", ".otc")

# Inputs per target in a smoke run, unless the target sets its own.
SMOKE_RUNS = 4000


@dataclass(frozen=True)
class TargetConfig:
    # Candidate sources, first existing wins. Targets import the package
    # through package/main.roc, as consumers do, and the test-only builders
    # through tests/support/main.roc (see docs/fuzzing.adoc, "Layout").
    sources: tuple[Path, ...]
    seeds: Path
    dictionary: Path
    # Bytes put before each real font file to make a seed (font-shape reads
    # text, a 0xFF marker, then a font).
    font_prefix: bytes
    max_input_size: int
    timeout: int
    contract: str
    # Whether real font files from tests/fonts/ and tests/corpus/ seed the
    # target (only for targets that read whole font files).
    font_files: bool = True
    # Inputs a smoke run gives the target, when --runs does not say;
    # targets whose every input builds and checks large fonts take fewer,
    # so that smoke stays a few seconds per target.
    smoke_runs: int = SMOKE_RUNS

    def source(self) -> Path:
        for candidate in self.sources:
            if candidate.is_file():
                return candidate
        raise ValueError(
            "no source for target; looked for "
            + ", ".join(str(path.relative_to(ROOT)) for path in self.sources)
        )


TARGETS: dict[str, TargetConfig] = {
    "font-read": TargetConfig(
        sources=(FUZZ_ROOT / "font-read.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-read.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "font.dict",
        font_prefix=b"",
        max_input_size=262144,
        timeout=10,
        contract=(
            "reading is total and deterministic; a rejection names a problem; "
            "an accepted font has finite metrics and total queries; "
            "substitution keeps clusters in range and grows at most 4n+32; "
            "reading cost grows linearly (2 vs 16 copies) and leaks nothing"
        ),
    ),
    "font-shape": TargetConfig(
        sources=(FUZZ_ROOT / "font-shape.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-shape.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "font.dict",
        font_prefix="office -> A*B fi".encode("utf-8") + b"\xff",
        max_input_size=262144,
        timeout=10,
        contract=(
            "substitution is deterministic, keeps clusters in range and "
            "grows at most 4n+32 (36 per character); kerning is one finite "
            "value per glyph; widths are deterministic and finite; shaping "
            "cost grows linearly (2 vs 16 copies) and leaks nothing"
        ),
    ),
    # Narrow targets (architecture §7.3): the input chooses the contents of
    # a font exercising one feature, built at two sizes. Real fonts are not
    # seeds (font_files=False): their bytes would only be read as choices.
    "font-cmap": TargetConfig(
        sources=(FUZZ_ROOT / "font-cmap.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-cmap.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=64,
        timeout=10,
        contract=(
            "one cmap format (0, 4, 6, 10, 12, 13) at 2 and 16 copies: reads; "
            "every lookup and the code point listing agree with the built map; "
            "reading linear, lookups constant per call, listing linear; no leaks"
        ),
        font_files=False,
    ),
    "font-coverage": TargetConfig(
        sources=(FUZZ_ROOT / "font-coverage.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-coverage.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=64,
        timeout=10,
        contract=(
            "coverage and class definition formats via GSUB single and GPOS "
            "class kerning at 2 and 16 copies: substitutes and width match the "
            "recipe; runs aligned, clusters in range; reading linear, shaping "
            "constant per call; no leaks"
        ),
        font_files=False,
    ),
    "font-gsub": TargetConfig(
        sources=(FUZZ_ROOT / "font-gsub.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-gsub.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=96,
        timeout=10,
        contract=(
            "one GSUB lookup kind (1, 2, 4, 5, 6, 7) at 8 and 64 lookups: "
            "lookups that never match leave the run unchanged; runs aligned, "
            "deterministic, clusters in range and order; reading and planning "
            "O(lookups), shaping constant per call; no leaks"
        ),
        font_files=False,
    ),
    "font-indic": TargetConfig(
        sources=(FUZZ_ROOT / "font-indic.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-indic.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=256,
        timeout=10,
        contract=(
            "Devanagari syllables, reph, matras, join controls and broken "
            "clusters in two real families: aligned deterministic bounded "
            "runs, original clusters, feature masks, linear allocations and no leaks"
        ),
        font_files=False,
    ),
    "font-khmer": TargetConfig(
        sources=(FUZZ_ROOT / "font-khmer.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-khmer.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=256,
        timeout=10,
        contract=(
            "Khmer coeng-Ro, split matras, join controls and broken "
            "clusters in two real families: aligned deterministic bounded "
            "runs, original clusters, feature masks, linear allocations and no leaks"
        ),
        font_files=False,
    ),
    "font-use": TargetConfig(
        sources=(FUZZ_ROOT / "font-use.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-use.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=4096,
        timeout=10,
        contract="USE syllable machines and joining across Tibetan, Sinhala, NKo, Adlam and Mongolian: aligned deterministic bounded runs, original clusters, feature masks, linear allocations and no leaks",
        font_files=False,
    ),
    "font-myanmar": TargetConfig(
        sources=(FUZZ_ROOT / "font-myanmar.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-myanmar.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=256,
        timeout=10,
        contract="Myanmar syllables and reordering across two real families: aligned deterministic bounded runs, original clusters, feature masks, linear allocations and no leaks",
        font_files=False,
    ),
    "font-position-context": TargetConfig(
        sources=(FUZZ_ROOT / "font-position-context.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-position-context.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=1048576,
        timeout=10,
        contract="GPOS contextual record fanout, nested order, ignored inputs and resource bounds: deterministic aligned runs, exact work limits, flat allocation scaling and no leaks",
        font_files=True,
    ),
    "font-arabic-stretch": TargetConfig(
        sources=(FUZZ_ROOT / "font-arabic-stretch.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-arabic-stretch.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=4096,
        timeout=10,
        contract="Arabic presentation fallback, Windows glyph heuristics and Syriac stretching: deterministic aligned bounded runs, original clusters, trace origins, scaling and no leaks",
        font_files=False,
    ),
    "font-arabic": TargetConfig(
        sources=(FUZZ_ROOT / "font-arabic.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-arabic.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=32,
        timeout=10,
        contract=(
            "Arabic joining and positioning in two real families at 2/16 "
            "text sizes: join controls, both directions and cluster levels, "
            "bounded deterministic runs and linear allocations; no leaks"
        ),
        font_files=False,
    ),
    "font-thai-lao": TargetConfig(
        sources=(FUZZ_ROOT / "font-thai-lao.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-thai-lao.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=32,
        timeout=10,
        contract=(
            'Thai/Lao Sara Am, legacy glyph fallback and GPOS at 2/16 text sizes: both cluster levels, deterministic aligned bounded runs, linear allocations and no leaks'
        ),
        font_files=False,
    ),
    "font-hangul": TargetConfig(
        sources=(FUZZ_ROOT / "font-hangul.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-hangul.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=32,
        timeout=10,
        contract=(
            'Hangul composition, Jamo features and tone placement in seven real/generated font modes at 2/16 text sizes: deterministic aligned bounded runs, linear allocations and no leaks'
        ),
        font_files=False,
    ),
    "font-color": TargetConfig(
        sources=(FUZZ_ROOT / "font-color.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-color.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=1048576,
        timeout=10,
        contract=(
            "CPAL/COLR at 8/64/256 glyphs: finite bounded deterministic paint "
            "graphs, all formats and variations, linear preparation, constant "
            "per-glyph allocations with unrelated glyph count; no leaks"
        ),
        font_files=True,
    ),
    "font-color-images": TargetConfig(
        sources=(FUZZ_ROOT / "font-color-images.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-color-images.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=65536,
        timeout=10,
        contract=(
            "SVG/sbix/CBDT encoded glyph assets at 8/64 glyphs, all CBLC "
            "index formats, duplicate chains, exact native strike metrics, "
            "deterministic payloads, linear allocation growth and no leaks"
        ),
        font_files=True,
    ),
    "font-outlines": TargetConfig(
        sources=(FUZZ_ROOT / "font-outlines.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-outlines.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=65536,
        timeout=10,
        contract=(
            "TrueType paths and caret facts at 32/128/512 points: finite "
            "bounded deterministic geometry, variable locations, explicit "
            "absence and cardinality, linear allocation growth; no leaks"
        ),
        font_files=True,
    ),
    "font-position": TargetConfig(
        sources=(FUZZ_ROOT / "font-position.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-position.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=65536,
        timeout=10,
        contract=(
            "GPOS single, cursive, marks and contextual lookups at two "
            "generated sizes: deterministic finite aligned runs, bounded "
            "nested application, linear allocation growth; no leaks"
        ),
        font_files=True,
    ),
    "font-metadata": TargetConfig(
        sources=(FUZZ_ROOT / "font-metadata.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-metadata.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=65536,
        timeout=10,
        contract=(
            "original font metadata, raw tables and signed bearings at "
            "4/32/256 glyphs; original byte equality, bounds, totality, "
            "determinism, linear reading, constant per-query allocations; no leaks"
        ),
        font_files=True,
    ),
    "font-vertical": TargetConfig(
        sources=(FUZZ_ROOT / "font-vertical.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-vertical.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=128,
        timeout=10,
        contract='Real Japanese vertical TTB/BTT shaping: index alignment, deterministic bounded growth, zero horizontal advances, finite positions, two generated run sizes and no leaks',
        font_files=True,
    ),
    "font-vertical-tables": TargetConfig(
        sources=(FUZZ_ROOT / "font-vertical-tables.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-vertical-tables.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=65536,
        timeout=10,
        contract='Vertical vhea/vmtx/VORG/VVAR parsing, corruption, strict and lenient reading, total deterministic queries and 16-fold metric-array scaling; no leaks',
        font_files=True,
    ),
    "font-cff": TargetConfig(
        sources=(FUZZ_ROOT / "font-cff.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-cff.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=1048576,
        timeout=10,
        contract='CFF1/CID/CFF2 cubic paths, calculator and blend programs: total finite deterministic queries, malformed data, glyph bounds, 16/64/256 operator allocation scaling and no leaks',
        font_files=True,
    ),
    "font-variation-complete": TargetConfig(
        sources=(FUZZ_ROOT / "font-variation-complete.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-variation-complete.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=2097152,
        timeout=10,
        contract='gvar phantom metrics, composite metrics, avar2 cross-axis and scalar-cache arithmetic, duplicate axis tags, real high-axis fonts, finite deterministic total queries and narrow three-size scaling',
        font_files=True,
    ),
    "font-math": TargetConfig(
        sources=(FUZZ_ROOT / "font-math.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-math.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=1048576,
        timeout=10,
        contract=(
            "MATH constants, corrections, corner kerns and constructions: "
            "total deterministic queries, variation locations, absent and "
            "corrupted tables; generated 8/64/256 glyph coverage sizes with "
            "linear reading and constant per-query allocations; no leaks"
        ),
        font_files=True,
    ),
    "font-gpos": TargetConfig(
        sources=(FUZZ_ROOT / "font-gpos.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-gpos.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=64,
        timeout=10,
        contract=(
            "GPOS pair formats 1 and 2 and kern at 2 and 16 copies: the width "
            "is the advances plus the recipe's kerning; both sizes agree; runs "
            "aligned; reading linear, shaping constant per call; no leaks"
        ),
        font_files=False,
    ),
    "font-var": TargetConfig(
        sources=(FUZZ_ROOT / "font-var.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-var.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=128,
        timeout=10,
        contract=(
            "fvar/avar/HVAR/MVAR at 32 and 256 glyphs: read in full; at() and "
            "queries total and deterministic at fuzzed locations; advances "
            "finite, non-negative, hmtx at the default; sizes agree; reading "
            "linear, at() and advances constant per query; no leaks"
        ),
        font_files=False,
    ),
    "font-gvar": TargetConfig(
        sources=(FUZZ_ROOT / "font-gvar.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-gvar.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=72,
        timeout=10,
        contract=(
            "glyf outlines (simple, composite, nested) with gvar at 16 and 128 "
            "glyphs: read strictly in full; extents total and deterministic, "
            "the header box at the default, the recipe's model at -1/0/1 "
            "corners, within the deltas elsewhere; sizes agree; reading "
            "linear, at() and extents constant per query; no leaks"
        ),
        font_files=False,
        smoke_runs=1500,
    ),
    "font-layout-var": TargetConfig(
        sources=(FUZZ_ROOT / "font-layout-var.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-layout-var.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=72,
        timeout=10,
        contract=(
            "GPOS pair kerning with GDEF store devices and GSUB/GPOS "
            "FeatureVariations at 24 and 192 glyphs: read strictly in full; "
            "glyphs and width equal the recipe's model at every location; "
            "sizes agree; reading linear, shaping constant per call, "
            "planning plus one per extra record; no leaks"
        ),
        font_files=False,
        smoke_runs=1500,
    ),
    "font-ots": TargetConfig(
        sources=(FUZZ_ROOT / "font-ots.roc",),
        seeds=FUZZ_ROOT / "seeds" / "font-ots.json",
        dictionary=FUZZ_ROOT / "dictionaries" / "narrow.dict",
        font_prefix=b"",
        max_input_size=96,
        timeout=10,
        contract=(
            "head, cmap, GSUB, post or name damaged in a valid font at 2 and "
            "16 copies: undamaged fonts read in full; reading deterministic; "
            "every problem names exactly the damaged table; strict agrees; "
            "accepted fonts total for queries and shaping; reading linear; "
            "no leaks"
        ),
        font_files=False,
        smoke_runs=1500,
    ),
}
TARGET_ORDER = tuple(TARGETS)

SMOKE_SEED = 1


# ----------------------------------------------------------------- helpers


def resolve_command(command: str) -> str:
    if "/" in command or "\\" in command:
        return str(Path(command).expanduser().resolve())
    return command


def display(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def command_output(command: Sequence[str]) -> str:
    try:
        completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    except OSError as problem:
        return f"unavailable: {problem}"
    return (completed.stdout.strip() or completed.stderr.strip()) or f"exit {completed.returncode}"


def git_revision() -> str:
    """The commit under test, `+dirty` when the tree differs from it."""
    try:
        head = subprocess.run(["git", "rev-parse", "--verify", "-q", "HEAD"], cwd=flight.checkout(),
                              capture_output=True, text=True, check=False)
        status = subprocess.run(["git", "status", "--porcelain"], cwd=flight.checkout(),
                                capture_output=True, text=True, check=False)
    except OSError:
        return "unknown"
    revision = head.stdout.strip() if head.returncode == 0 else "no-commit"
    return revision + ("+dirty" if status.stdout.strip() else "")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def resolve_targets(requested: Sequence[str]) -> list[str]:
    if not requested or list(requested) == ["all"]:
        return list(TARGET_ORDER)
    if "all" in requested:
        raise ValueError("`all` cannot be combined with individual target names")
    unknown = sorted(set(requested) - set(TARGETS))
    if unknown:
        raise ValueError(
            f"unknown fuzz target(s): {', '.join(unknown)}; choose from {', '.join(TARGET_ORDER)}"
        )
    seen: set[str] = set()
    return [name for name in requested if not (name in seen or seen.add(name))]


# ------------------------------------------------------------- the pin


def roc_cache_dir() -> Path:
    base = os.environ.get("XDG_CACHE_HOME")
    if sys.platform == "darwin":
        default = Path.home() / "Library" / "Caches"
    else:
        default = Path.home() / ".cache"
    return (Path(base) if base else default) / "roc" / "packages"


def check_pin(quiet: bool = False) -> list[str]:
    """Problems with the roc-fuzz pin: a target declaring another platform,
    or a cached download whose digest differs from the release's."""
    problems: list[str] = []
    for name in TARGET_ORDER:
        try:
            source = TARGETS[name].source()
        except ValueError as problem:
            problems.append(f"{name}: {problem}")
            continue
        urls = PLATFORM_RE.findall(source.read_text(encoding="utf-8"))
        if urls != [ROC_FUZZ_URL]:
            problems.append(
                f"{display(source)} declares platform {urls or 'none'}, expected the pinned {ROC_FUZZ_URL}"
            )
    stem = ROC_FUZZ_RELEASE["bundle"].removesuffix(".tar.zst")
    cached = roc_cache_dir() / stem / ROC_FUZZ_RELEASE["bundle"]
    if cached.is_file():
        digest = sha256_bytes(cached.read_bytes())
        if digest != ROC_FUZZ_RELEASE["sha256"]:
            problems.append(f"cached {cached} has SHA-256 {digest}, expected {ROC_FUZZ_RELEASE['sha256']}")
        elif not quiet:
            print(f"roc-fuzz {ROC_FUZZ_RELEASE['version']}: cached bundle digest matches ({cached})")
    elif not quiet:
        print(f"roc-fuzz {ROC_FUZZ_RELEASE['version']}: no cached bundle at {cached} yet; roc checks the content hash on download")
    return problems


# ------------------------------------------------------------- seeding


def load_seeds(path: Path) -> list[bytes]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as problem:
        raise ValueError(f"could not read seeds from {display(path)}: {problem}") from problem
    seeds = document.get("seeds") if isinstance(document, dict) else None
    if not isinstance(seeds, list):
        raise ValueError(f"{display(path)} must be an object with a `seeds` list")
    result: list[bytes] = []
    for index, seed in enumerate(seeds):
        where = f"{display(path)} seed {index}"
        if not isinstance(seed, dict) or not isinstance(seed.get("why"), str):
            raise ValueError(f"{where}: each seed needs a `why` string and `parts`")
        parts = seed.get("parts")
        if not isinstance(parts, list):
            raise ValueError(f"{where}: `parts` must be a list")
        data = bytearray()
        for part in parts:
            if not isinstance(part, dict) or len(part) != 1:
                raise ValueError(f"{where}: each part is one of {{text}}, {{hex}} or {{file}}")
            (kind, value), = part.items()
            if kind == "text" and isinstance(value, str):
                data += value.encode("utf-8")
            elif kind == "hex" and isinstance(value, str):
                try:
                    data += bytes.fromhex(value)
                except ValueError as problem:
                    raise ValueError(f"{where}: bad hex: {problem}") from problem
            elif kind == "file" and isinstance(value, str):
                data += (ROOT / value).read_bytes()
            else:
                raise ValueError(f"{where}: unknown part {part!r}")
        result.append(bytes(data))
    return result


def font_files() -> list[Path]:
    found: list[Path] = []
    for directory in FONT_DIRS:
        if directory.is_dir():
            found.extend(
                path for path in directory.rglob("*")
                if path.is_file() and path.suffix.lower() in FONT_SUFFIXES
            )
    return sorted(found)


def prepare_corpus(name: str, max_input_size: int, fresh: bool) -> Path:
    """The corpus directory for a run, seeded. A fresh corpus (smoke runs)
    holds only the seeds, so a smoke result depends only on the sources,
    the seeds, the fonts present and the libFuzzer seed; campaigns keep
    growing one persistent corpus per target."""
    config = TARGETS[name]
    destination = WORK_ROOT / ("smoke-corpus" if fresh else "corpus") / name
    if fresh and destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True, exist_ok=True)
    written = skipped = 0

    def add(data: bytes, label: str) -> None:
        nonlocal written, skipped
        if len(data) > max_input_size:
            skipped += 1
            return
        path = destination / f"{label}-{sha256_bytes(data)[:32]}"
        if not path.exists():
            path.write_bytes(data)
        written += 1

    for data in load_seeds(config.seeds):
        add(data, "seed")
    fonts = font_files() if config.font_files else []
    for font in fonts:
        add(config.font_prefix + font.read_bytes(), "font")
    corpus_note = "" if not config.font_files or (ROOT / "tests" / "corpus").is_dir() else "; tests/corpus/ absent (run scripts/fetch_corpus.py for more seeds)"
    print(
        f"{name}: corpus {display(destination)}: {written} seeds present"
        f" ({len(fonts)} font files found, {skipped} over the {max_input_size}-byte input bound skipped){corpus_note}",
        flush=True,
    )
    return destination


# ------------------------------------------------------------- building


def binary_path(name: str) -> Path:
    return WORK_ROOT / "bin" / name


def build_target(name: str, args: argparse.Namespace) -> int:
    output = binary_path(name)
    if args.no_build:
        if not output.is_file():
            print(f"error: --no-build given but {display(output)} does not exist", file=sys.stderr)
            return 2
        return 0
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [args.roc, "build", "--fuzz", display(TARGETS[name].source()), f"--output={output}", *args.dep]
    print(f"+ {shlex.join(command)}", flush=True)
    try:
        return subprocess.run(command, cwd=ROOT, check=False).returncode
    except OSError as problem:
        print(f"error: could not run roc: {problem}", file=sys.stderr)
        return 2


# ------------------------------------------------------------- running


def harvest(name: str, report_dir: Path) -> list[Path]:
    failures = report_dir / "failures"
    if not failures.is_dir():
        return []
    destination = WORK_ROOT / "crashes" / name
    destination.mkdir(parents=True, exist_ok=True)
    kept: list[Path] = []
    for failure in sorted(failures.rglob("*")):
        if failure.is_file():
            data = failure.read_bytes()
            path = destination / sha256_bytes(data)
            if not path.exists():
                path.write_bytes(data)
            kept.append(path)
    return kept


def print_crash_instructions(name: str, crashes: Sequence[Path]) -> None:
    print(f"\n{name}: {len(crashes)} failure input(s) harvested:", file=sys.stderr)
    for crash in crashes:
        print(f"  {display(crash)}", file=sys.stderr)
    example = display(crashes[0]) if crashes else "<input>"
    print(
        f"""
To turn each failure into a permanent regression:
  1. python3 scripts/run_fuzz.py show {name} {example}
  2. python3 scripts/run_fuzz.py replay {name} {example}
  3. python3 scripts/run_fuzz.py minimize {name} {example} {display(WORK_ROOT / 'minimized' / name)}/<short-name>
  4. Rebuild the minimal input with FontBuild (or as literal bytes) and add a
     top-level expect to the matching module of tests/api/, documented with a
     `## fuzz regression:` comment naming the target, the contract broken
     and the cause. It must fail before the fix and pass after.
  5. Fix the reader or shaper, then rerun this target with the same corpus.
See docs/fuzzing.adoc, "Distilling failures".""",
        file=sys.stderr,
    )


def run_target(name: str, mode: str, args: argparse.Namespace) -> dict[str, object]:
    config = TARGETS[name]
    max_input_size = args.max_input_size or config.max_input_size
    result: dict[str, object] = {"target": name, "outcome": "error", "crashes": []}
    if not config.dictionary.is_file():
        raise ValueError(f"missing fuzz dictionary: {display(config.dictionary)}")
    corpus = prepare_corpus(name, max_input_size, fresh=mode == "smoke")
    status = build_target(name, args)
    if status != 0:
        result["outcome"] = "build failed"
        return result

    report_dir = WORK_ROOT / "runs" / name / mode
    if report_dir.exists():
        shutil.rmtree(report_dir)
    report_dir.parent.mkdir(parents=True, exist_ok=True)
    command = [
        str(binary_path(name)),
        "ci",
        str(report_dir),
        str(corpus),
        f"--max-input-size={max_input_size}",
        f"--timeout={args.timeout or config.timeout}",
        f"--memory-limit={args.memory_limit}",
        f"--dictionary={config.dictionary}",
        "--print-final-stats",
        f"--source-revision={git_revision()}",
        f"--roc-version={command_output([args.roc, 'version'])}",
        f"--platform-release={ROC_FUZZ_RELEASE['version']}",
        f"--platform-sha256={ROC_FUZZ_RELEASE['sha256']}",
    ]
    if mode == "smoke":
        command += [f"--runs={args.runs or config.smoke_runs}", f"--seed={args.seed}"]
    else:
        command += [f"--time={args.seconds}"]
        if args.seed is not None:
            command.append(f"--seed={args.seed}")
    print(f"+ {shlex.join(command)}", flush=True)
    log_tail: list[str] = []
    try:
        completed = subprocess.run(command, cwd=report_dir.parent, check=False, capture_output=True, text=True, errors="replace")
        output = (completed.stdout or "") + (completed.stderr or "")
        log_tail = output.strip().splitlines()[-8:]
        return_code = completed.returncode
    except OSError as problem:
        print(f"error: could not run {name}: {problem}", file=sys.stderr)
        return result

    report_path = report_dir / "report.json"
    report: dict[str, object] = {}
    if report_path.is_file():
        report = json.loads(report_path.read_text(encoding="utf-8"))
    libfuzzer = report.get("libfuzzer") or {}
    result.update(
        outcome=report.get("outcome") or f"exit {return_code}",
        finding=report.get("finding_kind"),
        units=(libfuzzer or {}).get("executed_units"),
        edges=(libfuzzer or {}).get("coverage_edges"),
        rss=(libfuzzer or {}).get("peak_rss_mb"),
        duration_ms=report.get("duration_ms"),
        report=display(report_dir),
        return_code=return_code,
    )
    if return_code != 0 or result["outcome"] != "passed":
        print("\n".join(log_tail), file=sys.stderr)
        crashes = harvest(name, report_dir)
        result["crashes"] = [display(path) for path in crashes]
        print_crash_instructions(name, crashes)
    return result


def run_mode(args: argparse.Namespace) -> int:
    problems = check_pin(quiet=True)
    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        return 2
    results = [run_target(name, args.command, args) for name in resolve_targets(args.targets)]
    print(f"\nfuzz {args.command} summary (roc-fuzz {ROC_FUZZ_RELEASE['version']}, work dir {display(WORK_ROOT)}):")
    for result in results:
        print(
            f"  {result['target']:<12} {str(result['outcome']):<14}"
            f" units={result.get('units')} edges={result.get('edges')}"
            f" peak_rss_mb={result.get('rss')} ms={result.get('duration_ms')}"
            + (f" finding={result.get('finding')}" if result.get("finding") else "")
            + (f" report={result.get('report')}" if result.get("report") else "")
        )
    return 0 if all(result["outcome"] == "passed" for result in results) else 1


def run_artifact_command(args: argparse.Namespace) -> int:
    input_path = Path(args.input).expanduser().resolve()
    if not input_path.is_file():
        raise ValueError(f"fuzz input does not exist: {input_path}")
    arguments = [args.command, str(input_path)]
    if args.command == "minimize":
        output_path = Path(args.output).expanduser().resolve()
        if output_path.exists():
            raise ValueError(f"refusing to overwrite {output_path}")
        output_path.parent.mkdir(parents=True, exist_ok=True)
        arguments.append(str(output_path))
    status = build_target(args.target, args)
    if status != 0:
        return status
    command = [str(binary_path(args.target)), *arguments]
    print(f"+ {shlex.join(command)}", flush=True)
    cwd = WORK_ROOT / "runs" / args.target
    cwd.mkdir(parents=True, exist_ok=True)
    return subprocess.run(command, cwd=cwd, check=False).returncode


def list_targets(_args: argparse.Namespace) -> int:
    for name in TARGET_ORDER:
        config = TARGETS[name]
        try:
            source = display(config.source())
        except ValueError as problem:
            source = f"missing ({problem})"
        print(f"{name}\n  source: {source}\n  seeds: {display(config.seeds)}\n"
              f"  dictionary: {display(config.dictionary)}\n"
              f"  max input: {config.max_input_size} bytes, timeout: {config.timeout} s\n"
              f"  contract: {config.contract}")
    return 0


# ------------------------------------------------------------- CLI


def positive_int(value: str) -> int:
    try:
        number = int(value)
    except ValueError as problem:
        raise argparse.ArgumentTypeError("must be an integer") from problem
    if number <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return number


def add_build_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--roc", default=resolve_command(os.environ.get("ROC", "roc")),
                        help="Roc compiler (default: $ROC or roc)")
    parser.add_argument("--no-build", action="store_true",
                        help="reuse the binary already under .roc-font-tmp/fuzz/bin")
    parser.add_argument("--source", action="store_true",
                        help="compile package/ sources instead of the served bundle (quick local iteration)")


def add_run_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("targets", nargs="*", metavar="TARGET", help=f"{', '.join(TARGET_ORDER)}, or all")
    parser.add_argument("--max-input-size", type=positive_int, help="override the target's input bound")
    parser.add_argument("--timeout", type=positive_int, help="override the per-input timeout (seconds)")
    parser.add_argument("--memory-limit", type=positive_int, default=2048, help="MB (default 2048)")
    add_build_options(parser)


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    smoke = sub.add_parser("smoke", help="short seeded run of every target (CI)")
    add_run_options(smoke)
    smoke.add_argument("--runs", type=positive_int, default=None,
                       help=f"inputs per target (default: the target's smoke_runs, {SMOKE_RUNS} for most)")
    smoke.add_argument("--seed", type=int, default=SMOKE_SEED, help=f"libFuzzer seed (default {SMOKE_SEED})")

    campaign = sub.add_parser("campaign", help="time-bounded run (default 600 s per target)")
    add_run_options(campaign)
    campaign.add_argument("--seconds", type=positive_int, default=600)
    campaign.add_argument("--seed", type=int, default=None)

    nightly = sub.add_parser("nightly", help="long run: 1800 s per target")
    add_run_options(nightly)
    nightly.set_defaults(seconds=1800, seed=None)

    for name in ("show", "replay"):
        operation = sub.add_parser(name, help=f"{name} one saved input")
        operation.add_argument("target", choices=TARGET_ORDER)
        operation.add_argument("input")
        add_build_options(operation)
    minimize = sub.add_parser("minimize", help="minimise one saved failure")
    minimize.add_argument("target", choices=TARGET_ORDER)
    minimize.add_argument("input")
    minimize.add_argument("output")
    add_build_options(minimize)

    sub.add_parser("list", help="list targets, their sources and contracts")
    sub.add_parser("check-pin", help="verify every target declares the pinned roc-fuzz release")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = make_parser()
    args = parser.parse_args(argv)
    try:
        if args.command in ("smoke", "campaign", "nightly", "show", "replay", "minimize"):
            command = run_mode if args.command in ("smoke", "campaign", "nightly") else run_artifact_command
            # No bundle is needed to reuse binaries already built.
            with flight.flight(args.roc, source=args.source or args.no_build) as args.dep:
                return command(args)
        if args.command == "list":
            return list_targets(args)
        if args.command == "check-pin":
            problems = check_pin()
            for problem in problems:
                print(f"error: {problem}", file=sys.stderr)
            if not problems:
                print(f"roc-fuzz pin ok: {ROC_FUZZ_URL}")
            return 1 if problems else 0
    except ValueError as problem:
        parser.error(str(problem))
    except KeyboardInterrupt:
        print("interrupted", file=sys.stderr)
        return 130
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
