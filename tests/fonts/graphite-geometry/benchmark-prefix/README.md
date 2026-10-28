Original UPL control for collision positioning when later prefixes really
change. Each `abc` attaches positive-advance child A to FIX root B, followed
by frozen wide obstacle C. A's advance is 2500; B shifts right 397 units and
its complete cluster advance grows by 397. This occurs in every repeated
cluster, so subsequent roots require new exact prefixes. Y limits are [-1,1]
to avoid the separate reference behavior of initially degenerate slices.

The reference segment advance is exactly 3580 times the copy count, versus
3183 times the copy count without collision correction. Four, eight and
sixteen copies exercise 12, 24 and 48 input glyphs. One full subbox on unused
glyph 0 neutralizes the independently measured preload allocation defect.

`records.json` contains independent raw Graphite2 C API observations;
`public-records.json` and `public-oracle.json` contain pinned HB14.6 full
public runs. Both the original 2qu consumer and the private FPqy prefix-cache
consumer match all three full public outputs. These observations establish
numerical coverage, not a performance or allocation claim. Native optimized
allocation measurements are recorded separately when they actually complete.

`generate.py --check` reproduces the original font and case data. No engine
implementation source was read or ported.
