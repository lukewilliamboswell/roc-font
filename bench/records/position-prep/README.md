# Positioning preparation allocation correction

`bench/position-prep.py` generates original fonts with 8, 64 and 256
format-3 mark anchors. Native optimized Roc programs import the served
bundle and use the standard read benchmark protocol; the native HarfBuzz
comparator (system HarfBuzz13.2.1) receives identical bytes. Accuracy
oracles independently use pinned HarfBuzz14.6.0. Both JSON records pin the fonts and
bundle and retain all timing samples and their spread.

| Marks | Before allocations | After allocations | Leaks | Before Roc/HarfBuzz time | After Roc/HarfBuzz time |
| --- | ---: | ---: | ---: | ---: | ---: |
| 8 | 48 | 32 | 0 | 8.12 | 7.05 |
| 64 | 104 | 32 | 0 | 9.07 | 7.53 |
| 256 | 296 | 32 | 0 | 19.62 | 22.32 |

The correction removes a temporary list per format-3 anchor and uses
numeric tags when looking for optional tables. Allocation growth from
these temporary lists disappears. Timing samples were noisy during other
compiler activity (some spreads exceed 50%); they support no precise
speed claim. The largest relative timing ratio worsened by about 14%,
within the repository's 25% tolerance. Reading eagerly validates the font;
HarfBuzz prepares lazily, so their reading workloads differ.

`read-allocations.json` records the broader read allocation checks before
and after this correction, alongside counts from unchanged main measured
with the same nightly. Ordinary shaping, kerning and query allocation
counts are unchanged. Remaining reading increases buy the additional
positioning validation/indexes and font facts; they are not hidden by this
measurement. A subsequent change avoids a precise MATH scalar pool in
fonts without MATH; final ratchet records must use the final implementation.

Requested bytes and peak live bytes cannot be measured by the pinned
roc-fuzz 0.4.3 interface. Leak counts and allocation calls are available.
The benchmark now records binary hashes for future runs; the initial
archived runs recorded bundle/font hashes, compiler and build commands.
