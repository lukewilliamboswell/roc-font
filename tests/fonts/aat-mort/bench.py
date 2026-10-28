"""Replay native mort measurements; use binaries built by build-consumers.py.

Timings include startup/read/preparation/stdout. The pre-feature binary ignores
mort, so its checksum differs deliberately; it is a cost baseline, not equivalent
shaping. After and HarfBuzz must agree before any ratio is recorded.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--work", type=Path, default=ROOT / ".roc-font-tmp/mort-bench")
parser.add_argument("--output", type=Path, default=HERE / "native-measurements.json")
parser.add_argument("--iterations", type=int, default=4000)
args = parser.parse_args()
work = args.work.resolve()
assert subprocess.check_output([str(work / "harfbuzz"), "--version"], text=True).strip() == "14.6.0"
rows = []
for size in (16, 64, 192):
    file = HERE / f"scaling-{size}.ttf"
    row = {"states": size, "text_bytes": size, "font_glyphs": 257,
           "font_sha256": hashlib.sha256(file.read_bytes()).hexdigest()}
    for mode in (0, 1):
        for label in ("before", "after"):
            inp = work / f"input-{size}-{mode}"
            inp.write_bytes(bytes([mode, size >> 8, size & 255]) + file.read_bytes())
            done = subprocess.run([str(work / (label + "-alloc")), "replay", str(inp)], capture_output=True, text=True)
            match = re.search(r"ALLOCATION_DIAGNOSTIC allocations=(\d+) checksum=(-?\d+)", done.stdout + done.stderr)
            assert match and done.returncode == 77, done.stdout + done.stderr
            operation = "read" if mode == 0 else "shape"
            row[f"{label}_{operation}_allocations"] = int(match[1])
            row[f"{label}_{operation}_checksum"] = int(match[2])
    # Every output field contributes: g2/g3 alternating, advance600,
    # UTF8 cluster i, and unsafe-to-break on every glyph after the first.
    expected = sum(2 + i % 2 + 600 + i + (i > 0) for i in range(size))
    baseline = sum(1 + 600 + i for i in range(size))
    samples = {label: [] for label in ("before", "after", "harfbuzz")}
    for repeat in range(5):
        labels = ["before", "after", "harfbuzz"]
        # Rotate paired runs so sustained machine load is not attributed to one binary.
        for label in labels[repeat % 3:] + labels[:repeat % 3]:
            binary = work / (label + "-timing") if label != "harfbuzz" else work / "harfbuzz"
            started = time.perf_counter()
            done = subprocess.run([str(binary), str(file), str(args.iterations), str(size)], capture_output=True, text=True)
            samples[label].append(time.perf_counter() - started)
            assert done.returncode == 0, done.stderr
            assert int(done.stdout) == args.iterations * (baseline if label == "before" else expected), (label, size, done.stdout, expected)
    assert row["after_shape_checksum"] == expected and row["before_shape_checksum"] == baseline
    for label, values in samples.items():
        row[label + "_seconds_samples"] = values
        row[label + "_seconds_median"] = statistics.median(values)
    row["after_to_hb_ratio"] = row["after_seconds_median"] / row["harfbuzz_seconds_median"]
    rows.append(row)
    print({key: value for key, value in row.items() if "samples" not in key}, flush=True)
result = {"schema": 1, "harfbuzz": "14.6.0",
          "roc": subprocess.check_output([os.environ.get("ROC", "roc"), "version"], text=True).strip(),
          "iterations": args.iterations, "repeats": 5,
          "timing_flags": ["--opt=speed"], "allocation_flags": ["--fuzz", "--opt=speed"],
          "baseline_revision": "0d9ec2e plus shared legacy-runtime contracts; before Face imports AatMort",
          "before_bundle": "8s2Bg79vpb84kLjmz2vRRRU4ZEAgEsD1r1EUFZrfXo88.tar.zst",
          "after_bundle": "FEUxig9CoQGvktAY22mRYFEMzH7a3Agf9UwNzd8afKvp.tar.zst",
          "requested_bytes": None, "peak_live_bytes": None,
          "limits": "roc-fuzz0.4.3 exposes allocation calls only. Timings include startup, read, plan and stdout; repeated queries amortize them. Baseline ignores mort and is not equivalent work. No general shaping-performance claim.",
          "binaries": {name: hashlib.sha256((work / name).read_bytes()).hexdigest()
                       for name in ("before-timing", "after-timing", "before-alloc", "after-alloc", "harfbuzz")},
          "rows": rows}
args.output.write_text(json.dumps(result, indent=2) + "\n")
