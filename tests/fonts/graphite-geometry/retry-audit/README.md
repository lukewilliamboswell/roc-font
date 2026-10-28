# Original Graphite collision retry witnesses

These 66 UPL font programs isolate retry scheduling, threshold decisions,
internal flag persistence and pass-local floating arithmetic. Observations come
from Graphite2 1.3.14's public C ABI and public `gr_start_logging` JSON. No engine
implementation source was opened or used. The generator reuses original fixture
builders and patches documented font tables with fontTools 4.61.1.

Run `python generate.py --check` to reproduce font bytes and case JSONC.
`python check.py` verifies cached keys and hashes with the standard library alone.
The parent geometry directory's extractors support recording and `--check`:

```
python record.py --cases retry-audit/cases.jsonc --output retry-audit/records.json
python record_traces.py --cases retry-audit/cases.jsonc --output retry-audit/traces.json
```

All 66 reference faces/segments are accepted without an abort. Release and
tracing-build public results are bit-identical; `oracle-proof.json` records the
library and original generator hashes. This is reference evidence. Native Roc
agreement remains a separate gate.

## Measured schedule

For an active group, phase 1 visits shifting targets in pass traversal order.
Phase 2a visits currently bad targets in the opposite order. Phase 2b visits good
targets in forward order, subject to the lock and movement rules below. Every
iteration for an earlier group finishes before phase 1 starts the next group.
The ungrouped control visits all four targets before reversing all four.
A reversed second pass retains the established font/text facts while reversing
the traversal.

The low three pass bits bound total rounds, including the first forward sweep.
A retry runs when bad targets remain or the previous forward sweep made a large
enough move. The following distinction is observable:

* Both bad targets with limits ±100 remain bad and run all requested reverse
  sweeps, even when positions never change and threshold is 255.
* A good forward sweep can be repeated to refine costs even when no target is
  currently bad. Once it makes no eligible movement, a good group stops.
* A final reverse sweep can clear stale bad flags, then leave phase 2b empty
  because the previous forward sweep made no eligible movement.

`relay-rounds-*` retains these transitions rather than just final glyph positions.

## Flags and temporary locks

The public slot flags retain the authored bits and acquire these observed bits:
32 marks a failed solve; 64 marks a target processed by shifting. A successful
or missed solve clears 32. Phase 2a sets 256 on every target it handles, including
one that succeeds or logs `missed`.

When phase 2b runs, a still-bad target is skipped and keeps its 256 bit. A good
locked target has 256 cleared and is skipped for that forward visit. Other good
targets are solved. A failed forward retry becomes bad without acquiring 256
until a later reverse visit. If phase 2b is globally skipped, a recovered target
can retain 256: wide threshold 255 ends with flags 321, whereas threshold 0 ends
with 65 at the same position. Authored 256 is preserved through phase 1 and also
suppresses/clears at an eligible good forward visit. It does not prevent a later
reverse retry. Pass 0 preserves authored flags unchanged.

## Threshold metric

The forward decision uses the maximum **single-target Euclidean displacement**
from the preceding forward sweep, measured as a change between successive
pass-local deltas. It is not the total accumulated offset, a maximum component,
or movement from phase 2a. Encoded threshold 0 has the observed default behavior
of 10, rather than permitting every tiny move. The ordinary equality boundary
is inclusive:

* A 200-unit move triggers at threshold 200, but not 201.
* Encoded 0 and explicit 10 both trigger for a 10-unit move and skip a 9-unit
  move. A 1-unit move triggers for explicit 1 but is skipped by encoded 0.
* A scaled relay's largest forward move is 175; a reverse move of 100 does not
  make it trigger at threshold 176. Threshold 175 does trigger.
* A diagonal move `(49.80392074584961,49.80392074584961)` triggers at 70, but not
  71. Its maximum component and L1 length would give different answers.

The fractional threshold cases distinguish delta changes from the total offset:
threshold 20 stops after one forward refinement, even though the resulting total
offset exceeds 200. Threshold 1 continues for six refinements; encoded 0 and
explicit 10 stop after two.

These witnesses do not distinguish comparison of squared norms from an F32 square
root rounded near an exact threshold. That last arithmetic association remains
unproved; the ordinary boundary and Euclidean metric are established.

## Neighbor filtering and `missed`

KERN-marked glyphs are excluded as shifting obstacles, even with FIX set.
During phase 2a, movable FIX neighbors that are currently good are additionally
ignored. Frozen obstacles remain relevant; other bad movable neighbors remain
relevant even if they acquired 256 earlier in the same reverse sweep. Ordinary
forward refinement again sees bad movable obstacles.

The false-good neighbor control distinguishes this from an all-neighbor physical
ink test. A fails; B's collapsed diagonal slice reports success at `(201,101)`.
B still overlaps A's 300×600 ink, but A's reverse retry logs `missed` and clears
32 because good movable B is ignored. A frozen neighbor instead keeps A bad.
The far-frozen case keeps an eligible frozen obstacle after filtering, yet still
logs `missed`, so merely having an eligible neighbor is not sufficient either.

Search-window cases retain another important limit: A's current X is 0, its
movement X bounds are `[101,201]`, and frozen B is at 400. The reference builds
constraints, finds X and diagonal slices infeasible, then selects unconstrained
Y=0 and reports success while retaining X=0 outside those positive bounds. It
is a full solve, not `missed`. At distance 700 this control also solves; at 2000
it logs `missed`. These cases constrain the optimization guard without asserting
an unproved complete broad-phase formula. Do not replace it with either a current
ink test or a test that only asks whether final axis intervals remain nonempty.

A `missed` result preserves previously computed offsets. The prior-far-frozen
case first establishes B's offset 200, then moves frozen A to −2000; B logs
`missed` and remains physically at 300, rather than returning to nominal 100.

## Separate pass-start offset and current delta

The two-pass fractional cases keep a nonzero base offset and several native
refinements. First pass 1 establishes B's offset near 227.27272. A second pass
starts with that offset and computes a delta near −12.203865, followed by more
fractional forward steps. The cached final C-API values distinguish rounding:

| Case | Final B origin |
| --- | --- |
| One pass, 3 rounds | `(313.03485107421875,-10.169891357421875)` |
| Prior pass 1, then repeated pass 7 | `(313.0348815917969,-10.169883728027344)` |
| Prior pass, then obstacle shift 100 | `(407.5955810546875,29.998016357421875)` |

The public trace distinguishes `currOffset` from `currShift`; reconstructing a
pass delta from a rounded combined total can lose observable bits. Keep the
pass-start point and current delta separately until committing the pass result.
Rounded logging decimals are explanatory evidence; cached position/advance bits
are the exact oracle.
