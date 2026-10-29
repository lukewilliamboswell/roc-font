# MATH font fixtures and query conformance

`NotoSansMath-Regular.ttf` is the unmodified unhinted TrueType build from
notofonts/math `gh-pages`, commit `53eb8eb200ed8fc73fa13d97d26a2c9c56428c17`:

https://raw.githubusercontent.com/notofonts/math/53eb8eb200ed8fc73fa13d97d26a2c9c56428c17/fonts/NotoSansMath/unhinted/ttf/NotoSansMath-Regular.ttf

SHA-256: `1e351fb3ed563f4495eea3ce69c4698a3ae0b5b8800568006b9817383013087e`.
Its copyright and SIL Open Font License 1.1 are in `OFL.txt`.
It has TrueType outlines, 5,015 glyphs, and a MATH 1.0 table. The table
contains 215 vertical constructions (1,149 variants, 57 assemblies) and
29 horizontal constructions (132 variants, 22 assemblies).

All seven fonts pass the pinned OTS 9.3.0 sanitizer.

The six `math*.ttf` fixtures are original generated test data, under this
repository's Universal Permissive License (`SYNTHETIC-LICENSE.txt`). Run
`generate.py` with fontTools 4.61.1 to reproduce them. They cover all four
corner kern tables, duplicate heights and exact threshold equality, signed corrections, all three
pixel device formats, zero-part assemblies, missing data and GDEF variation
devices. The latter change constants, corrections, accent attachments,
kern thresholds, kern values and assembly corrections.

`cases.jsonc` retains ten distinct numerical/location cases and 445 compact
font-fact checkpoints. Each case records explicit glyph ids. Noto uses 13:

| Glyph ids | Purpose |
| --- | --- |
| 0 | absent italic/accent/construction data |
| 4 | A: accent attachment |
| 87, 115 | f and its script style: italic corrections |
| 1844 | fraction: extended vertical variants without an assembly |
| 1861, 1864 | bar and left parenthesis: vertical assemblies |
| 2847, 2875, 3195 | integral, summation and radical constructions |
| 4374, 4376 | left/right arrows: horizontal assemblies |
| 4788 | combining circumflex: horizontal variants |

Synthetic cases query meaningful glyphs 1/3 and absent glyph 2; the empty case
queries only glyph 2. Every case retains all 56 constants and connector overlap.
For selected glyphs, queries retain every corner kern threshold and its exact
neighbours, both construction directions and complete assembly recipes. The
property fuzz target and public API tests cover broader totality and malformed
input contracts; the committed oracle is a small independent checkpoint.

`oracle.py` records with pinned uharfbuzz 0.56.3 (HarfBuzz 14.6.0) and independently
checks fontTools 4.61.1. `verify.py` builds the optimized native `query.roc` against
`scripts/flight.py`'s served bundle and compares every retained fact. Ordinary
replay needs neither oracle installed. Each record pins the font hash, canonical
case hash, selection mode and glyph ids, so changed selection/location metadata
cannot silently reuse an old cache.

Exhaustive all-glyph records stay local and regenerable:

```
python tests/fonts/math/oracle.py
python tests/fonts/math/verify.py
python tests/fonts/math/oracle.py --full
python tests/fonts/math/verify.py --full
```

The first pair generates/replays the compact committed checkpoints. The second
pair generates/replays all 5,869 facts under ignored
`.roc-font-tmp/math/oracle-full.jsonl`, without changing `oracle.jsonl`. Full replay
requires that local cache to exist and still needs no oracle installation.
Neither mode generates Roc code.

## Deliberate reference divergence

HarfBuzz 14.6.0 ignores MATH VariationIndex devices: its `MathValueRecord`
implementation calls `get_x_delta(font)` / `get_y_delta(font)` without a
GDEF variation store. Current upstream supplies that store. roc-font uses
the checked GDEF store, preserving variation support instead of silently
returning static values. Accordingly, the three ordinary variable cases (including the default location)
identify their oracle as `fonttools-varstore-and-harfbuzz-materialized`:
fontTools independently evaluates variation deltas and materializes the
MATH values, and HarfBuzz then checks the resulting static queries.
The Noto, synthetic and empty cases use direct HarfBuzz queries. The four
wide-value cases use the independent binary32 variation-store oracle described
below. Each cached result records its provenance.

Pixel devices are structurally validated, but are not applied: font-unit
queries have no ppem, as with HarfBuzz at ppem zero. The public raw accent
attachment and italic-correction queries expose explicit absence, rather
than HarfBuzz's half-advance/zero synthesis. The recorder compares absence
with the fontTools coverage and validates the corresponding HarfBuzz
fallback separately.

## Wide mathematical variation values

A valid ItemVariationData row can contain enough signed32-bit deltas to
exceed I32 after summation. Delta-bearing math facts therefore use I64:
constants, corrections, attachment positions, kern heights/values and
assembly italic correction. Fixed unsigned16-bit variant and part sizes
remain I32, while percentages remain I16. No accepted value is clamped.

`math-large-variable.ttf` has32identical variation regions and positive
and negative long-word columns. At maximum weight its delta magnitude is
68,719,476,736 font units. The two large-variable cases independently use
fontTools VarStoreInstancer with binary32 rounding of these exact
identically weighted sums. They identify their oracle as
`fonttools-varstore-f32-wide`. Such results cannot be materialized into a
static MATH record, whose stored base value is signed16-bit. HarfBuzz14.6
ignores MATH variation devices, so it is deliberately not claimed as an
oracle for these wide values; its static queries still verify variant
records and determine the unchanged kern threshold selection.

An accepted row has at most65535columns, each delta fits I32 and each
region scalar lies in [0,1]. Even allowing binary32 accumulation error,
the rounded sum is below2^48 in magnitude, leaving room in I64 for the
base value without overflow or saturation. Repeated region indices do not
change that per-row count bound.

Two additional original variable fixtures cover scalar precision and the
meaning of the design default. `math-precise-variable.ttf` has three axes
whose normalized coordinates [1,1,256] produce scalar 2^-34. Thirty-two
signed-32-bit columns still add four font units, which a 2.30 shaping cache
would lose. `math-constant-variable.ttf` has peak-zero regions and contributes
even at normalized coordinates [0,0,0]. Both pass OTS9.3. Their independently
computed fontTools/binary32 facts use the wide oracle path, because pinned
HarfBuzz14.6 does not evaluate raw MATH VariationIndex devices. MATH uses
precise binary32 scalars at every location, including the design default.
