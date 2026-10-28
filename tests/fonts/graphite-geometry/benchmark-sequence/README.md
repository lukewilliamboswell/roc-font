Original UPL sequence-membership scaling control. Every `ab` pair forms a
separate attachment tree. The FIX target declares sequence class 1; its
ignored child declares class 0, so no sequence region matches. The control
measures collection of unrelated roots without changing the geometry being
solved. A full subbox on unused glyph 0 makes preload modes agree.

Before changing collection, the optimized Bph package (root 6653e4a plus
reader 52b7e78) passes every ordered full-output HB14.6/Graphite2 checksum at
4, 8 and 16 copies. `before.json` records 108/201/385 allocation calls, zero
leaks, and median Roc/HB time ratios 6.20/9.71/14.15. Requested bytes and peak
live bytes are unavailable from this counter and explicitly null. This is
before evidence; no after speedup or completed real-font budget claim is made.

`generate.py --check` reproduces the font and cases. `records.json` caches
raw public Graphite2 C API facts; `public-records.json` and
`public-oracle.json` cache the default HB14.6 Graphite adapter output. These
are independent expected results, not values captured from Roc.

`after-index.json` compares optimized snapshot 3086b73 (the retained f53b287
package plus d6b2d4c) against the same Bph before executables. Every sample
matches the ordered independent checksum and has zero leaks. The index adds
two flat pools: calls become 110/203/387, versus 108/201/385. Paired median
Roc/HB ratios are 6.08→6.24, 9.72→10.19 and 14.06→14.74. This full-snapshot comparison shows
about a 3–5% CPU regression; intervening pruning changes mean it cannot
attribute that difference to the index. The intended
benefit is reducing repeated sequence-search work on long attachment runs,
which requires a separate completed-work measurement. The existing nine
attachment/kerning/shifting allocation ratchets remain unchanged and pass.

`work-profile-before.json` preserves a separate explicit-dev diagnostic on
258-scalar Awami, after shaping produced 387 active glyphs. The query performs
two deterministic executions; each exhausts the remaining 966,433 SHIFT work
units, including 214,398 in sequence collection, 205,436 positioning, 362,026
ink collection and 178,007 solving. The remaining 6,566 units cover preparation
and traversal. The instrumented process exits 1 and is not a conformance pass
or timing measurement. `work-profile-diagnostic.json` preserves the hashed original patch as escaped text; it contains only original
logging additions to snapshot 526a7cc, not production changes.

`after-index-matched.json` uses the exact immediate pre-index executables
(snapshot e3edf5c, f53b287 collision code) rather than the older Bph snapshot.
This comparison isolates d6b2d4c on the same package source and extends the
sizes to 16/64/256 copies (32/128/512 scalars). All ordered outputs match HB;
allocation calls are 385→387, 1491→1493 and 5911→5913, with zero leaks.
Paired median Roc/HB ratios are 14.47→14.27, 22.29→22.14 and 25.05→24.76.
Those small timing changes do not establish a material CPU improvement.
The separate compatible native work-factor diagnostic observes long Awami
completion at factor 6267 versus 6521 before indexing, about 3.9% less work;
the default factor 4096 still exhausts. Every completed output hash is
unchanged. Neither result establishes full real-font agreement.
