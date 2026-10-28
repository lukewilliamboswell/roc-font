# Modern Apple shaping measurements

The native Roc and HarfBuzz 14.6 loops shape the same text and consume all
glyph ids, UTF-8 clusters, advances and offsets in matching checksums.
Font preparation and planning are outside the timed loop. Each row uses
five samples of 128 iterations. The three sizes are 16/64/256 copies.
`bench.py` builds both consumers against an immutable served package;
`feature_allocations.py` additionally enforces source-sentinel imports.

The earlier functional snapshot is the bundle from 1747518 (`before`).
`after` includes class/applicability corrections. `optimized` removes the
temporary lists in rearrangement. It captures up to four scalar boundary
items, moves the overlapping middle in the safe direction, then writes
the boundary items and clusters in place. All 16 verbs and 63/64/65/256
glyph spans are covered by 640 independent cached native cases.

| Path | Optimized allocation calls at three sizes |
| --- | --- |
| Direct substitution | 14 / 14 / 14 |
| Contextual substitution | 14 / 14 / 14 |
| Ligature substitution | 30 / 40 / 53 |
| Insertion | 20 / 22 / 26 |
| Rearrangement | 14 / 14 / 14 (previously 46 / 142 / 526) |
| Tracking with combining marks | 15 / 15 / 15 |
| Real Noto Sans Tamil MN | 111 / 313 / 1092 |

Every row reports zero leaked allocations. Full timing ratios and source
identities are in the per-model JSON records. Timing varies with machine
load; the allocation reduction is deterministic. The initial untouched
pre-AAT package would perform different work, so it is not used as an
equivalent-output timing baseline. The recorded source-member hashes and
immutable bundle identities identify builds made during integration;
the checkout revision alone does not identify uncommitted source.

`bench/baseline.json` ratchets the narrow allocation cases. Run
`python3 scripts/feature_allocations.py --only aat-morx` to check them,
or `bench.py --check` with an explicitly preserved binary for a targeted
replay. `--update` on the central checker records a deliberate change.
roc-fuzz 0.4.3 exposes allocation calls and live-allocation counts;
requested bytes and peak live bytes are unavailable and remain null.
