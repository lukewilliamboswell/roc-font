# CFF path evidence

The four renamed Adobe subsets are OFL fonts. `source-pins.json` records the
upstream commit, URL and SHA256 of every original and licence; `derived-pins.json`
records the resulting subsets. `prepare.py --check` reproduces their bytes with
fontTools 4.61.1. All four pass OTS 9.3 (commit884861e). Names reserved by the OFL
are replaced in the modified fonts. The matching OFL texts are included.

| File | Model actually exercised |
| --- | --- |
| sans-cff1.otf | Name-keyed CFF1; global and local subroutines |
| cid-cff1.otf | CID-keyed CFF1; 18 font dictionaries and FDSelect |
| sans-cff2.otf | Variable CFF2; weight axis, avar, blend |
| serif-cff2.otf | Variable CFF2; weight/optical-size axes, 4 font dictionaries |

The original drawings in `generate.py` and the generated operator/calculator
fonts are UPL test data; see LICENSE. `operators-cff1.otf` passes OTS 9.3 and
exercises all drawing/flex operators, hints/masks/widths, biased local/global
calls, StandardEncoding seac and empty/move-only outlines. The calculator
fixtures deliberately include legal Type2 arithmetic/transient/random operators
which OTS 9.3 and HarfBuzz 14.6 do not implement completely. Their OTS rejection
does not make them malformed Type2 programs; FreeType is their independent
geometry oracle. They are never bundled with the package.

## Cached native replay

`oracle.py` records 2348 cases with fontTools 4.61.1 and HarfBuzz 14.6.0: every glyph
in all four real subsets at default, axis endpoints/midpoints and combined
locations, plus every original operator glyph. It generates JSON, never Roc.
`verify.py` builds `query.roc` with `--opt=speed` and the explicit dependency
arguments from `flight.flight`, importing the loopback-served package bundle.
Every cached record is replayed. The verifier needs only Python's standard
library and Roc; recording oracles requires the pinned oracle environment.

Public paths retain F64 coordinates. HarfBuzz's draw ABI narrows them to F32;
the verifier compares that narrowing exactly, separately from F64 fontTools
geometry. The selected normalized F2DOT14 coordinates and independently
calculated F32 region scalar inputs are recorded. The unmodified fontTools
scalar-policy paths are retained too: its F64 support-scalar division differs
from HarfBuzz in 18 Source Sans midpoint glyphs. Supplying the same recorded
F32 scalar inputs to its unmodified charstring interpreter gives exact F64
geometry without a tolerance. Extents include cubic controls and use HarfBuzz's
half-up rounding, rather than an analytical tight cubic box.

Redundant final straight segments to a contour start are canonicalized as
Close. HarfBuzz suppresses a move-only contour; the public API and fontTools
retain MoveTo/Close, with Empty extents. These are explicit representation
policies, not numerical tolerances.

`freetype-oracle.py` records 160 controlled glyph loads from FreeType 2.13.2.
It resets `FT_Property_Set(library,"cff","random-seed",seed)` before **every**
fresh face: face creation advances the driver seed. Property 0 honors the
font's initialRandomSeed; 54321 overrides it. Matching font-seed variants permit
replay through the package without exposing rendering-library configuration.
The original, negative, zero/default and overridden seeds are all exercised.
FreeType NO_SCALE points are shifted 16.16 integers: the verifier checks this
quantized geometry and sorts whole seac contours because FreeType emits the
accent before the base. This is 160 quantized comparisons, not 160 exact F64
comparisons. The public tests separately assert exact F64 random positions.

Random uses FreeType 2.13.2's xorshift32 sequence and `(low16+1)/65536` in(0,1].
Each glyph query restarts its private seed, so query order cannot change bits.
Negative seeds use their magnitude; zero/missing seeds use 987654321, matching
FreeType's private-dictionary initialization. No hinting or rasterization is
performed by this package.

The initial native gate passed 2348/2348 exact path/extents records and 160/160
quantized FreeType records. The final expanded gate passes 2943/2943 exact
normative F64 paths/extents and 160/160 quantized FreeType records. CffMain passes
22 expects (15 CFF plus 7 support) in a
source-sentinel mirror with explicit served dependency replacement. An earlier
raw CLI invocation accidentally compiled the source closure; its 539 count is
not public-bundle evidence and is not retained as such.

The additional original fonts cover both predefined Expert charsets, custom
charset format 2, both subroutine bias thresholds 1240/33900, and CFF2 FDSelect
formats 0/3/4 with two dictionaries, nested blends and a flex1 branch that
changes with location. All of these valid fixtures pass OTS 9.3. Separate files
cover truncated INDEX data, missing subroutines, recursive subroutines/seac,
missing required CFF2 PrivateDICT, and the exact/outside coordinate envelope.
The edge and outside coordinate files both pass OTS: the outside rejection is
explicitly our numeric resource bound, not a claim of malformed font data.

Three declared HarfBuzz 14.6 default-draw differences are retained in the raw
oracle records. For the CFF2 constant-region fixture, HB draw suppresses all
blends at zero coordinates while its extents and fontTools apply the constant
region. Its source `hb-ot-cff2-table.cc:223-224` passes zero coordinate count
when `has_nonzero_coords` is false; extents uses the full coordinate vector.
The public path follows the specification and agrees with fontTools and HB
extents. The verifier checks the exact normative path and separately proves
the raw HB path equals fontTools with blending disabled. No tolerance or
unlisted exception is used.

## Hostile input and numerical limits

Reading checks INDEX offsets before allocation, DICT/cardinality/control
operands, FDSelect/charset/encoding references, every reachable charstring
execution, hint masks, and bounded seac expansion. Subroutines use an explicit
call stack. Unknown operators clear operands as the formats specify. CFF2
program selectors and offsets cannot be blended. No query repairs a reference
or clips geometry.

The proof limits are absolute operands 2^100; absolute coordinates at **all**
variation locations 2^30−1; stacks 48 (CFF1)/513 (CFF2); 10 nested subroutine calls;
200000 expanded commands; 1000000 instructions per glyph; seac depth 10 and 1024
component visits. Total preparation instructions are bounded by
`max(1000000,64*min(table_bytes,1000000))`. Exceeding a numerical/resource proof
is OverLimit, even for an otherwise legitimate program. Interval slack covers
variable accumulation and both possible flex1 branches. Static cancellation
retains its actual deterministic result.

Source Serif 4.005 contains blended PrivateDICT BlueScale values. OTS 9.3,
fontTools 4.61.1 and HarfBuzz 14.6 accept them, although the current OpenType
summary marks BlueScale nonblendable. The reader retains finite bounded
values of this ignored hint entry; program/offset controls remain static.
OpenType FontMatrix is finite-checked but does not transform the raw font-unit
paths, matching HarfBuzz. Font-unit outlines exclude hinting/pixel placement.

`font-cff.roc` measures isolated 16/64/256 line-program preparation and query
allocation scaling and leaks; it tests the exact numerical envelope edge and
explicit rejection just outside. Mutated real CFF1/CID/CFF2 and calculator
seeds exercise totality, finite output, deterministic repeated reads/queries,
variation locations and out-of-range glyphs. `fuzz-small.json` and
`fuzz-seeded.json` record 1000 optimized native inputs each, seeds 27128/27129.
Requested bytes and peak live bytes are unavailable in roc-fuzz 0.4.3; RSS is
not a substitute. `font-cff2.roc` adds an independent narrow nested-blend target
at 16/64/256 operators, including a constant default region and FDSelect 4.
Final campaigns pass 1000 inputs each, seeds 27131/27132, on the final core.

## Native performance evidence

`native-measurements.json` records untouched 39b66c3, initial functional CFF,
and optimized CFF at 16/64/256 operators for both straight-line and nested-blend
programs. The untouched implementation returns Unknown; its zero query costs
are not an equivalent-work speed comparison. The functional optimization
returns an already-sized path buffer directly when there is no seac expansion.

Plain outline allocations decline 9/11/13→2/2/2, and extents 2/2/2→1/1/1.
Nested-blend outlines decline 10/12/14→3/3/3, and extents 3/3/3→2/2/2.
Reading remains 47 allocations for plain programs and 78 for the variable fixture.
These are feature-local allocation counts, not a change to unrelated default
font workloads. Timing uses native optimized Roc and native HarfBuzz 14.6 C,
with coordinate checksums and explicit matching locations: Regular 400 for
extents and 500 for CFF2 drawing, avoiding HB's zero-coordinate draw shortcut.
Both processes include startup, reading, preparation and stdout.

Grouped timing samples were affected by run-order/system load. The additional
`paired-timings.json` rotates initial/current/HB order over 7 repetitions.
After/initial outline ratios at 16/64/256 are 0.894/0.950/0.978 for plain programs
and 0.962/0.985/1.010 for nested blends. Largest-size after/HB ratios are about
9.08 and 9.17 respectively. The deterministic allocation improvement is clear;
the elapsed-time samples do not establish a general speed improvement.

Reproduce with `build-bench.py` (served source-sentinel builds), `bench.py` and
`paired-bench.py`. Timing flags are `--opt=speed`; allocation flags are
`--fuzz --opt=speed`. The exact compiler, binary/font hashes, samples and
measurement limits are recorded. The initial functional query code predates
the direct-buffer optimization; the baseline query lacks CFF entirely.

Primary format/reference sources:

* [Adobe CFF specification 5176](https://adobe-type-tools.github.io/font-tech-notes/pdfs/5176.CFF.pdf)
* [Adobe Type2 specification 5177](https://adobe-type-tools.github.io/font-tech-notes/pdfs/5177.Type2.pdf)
* [OpenType CFF2](https://learn.microsoft.com/en-us/typography/opentype/spec/cff2)
* [HarfBuzz 14.6 CFF interpreter](https://github.com/harfbuzz/harfbuzz/tree/14.6.0/src)
* [FreeType random-seed property](https://freetype.org/freetype2/docs/reference/ft2-properties.html#random-seed)
* [FreeType 2.13.2 private-seed initialization](https://github.com/freetype/freetype/blob/VER-2-13-2/src/cff/cffload.c)
* [FreeType 2.13.2 Type2 random operator](https://github.com/freetype/freetype/blob/VER-2-13-2/src/psaux/psintrp.c)
