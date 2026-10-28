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

The first native gate passed 2348/2348 exact path/extents records and 160/160
quantized FreeType records. CffMain passed 18 expects (11 CFF plus 7 support) in a
source-sentinel mirror with explicit served dependency replacement. An earlier
raw CLI invocation accidentally compiled the source closure; its 539 count is
not public-bundle evidence and is not retained as such.

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
not a substitute. Dedicated timing/allocation evidence is added separately.

Primary format/reference sources:

* [Adobe CFF specification 5176](https://adobe-type-tools.github.io/font-tech-notes/pdfs/5176.CFF.pdf)
* [Adobe Type2 specification 5177](https://adobe-type-tools.github.io/font-tech-notes/pdfs/5177.Type2.pdf)
* [OpenType CFF2](https://learn.microsoft.com/en-us/typography/opentype/spec/cff2)
* [HarfBuzz 14.6 CFF interpreter](https://github.com/harfbuzz/harfbuzz/tree/14.6.0/src)
* [FreeType random-seed property](https://freetype.org/freetype2/docs/reference/ft2-properties.html#random-seed)
* [FreeType 2.13.2 private-seed initialization](https://github.com/freetype/freetype/blob/VER-2-13-2/src/cff/cffload.c)
* [FreeType 2.13.2 Type2 random operator](https://github.com/freetype/freetype/blob/VER-2-13-2/src/psaux/psintrp.c)
