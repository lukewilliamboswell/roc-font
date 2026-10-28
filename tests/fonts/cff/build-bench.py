"""Build matched optimized CFF callers through served source-sentinel bundles.

--before-root names an untouched39b66c3 checkout; --initial-root names the
functional pre-optimization checkout. Neither checkout is modified. Compile
the pinned HB14.6 library first, then run bench.py on the resulting binaries.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import flight

parser = argparse.ArgumentParser()
parser.add_argument("--before-root", type=Path)
parser.add_argument("--initial-root", type=Path)
parser.add_argument("--work", type=Path, default=ROOT / ".roc-font-tmp/cff-bench")
parser.add_argument("--hb-source", type=Path, default=Path("/private/tmp/harfbuzz-14.6.0/src"))
parser.add_argument("--hb-build", type=Path, default=Path("/private/tmp/roc-font-hb14-bench/src"))
args = parser.parse_args()
roc = os.environ.get("ROC", "roc")
work = args.work.resolve()
work.mkdir(parents=True, exist_ok=True)
for label, checkout in [("before", args.before_root), ("initial", args.initial_root), ("after", ROOT)]:
    if checkout is None:
        continue
    directory = work / (label + "-bundle")
    directory.mkdir(exist_ok=True)
    subprocess.run([roc, "bundle", "package/main.roc", "--output-dir", str(directory)], cwd=checkout, check=True)
    bundles = list(directory.glob("*.tar.zst"))
    assert len(bundles) == 1, bundles
    with flight.flight(roc, bundle=bundles[0], work=work / (label + "-flight")) as dep:
        mirror = flight.make_mirror(work / (label + "-mirror"))
        for source, flags, suffix in [("bench.roc", ["--opt=speed"], "timing"),
                                      ("alloc.roc", ["--fuzz", "--opt=speed"], "alloc")]:
            subprocess.run([roc, "build", *flags, "tests/fonts/cff/" + source,
                            f"--output={work / (label + '-' + suffix)}", *dep], cwd=mirror, check=True)
subprocess.run(["cc", "-O2", str(HERE / "bench.c"), "-I" + str(args.hb_source),
                "-I" + str(args.hb_build), "-L" + str(args.hb_build), "-lharfbuzz",
                "-Wl,-rpath," + str(args.hb_build), "-o", str(work / "harfbuzz")], check=True)
assert subprocess.check_output([str(work / "harfbuzz"), "--version"], text=True).strip() == "14.6.0"
