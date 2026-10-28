"""Interleave initial/current/HB native outline queries to reduce run-order bias."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--work", type=Path, default=ROOT / ".roc-font-tmp/cff-bench")
parser.add_argument("--output", type=Path, default=HERE / "paired-timings.json")
args = parser.parse_args()
work = args.work.resolve()
rows = []
for kind, size in [(kind, size) for kind in ("lines", "blends") for size in (16, 64, 256)]:
    file = HERE / f"{kind}-{size}-cff{1 if kind == 'lines' else 2}.otf"
    samples = {label: [] for label in ("initial", "after", "harfbuzz")}
    expected = size * (size + 1) * 4000 * (4 if kind == "blends" else 1)
    for repeat in range(7):
        labels = ["initial", "after", "harfbuzz"]
        labels = labels[repeat % 3:] + labels[:repeat % 3]
        for label in labels:
            binary = work / ("harfbuzz" if label == "harfbuzz" else label + "-timing")
            started = time.perf_counter()
            done = subprocess.run([str(binary), str(file), "4000", "2"], capture_output=True, text=True, check=True)
            samples[label].append(time.perf_counter() - started)
            assert float(done.stdout) == expected, (label, file, done.stdout, expected)
    medians = {label: statistics.median(values) for label, values in samples.items()}
    row = {"kind": kind, "size": size, "medians": medians, "samples": samples,
           "after_initial_ratio": medians["after"] / medians["initial"],
           "after_harfbuzz_ratio": medians["after"] / medians["harfbuzz"],
           "font_sha256": hashlib.sha256(file.read_bytes()).hexdigest()}
    rows.append(row)
    print(row, flush=True)
args.output.write_text(json.dumps({"repeats": 7, "queries": 4000,
    "order": "rotated initial/after/HB per repetition", "harfbuzz": "14.6.0",
    "mode": "outline; CFF2explicitwght500; CFF1static", "rows": rows}, indent=2) + "\n")
