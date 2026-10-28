Run `ROC=/path/to/roc /path/to/oracle/python bench/variation-complete/bench.py`. This builds two optimized native apps sequentially from a source-sentinel mirror, importing the served package bundle, then measures them beside actual HarfBuzz 14.6.0 functions in a native C loop. `--reuse` reuses those apps. `native.json` records immutable bundle identity, compiler, reference binary hash, font hashes, five-sample medians and exact checksums.

The measurements exclude font reading and startup. Metric cases query glyph 1 at weight 1 repeatedly. HarfBuzz caches those metrics; Roc evaluates the validated tuple stream on each call. Axis cases perform public `Font.at` and `Font.coordinates`, including the latter's tagged records; HarfBuzz sets the corresponding design coordinates and reads normalized coordinates. These are public-operation comparisons, not an isolated floating-point arithmetic contest.

| Work | Three increasing sizes | Allocation calls | Roc / HB ratio |
| --- | --- | --- | --- |
| Sparse phantom metrics | 4 / 64 / 512 contour points | 5 / 5 / 5 | 12.84–12.93 |
| All-point phantom tuples | 4 / 64 / 512 contour points | 4 / 4 / 4 | 11.31–15.08 |
| Axis normalization | 8 / 32 / 128 axes | 28 / 76 / 268 | 21.65–25.80 |
| avar2 cross-axis deltas | 8 / 32 / 128 active regions | 23 / 23 / 23 | 16.48–17.35 |

Every measured call has zero leaked allocations. Sparse phantom queries do not allocate or scan with unrelated contour count. All-point tuples scan encoded runs but retain only four metric values. Axis normalization allocation calls grow linearly with returned tagged axes. avar2 uses a flat region cache with a constant number of allocation calls as the region count grows. The fuzz target independently enforces those size relationships and expected coordinate/advance results on every input.

These features previously lacked correct public behavior, so no elapsed-time comparison to the old incorrect metric/avar2 result is presented. Repeated metrics are a measured caching opportunity; location changes also retain a performance gap. The figures do not imply HarfBuzz-equivalent speed. roc-fuzz 0.4.3 exposes allocation calls and live allocation count, but not requested bytes or peak live bytes: those fields are explicitly null. Fuzz RSS is reported separately in the test evidence.
