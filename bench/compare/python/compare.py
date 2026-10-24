"""fontTools comparison program for scripts/bench.py: reading only.

Usage: python3 compare.py fonttools <iterations>, with one case file on stdin
(see bench/roc/FontBench.roc): <operation>\\n<font length>\\n<font><text>.
Only the `read` operation is supported; any other exits 3.

`read` parses the font with TTFont and decompiles every table
(ensureDecompiled), so its work includes outlines the Roc reader only scans
for extents. One JSON line is printed:
{"iterations", "elapsed_ns", "successes", "checksum"}.
"""
import io
import json
import sys
import time

from fontTools.ttLib import TTFont


def main() -> int:
    iterations = int(sys.argv[-1]) if len(sys.argv) > 1 else 1
    data = sys.stdin.buffer.read()
    op, rest = data.split(b"\n", 1)
    length, rest = rest.split(b"\n", 1)
    font = rest[: int(length)]
    if op != b"read" or sys.argv[1] != "fonttools":
        print(f"unsupported: {sys.argv[1]} {op.decode(errors='replace')}", file=sys.stderr)
        return 3
    checksum = successes = 0
    start = time.perf_counter_ns()
    for _ in range(iterations):
        try:
            tt = TTFont(io.BytesIO(font), lazy=False)
            tt.ensureDecompiled()
            checksum += tt["maxp"].numGlyphs + tt["head"].unitsPerEm
            successes += 1
        except Exception:  # a rejected font counts as a failure, like the others
            pass
    elapsed = time.perf_counter_ns() - start
    print(json.dumps({"iterations": iterations, "elapsed_ns": elapsed, "successes": successes, "checksum": checksum},
                     separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
