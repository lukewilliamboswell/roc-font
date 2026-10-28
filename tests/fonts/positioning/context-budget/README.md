# Context positioning scheduling fixtures

These20 original TrueType fonts and their generator are UPL-licensed (see
LICENSE). Rebuild with fontTools4.61.1 using `python generate.py`; glyph
outlines and metrics come from the repository's deterministic benchmark
builder. No third-party font was modified.

Seventeen fonts pass OTS9.3.0 (commit884861e0103b41d7e9845fdaf9fd1e3c12819103):

- `many-{8,64,256,2048,8192}` calls the same SinglePos lookup in table order.
  The256/2048/8192fonts reproduce the before-benchmark bytes exactly.
- `ignored-8192` has8192 sequence indices1, past its one matched input but
  below the font glyph count. OTS permits these; shaping ignores them.
- `context-{1,2,3}` and `chain-{1,2,3}` match across ignored marks. The
  SequenceIndex selects matched-input position, not adjacent run position.
- `nested-order`, `attach-shift` and `shift-attach` combine nested contexts,
  mark attachment and placement. The operations do not commute: final mark
  offsets are respectively(-396,700),(-403,700),(-410,700).
- `cycle-8192` has an actual self-cycle; `fanout-8192` has8192 contexts each
  containing8192 SinglePos applications. Both are structurally valid.

The three `wide-*` files are deliberate validator-negative fonts. Their
extension offsets reach direct record arrays beyond65535 bytes, and their
coverage aliases initial ignored records. HarfBuzz14.6 shapes these, but
OTS checks both record-end<=65535 and coverage after record-end. The
package rejects them under its existing OTS policy; they are not examples
of valid fonts in the positive replay.

`oracle.py` records108 cases from uharfbuzz0.56.3/HarfBuzz14.6.0. It caches
actual returned glyphs/positions/clusters or an explicit MemoryError for
the cyclic reference failure; it never invents a successful cycle result.
Twenty custom-depth cases test the package contract separately, using a
literal bounded DFS interpreter in `verify.py`.102 native cases replay;
six wide-font reference runs are retained solely as validator provenance.
HarfBuzz's successful finite-fanout result is itself work-limited: advance
66038 is510 nominal plus65528 SinglePos leaves (65536 nested applications
include eight contextual calls). The public checked API additionally
reports that operations stopped; HarfBuzz provides no such success flag.

Run `ROC=/path/to/roc python verify.py` for optimized native artifact
replay without installed oracles. `tests/api/PositionContextTests.roc`
covers public depth bounds, valid ignored records, exact noncommuting
order and strict/default rejection of the negative table. The dedicated
fuzz target measures shaping allocations at8/64/256 records and mutates
valid cyclic/fanout/ignored/mark fixtures, retaining totality,
determinism, index alignment, bounded output and leak checks.

The scalar execution frames retain one matched-position span per active
nesting level. Prepared record lists are shared; increasing pending
fanout does not create a live list of pending calls. The independent
review checked depth-first table order, parent-frame advancement before
pushing a child, truncation of the position pool on pop, absolute run
indices (GPOS never changes run length), and skipping invalid sequence
indices before budget/depth checks. No additional core defect was found.

`bench/context-budget.py` compares the same optimized before/after inputs
at256/2048/8192 records, with calibration, discarded warmup and five
samples, against a native comparator whose version must be14.6.0. It
records binary/font hashes, call counts, leak counts and peak RSS.
Requested bytes and peak live allocator bytes are explicitly unavailable
from roc-fuzz0.4.3; RSS is a separate process measure.
