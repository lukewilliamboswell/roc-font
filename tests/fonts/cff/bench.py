"""Native CFF3-size measurements; binaries must be built through flight.

Both Roc and HB elapsed times include process startup, file reading, preparation
and stdout.4000queries amortize that overhead; ratios describe this workload,
not general shaping speed. The untouched baseline returns Unknown, so its zero
query checksum is not a semantic-equivalence performance comparison.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--work", type=Path, default=ROOT / ".roc-font-tmp/cff-bench")
parser.add_argument("--labels", nargs="+", default=["before", "initial", "after"])
parser.add_argument("--output", type=Path, default=HERE / "native-measurements.json")
args = parser.parse_args()
work = args.work.resolve()
count = 4000
repeats = 5
version = subprocess.check_output([str(work / "harfbuzz"), "--version"], text=True).strip()
assert version == "14.6.0", version
rows = []
for kind, size in [(kind, size) for kind in ("lines", "blends") for size in (16, 64, 256)]:
    file = HERE / f"{kind}-{size}-cff{1 if kind == 'lines' else 2}.otf"
    for mode in [0, 1, 2]:
        row = {"program_kind": kind, "line_operators": size, "operation": ["read", "extents", "outline"][mode],
               "allocation_location": {"wght":400} if kind == "blends" else "static", "timing_location": {"wght":500 if mode == 2 else 400} if kind == "blends" else "static",
               "font_sha256": hashlib.sha256(file.read_bytes()).hexdigest()}
        for label in args.labels:
            inp = work / f"input-{size}-{mode}"
            inp.write_bytes(bytes([mode]) + file.read_bytes())
            done = subprocess.run([str(work / (label + "-alloc")), "replay", str(inp)], capture_output=True, text=True)
            match = re.search(r"ALLOCATION_DIAGNOSTIC allocations=(\d+) checksum=([^\s]+)", done.stdout + done.stderr)
            assert match and done.returncode == 77, done.stdout + done.stderr
            row[label + "_allocations"] = int(match[1])
            row[label + "_checksum"] = float(match[2])
        if mode:
            if kind == "blends":
                # Regular400 normalizes to6554/16384. Half-up bounds
                # are calculated independently before timing/replay.
                per_query = size + math.floor(size * (5 + 4 * (6554 / 16384)) + .5) if mode == 1 else 4 * size * (size + 1)
            else:
                per_query = 2 * size if mode == 1 else size * (size + 1)
            expected = per_query * count
            for label in [*args.labels, "harfbuzz"]:
                times = []
                for _ in range(repeats):
                    binary = work / (label + "-timing") if label != "harfbuzz" else work / "harfbuzz"
                    started = time.perf_counter()
                    done = subprocess.run([str(binary), str(file), str(count), str(mode)], capture_output=True, text=True)
                    times.append(time.perf_counter() - started)
                    assert done.returncode == 0, done.stderr
                    checksum = float(done.stdout)
                    assert checksum == (0 if label == "before" else expected), (label, checksum, expected)
                row[label + "_seconds_samples"] = times
                row[label + "_seconds_median"] = statistics.median(times)
            for label in args.labels:
                row[label + "_to_hb_ratio"] = row[label + "_seconds_median"] / row["harfbuzz_seconds_median"]
        rows.append(row)
        print({key: value for key, value in row.items() if "samples" not in key}, flush=True)
result = {"schema": 1, "harfbuzz": version,
          "roc": subprocess.check_output([os.environ.get("ROC", "roc"), "version"], text=True).strip(),
          "timing_flags": ["--opt=speed"], "allocation_flags": ["--fuzz", "--opt=speed"],
          "iterations": count, "repeats": repeats, "baseline_revision": "39b66c3",
          "requested_bytes": None, "peak_live_bytes": None,
          "measurement_limits": "roc-fuzz0.4.3 exposes allocation calls, not requested/peak live bytes. Both timing binaries include startup/read/preparation/stdout. The pre-feature baseline has noCFFpaths: Unknown and checksum0 are expected, not equivalentwork. initial is first functionalCFF implementation; after can measure a focusedoptimization.",
          "binaries": {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in work.iterdir()
                       if path.name in ["harfbuzz", *[label + suffix for label in args.labels for suffix in ("-timing", "-alloc")]]},
          "rows": rows}
args.output.write_text(json.dumps(result, indent=2) + "\n")
