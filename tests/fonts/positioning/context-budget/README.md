# Context positioning scheduling fixtures

These 28 original TrueType fonts and their generator are UPL-licensed (see
LICENSE). Rebuild with fontTools 4.61.1 using `python generate.py`; glyph
outlines and metrics come from the repository's deterministic benchmark
builder. No third-party font was modified.

Twenty-five fonts pass OTS 9.3.0 (commit 884861e0103b41d7e9845fdaf9fd1e3c12819103):

- `many-{8,64,256,2048,8192}` calls the same SinglePos lookup in table order.
  The fonts with 256, 2048 and 8192 records reproduce the benchmark's
  original bytes exactly.
- `ignored-8192` has 8192 sequence indices of 1, past its one matched input
  but below the font glyph count. OTS permits these; shaping ignores them.
- `context-{1,2,3}` and `chain-{1,2,3}` match across ignored marks. The
  SequenceIndex selects a matched input, rather than an adjacent run position.
- `nested-order`, `attach-shift` and `shift-attach` combine nested contexts,
  mark attachment and placement. These operations do not commute: final
  mark offsets are respectively (-396,700), (-403,700) and (-410,700).
- `cycle-8192` has a self-cycle; `fanout-8192` has 8192 contexts, each
  containing 8192 SinglePos applications. Both are structurally valid.

The `saturating-advance` and `saturating-placement` fonts apply nine blocks
of 8192 positive values, then nine blocks of negative values. HarfBuzz
saturates each update to a signed 32-bit position; clamping only the final
sum produces a different result after cancellation. At 64 input glyphs,
the first two advances or placements must be -268435457 and 806354943.
The reference operation is `hb_saturate_add` in HarfBuzz 14.6
`src/OT/Layout/GPOS/ValueFormat.hh`, lines 106–154.

The `device-advance` and `device-placement` fonts separately test stored
values followed by variable corrections. At `wght=1`, a final stored
+32767 saturates before a VariationIndex delta of -32768; the result is
2147450879. Combining them before addition incorrectly treats this as -1.

`attachment-mixed-advances` uses a MultipleSubst result to attach a mark
across a second component with advances [-1,+1]. Starting at INTMAX,
ordered subtraction produces INTMAX-1; subtracting their combined zero
produces the wrong value. `float-anchor` checks binary32 anchor arithmetic:
base 1+2^24 and mark 0+2^24 both round to 2^24 before subtraction. Its final
mark x offset is -510, rather than the -509 from integer arithmetic.

`attachment-distance` tests signed 16-bit parent links: distances 32767
and 32768 attach at (-410,700); distance 32769 refuses attachment entirely
and leaves (0,0). These long cases cache only selected output indices,
while the native driver still validates alignment and every cluster.

`pair-absolute` isolates the pair-only fast path: a variable correction of
2147483520 overflows when added to the nominal advance 510, then a second
lookup subtracts 32768. Saturating the absolute advance gives 2147450879;
saturating accumulated deltas would incorrectly add another 383.

The three `wide-*` files are deliberate validator-negative fonts. Their
extension offsets reach direct record arrays beyond 65535 bytes, and their
coverage aliases initial ignored records. HarfBuzz 14.6 shapes these, but
OTS checks that the record end is at most 65535 and coverage starts after
it. The package rejects them under its existing OTS policy; they are not
examples of valid fonts in the positive replay.

`oracle.py` records 140 cases from uharfbuzz 0.56.3 / HarfBuzz 14.6.0. It
caches actual returned glyphs, positions and clusters or an explicit
MemoryError for the cyclic reference failure. Twenty-two custom-depth
cases test the package contract separately, using a literal bounded DFS
interpreter in `verify.py`. There are 134 native replay cases; six wide-font
reference runs are retained solely as validator provenance. Cycle probes
at depths 65535 and 65536 distinguish combined Depth and Operations reports
from Operations alone when the work bound wins the simultaneous check.
HarfBuzz's successful finite-fanout result is itself limited by work:
advance 66038 is the nominal 510 plus 65528 SinglePos leaves. Its 65536
nested applications also include eight contextual calls. The public checked
API additionally reports that operations stopped; HarfBuzz returns this
partial run without a resource-exhaustion diagnostic.

Run `ROC=/path/to/roc python verify.py` for optimized native artifact
replay without installed oracles. `tests/api/PositionContextTests.roc`
covers public depth bounds, valid ignored records, exact operation order,
strict and default rejection of the negative table, and empty runs. The
dedicated fuzz target measures shaping allocations at 8, 64 and 256 records
and mutates valid cyclic, fanout, ignored-record and mark fixtures. It
checks totality, determinism, index alignment, bounded output and leaks.

Scalar execution frames retain one matched-position span per active
nesting level. Prepared record lists are shared; increasing pending
fanout does not create a live list of pending calls. The independent
review checked depth-first table order, parent-frame advancement before
pushing a child, truncation of the position pool on pop, absolute run
indices (GPOS never changes run length), and skipping invalid sequence
indices before budget and depth checks. No additional core defect was found.

`bench/context-budget.py` compares the same optimized before and after
inputs at 256, 2048 and 8192 records, with calibration, discarded warmup and
five samples, against a native comparator whose version must be 14.6.0.
It records binary and font hashes, allocation calls, leak counts and peak
RSS. Requested bytes and peak live allocator bytes are unavailable from
roc-fuzz 0.4.3; RSS is a separate process measure.

Two interrupted mixed runs declare `WorkBudgetAccounting`: the 8-padding
case in each direction. The raw HarfBuzz cache is retained unchanged.
Roc counts lookup applications and script work. HarfBuzz also charges
buffer bookkeeping: two operations for the initial grapheme merge and
three for marking the attachment unsafe. The pinned internal-counter
probe and its actual trace are in `bench/context-ops.cc` and
`operations-trace.json`.

`verify.py` reads the graph facts decoded independently by fontTools and
interprets its nine inner contexts, each with 8192 leaf updates. With a
65536-operation budget, Roc executes eight inner calls and 65528 leaves;
HarfBuzz's remaining 65531 permits eight inner calls and 65523 leaves.
The verifier computes the Roc offset with sequential signed-32-bit
saturation and subtraction of [-1,+1]. It checks every other cached glyph field against
HarfBuzz and requires the public `Operations` report. No cached Roc result
or blanket allowance for interrupted runs is used. Larger completed mixed
cases still require exact HarfBuzz agreement.

The final measurements in `after-native.json` use the same nightly and
explicit speed optimization for both allocation binaries. The preserved
historical allocator was rebuilt at its exact clean commit 99a0b4f; the
older timing comparator is from 72f7eee. The report records that these
snapshots also differ in earlier manual-ZWJ support, so improvements are
not attributed solely to the pending-call representation.

| Context records | Previous allocations | Final allocations | Final / previous time | Final / HarfBuzz time |
| --- | --- | --- | --- | --- |
| 256 | 25 | 22 | 0.656 | 5.04 |
| 2048 | 25 | 22 | 0.636 | 5.17 |
| 8192 | 25 | 22 | 0.632 | 5.18 |

All measured operations leak zero allocations and ordinary benchmark
checksums agree. Mixed-sign attachment runs with 8, 64 and 256 padding
glyphs use 38, 39 and 39 allocations. Their full positions are independently
checked by the native oracle replay; the generic benchmark checksum does
not include offsets.

For the cyclic font, measured peak process RSS falls from 17.53 MiB to
3.98 MiB; finite fanout falls from 8.28 MiB to 3.95 MiB. The previous
snapshot has a 16384-operation floor, while the final snapshot has 65536,
so their adversarial timings and allocation counts do not compare equal
allowed work. The cycle reference fails; its C timing is explicitly not
a successful shape oracle. `numerical-before.json` separately preserves
actual pre-fix advance, placement, mixed-attachment and parent-distance
mismatches. `checks.json` records the final native and fuzz evidence.
