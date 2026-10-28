Run `ROC=/path/to/roc /path/to/oracle/python bench/aat-position/bench.py --label after`. Consumers compile sequentially against the served bundle in a source-sentinel mirror. Native timing excludes font preparation and planning; both engines shape the same Latin LTR text and their full glyph/cluster/position checksums must agree. Each row records five samples with 128 iterations. HarfBuzz 14.6.0 runs in a native C loop, without per-call Python overhead.

The preserved initial implementation revealed one full glyph-list copy per state action when updating unsafe-break flags through a record spread. Destructuring the run before consuming its items removes those copies. `before.json` and `after.json` record matched optimized native measurements and immutable bundle identities.

| Path | Text sizes (scalars) | Allocation calls before | Allocation calls after | Final Roc / HB ratios |
| --- | --- | --- | --- | --- |
| Pair kerning | 16 / 128 / 512 | 17 / 16 / 16 | 17 / 16 / 16 |see raw rows |
| Stateful kerning | 16 / 128 / 512 | 26 / 81 / 273 | 18 / 17 / 17 | 5.39 / 2.87 / 2.53 |
| Coordinate attachments | 16 / 128 / 512 | 28 / 83 / 275 | 20 / 19 / 19 | 5.34 / 2.94 / 2.56 |

Every row has zero leaked allocations. The narrow fuzz target enforces constant allocation calls for pair queries with unrelated table size and state/attachment queries with increasing text size. Reading is tested separately at 8/64/256 encoded pair records and glyphs. Elapsed-time evidence compares same-run ratios to the reference; large state/attachment cases improve materially after removing the copy.

roc-fuzz 0.4.3 exposes allocation calls and live allocation count, but not requested bytes or peak live bytes. Those fields are explicitly null, not estimated. Fuzz peak RSS is separate evidence. These results cover the measured fonts and sizes; they are not a claim of HarfBuzz-equivalent speed or a broad shaping allocation-baseline update.
