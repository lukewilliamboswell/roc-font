"""Build source-sentinel public mort consumers against served bundles."""
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
parser.add_argument("--before-bundle", type=Path)
parser.add_argument("--only-fuzz", action="store_true")
parser.add_argument("--work", type=Path, default=ROOT / ".roc-font-tmp/mort-bench")
args = parser.parse_args()
roc = os.environ.get("ROC", "roc")
work = args.work.resolve()
work.mkdir(parents=True, exist_ok=True)
for label, bundle in ([("after", None)] if args.only_fuzz else [("before", args.before_bundle), ("after", None)]):
    if label == "before" and bundle is None:
        continue
    with flight.flight(roc, bundle=bundle, work=work / (label + "-flight")) as dep:
        mirror = flight.make_mirror(work / (label + "-mirror"))
        if not args.only_fuzz:
            for source, name, flags in [
                ("bench.roc", label + "-timing", []),
                ("alloc.roc", label + "-alloc", ["--fuzz"]),
            ]:
                subprocess.run([roc, "build", *flags, "--opt=speed", str(mirror / "tests/fonts/aat-mort" / source),
                                "--output=" + str(work / name), *dep], cwd=mirror, check=True)
        if label == "after":
            subprocess.run([roc, "test", str(mirror / "tests/api/MortMain.roc"), *dep], cwd=mirror, check=True)
            subprocess.run([roc, "build", "--fuzz", "--opt=speed", str(mirror / "fuzz/font-mort.roc"),
                            "--output=" + str(work / "font-mort"), *dep], cwd=mirror, check=True)
