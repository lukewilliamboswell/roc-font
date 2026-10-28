The three original, licensed fixtures share one Sill setting array across 64,
256 and 1,024 language records. Graphite2 1.3.14 accepts them; OTS9.3 retains
their Graphite tables. The previous reader copied every logical reference,
including 1,048,576 setting records from a 17,580-byte font. The revised reader
stores each source position once and records scalar spans into that pool.
Partly overlapping Feat and Sill arrays use the same bounded preparation.

`shared-spans.json` records five interleaved optimized native samples, immutable
before/after bundles and binary hashes, compiler/library hashes and source hashes.
Input I/O is excluded in both engines. Ratios compare whole strict font reading
against Graphite2 face preparation, so their validation work differs. The median
Roc/Graphite2 ratios changed from 4.10/5.01/5.52 to 0.81/0.117/0.0187. Both
implementations still used 61 allocation calls at all three sizes, with no leaks.
The pinned fuzz platform does not expose requested bytes or peak live bytes;
those fields are explicitly null. Seven public reader expects passed through
the final served bundle in a mirror whose source entry cannot compile.

Reproduce with the latest Roc in `ROC`, using the pinned Python environment:

```
python tests/fonts/graphite/bench_read.py --output /tmp/graphite-read.json
```

Use `--bundle ARCHIVE` to prepare consumers from an immutable artifact and
`--compare WORK` to interleave an existing `WORK/read_bench` before binary.
Use `--reuse --work WORK` to retain already compiled binaries. The allocation
consumer deliberately exits77 after emitting its measured diagnostic.
