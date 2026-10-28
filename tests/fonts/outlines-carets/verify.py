"""Replay every cached outline/caret record using an optimized bundle consumer."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import flight
from _common import load_jsonc


def canonical_path(path):
    """A closing segment to the contour start is implicit in Close."""
    if path is None:
        return None
    result = []
    start = None
    for op, points in path:
        if op == "moveTo":
            start = points[0]
        if op == "closePath" and result and result[-1] == ["lineTo", [start]]:
            result.pop()
        result.append([op, points])
    return result


def main():
    cases = load_jsonc(HERE / "cases.jsonc")["cases"]
    records = json.loads((HERE / "oracle.json").read_text())["records"]
    if len(cases) != len(records):
        raise SystemExit("outline case and oracle counts differ")
    requests = []
    for case, record in zip(cases, records):
        if any(case[key] != record[key] for key in ("font", "glyph", "axes")):
            raise SystemExit(f"outline case changed: {case['id']}")
        file = HERE / case["font"]
        if hashlib.sha256(file.read_bytes()).hexdigest() != case["font_sha256"]:
            raise SystemExit(f"outline font changed: {file}")
        axes = ",".join(f"{tag}={value}" for tag, value in case["axes"].items())
        requests.append(f"{case['id']}\t{file}\t{case['glyph']}\t{axes}\n")
    roc = os.environ.get("ROC", "roc")
    temp = ROOT / ".roc-font-tmp"
    temp.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="outlines-", dir=temp) as directory:
        work = Path(directory)
        binary = work / "queries"
        with flight.flight(roc, work=work) as dep:
            subprocess.run([roc, "build", "--opt=speed", str(HERE / "query.roc"),
                            f"--output={binary}", *dep], cwd=ROOT, check=True)
        run = subprocess.run([str(binary)], input="".join(requests), capture_output=True,
                             text=True, timeout=120, check=True)
        lines = run.stdout.splitlines()
        if len(lines) != len(cases):
            raise SystemExit(f"expected {len(cases)} answers; got {len(lines)}")
        failures = []
        for case, record, line in zip(cases, records, lines):
            tag, payload = line.split("\t", 1)
            actual = json.loads(payload)
            expected_carets = list(record["carets"])
            if case["font"] == "outlines-carets.ttf" and case["glyph"] == 1:
                # This fixture's format-2 caret names explicit contour point 1,
                # the endpoint of the first straight segment. hb-ot lacks a
                # contour callback, but hb_draw supplies its unrounded position.
                # fontTools independently verifies default/endpoint geometry;
                # instancing rounds fractional intermediate coordinates.
                expected_carets[1] = record["path"][1][1][0][0]
            expected = {"path": canonical_path(record["path"]), "carets": expected_carets}
            actual["path"] = canonical_path(actual["path"])
            if tag != case["id"] or actual != expected:
                failures.append((case["id"], expected, actual))
        for tag, expected, actual in failures[:8]:
            print(f"{tag}:\nexpected {expected}\nactual   {actual}", file=sys.stderr)
        if failures:
            return 1
        print(f"Outlines/carets: {len(cases)} cached native records agree (paths, variation locations and point carets).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
