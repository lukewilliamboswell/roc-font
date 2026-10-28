"""Replay every cached CFF record through the optimized served public API."""
from pathlib import Path
import argparse
import hashlib
import json
import math
import os
import struct
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import flight

def canonical(path):
    """A straight segment back to the start is implicit in Close."""
    result = []
    start = None
    for op, points in path:
        if op == "moveTo":
            start = points[0]
        if op == "closePath" and result and result[-1] == ["lineTo", [start]]:
            result.pop()
        result.append([op, points])
    return result

def narrowed(path):
    return [[op, [[struct.unpack(">f", struct.pack(">f", v))[0] for v in point]
                   for point in points]] for op, points in path]

def harfbuzz_path(path):
    # hb_draw suppresses a MoveTo/Close contour with no drawing segment.
    result = []
    for op, points in narrowed(path):
        if op == "closePath" and result and result[-1][0] == "moveTo":
            result.pop()
        else:
            result.append([op, points])
    return result

def freetype_contours(path):
    """FreeType emits seac accent before base; hb/fontTools emit base first.

    Contour order does not change the nonzero winding geometry. Retain each
    contour's orientation and all its points; only sort whole contours.
    NO_SCALE FreeType coordinates are16.16 values shifted to integer units.
    """
    contours = []
    current = []
    quantized = [[op, [[math.floor(v) for v in point] for point in points]]
                 for op, points in path]
    for op, points in canonical(quantized):
        current.append([op, points])
        if op == "closePath":
            if len(current) > 2:
                contours.append(current)
            current = []
    return sorted(contours, key=lambda contour: json.dumps(contour, separators=(",", ":")))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path)
    args = parser.parse_args()
    records = json.loads((HERE / "oracle.json").read_text())["records"]
    ft_records = json.loads((HERE / "freetype-oracle.json").read_text())["records"]
    requests = []
    for record in records:
        file = HERE / record["font"]
        assert hashlib.sha256(file.read_bytes()).hexdigest() == record["sha256"]
        axes = ",".join(f"{tag}={value}" for tag, value in record["axes"].items())
        requests.append(f"{record['id']}\t{file}\t{record['glyph']}\t{axes}\n")
    for index, record in enumerate(ft_records):
        file = HERE / record["query_font"]
        assert hashlib.sha256(file.read_bytes()).hexdigest() == record["query_sha256"]
        requests.append(f"cff-ft-{index}\t{file}\t{record['glyph']}\t\n")
    roc = os.environ.get("ROC", "roc")
    work = ROOT / ".roc-font-tmp/cff-replay"
    work.mkdir(parents=True, exist_ok=True)
    binary = args.binary or work / "query"
    if args.binary is None:
        with flight.flight(roc, work=work) as dep:
            subprocess.run([roc, "build", "--opt=speed", str(HERE / "query.roc"),
                            f"--output={binary}", *dep], cwd=ROOT, check=True)
    run = subprocess.run([str(binary)], input="".join(requests), capture_output=True,
                         text=True, timeout=180, check=True)
    lines = run.stdout.splitlines()
    assert len(lines) == len(records) + len(ft_records), (len(lines), len(records), run.stderr)
    failures = []
    for record, line in zip(records, lines):
        tag, payload = line.split("\t", 1)
        actual = json.loads(payload)
        path = canonical(actual["path"]) if actual["path"] is not None else None
        # HarfBuzz reports a zero box for an empty outline. The public
        # API intentionally distinguishes Empty from a nonempty zero box.
        draws = path is not None and any(op in ("lineTo", "curveTo", "qCurveTo") for op, _ in path)
        expected_extents = record["harfbuzz_extents"] if draws else None
        expected = record["fonttools_f32_scalar_path"]
        checks = {"id": tag == record["id"], "fontTools_f64": path == expected,
                  "harfbuzz_f32": path is not None and harfbuzz_path(path) == record["harfbuzz_path"],
                  "extents": actual["extents"] == expected_extents}
        if not all(checks.values()):
            failures.append({"id": tag, "checks": checks, "actual": actual,
                             "expected": expected, "hb": record["harfbuzz_path"],
                             "extents": expected_extents})
    ft_failures = []
    for index, (record, line) in enumerate(zip(ft_records, lines[len(records):])):
        tag, payload = line.split("\t", 1)
        actual = json.loads(payload)["path"]
        if tag != f"cff-ft-{index}" or actual is None or freetype_contours(actual) != freetype_contours(record["path"]):
            ft_failures.append({"id": tag, "name": record["name"], "actual": actual,
                                "expected": record["path"]})
    (work / "results.json").write_text(json.dumps({"exact_records": len(records),
        "exact_agree": len(records) - len(failures), "freetype_quantized_records": len(ft_records),
        "freetype_quantized_agree": len(ft_records) - len(ft_failures),
        "failures": failures + ft_failures}, separators=(",", ":")) + "\n")
    for failure in failures[:5]:
        print(json.dumps(failure), file=sys.stderr)
    print(f"CFF paths/extents: {len(records) - len(failures)}/{len(records)} exact cached records")
    for failure in ft_failures[:5]:
        print(json.dumps(failure), file=sys.stderr)
    print(f"FreeType calculator/random: {len(ft_records) - len(ft_failures)}/{len(ft_records)} quantized path records")
    return bool(failures or ft_failures)

if __name__ == "__main__":
    raise SystemExit(main())
