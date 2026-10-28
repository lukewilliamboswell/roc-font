# MATH font fixtures and query conformance

`NotoSansMath-Regular.ttf` is the unmodified unhinted TrueType build from
notofonts/math `gh-pages`, commit `53eb8eb200ed8fc73fa13d97d26a2c9c56428c17`:

https://raw.githubusercontent.com/notofonts/math/53eb8eb200ed8fc73fa13d97d26a2c9c56428c17/fonts/NotoSansMath/unhinted/ttf/NotoSansMath-Regular.ttf

SHA-256: `1e351fb3ed563f4495eea3ce69c4698a3ae0b5b8800568006b9817383013087e`.
Its copyright and SIL Open Font License 1.1 are in `OFL.txt`.
It has TrueType outlines, 5,015 glyphs, and a MATH 1.0 table. The table
contains 215 vertical constructions (1,149 variants, 57 assemblies) and
29 horizontal constructions (132 variants, 22 assemblies).

All four fonts pass the pinned OTS 9.3.0 sanitizer.

The three `math*.ttf` fixtures are original generated test data, under this
repository's Universal Permissive License (`SYNTHETIC-LICENSE.txt`). Run
`generate.py` with fontTools 4.61.1 to reproduce them. They cover all four
corner kern tables, duplicate heights and exact threshold equality, signed corrections, all three
pixel device formats, zero-part assemblies, missing data and GDEF variation
devices. The latter change constants, corrections, accent attachments,
kern thresholds, kern values and assembly corrections.

`cases.jsonc` defines six native conformance cases. `oracle.py` records
font facts using pinned uharfbuzz 0.56.3 (HarfBuzz 14.6.0) and independently
checks them against fontTools 4.61.1. `verify.py` builds `query.roc` with the
optimized native backend, against `scripts/flight.py`'s served bundle,
and compares every line with cached `oracle.jsonl`. No oracle dependency
is needed for replay, and no generated Roc source is used.

## Deliberate reference divergence

HarfBuzz 14.6.0 ignores MATH VariationIndex devices: its `MathValueRecord`
implementation calls `get_x_delta(font)` / `get_y_delta(font)` without a
GDEF variation store. Current upstream supplies that store. roc-font uses
the checked GDEF store, preserving variation support instead of silently
returning static values. Accordingly, the two nondefault variable cases
identify their oracle as `fonttools-varstore-and-harfbuzz-materialized`:
fontTools independently evaluates variation deltas and materializes the
MATH values, and HarfBuzz then checks the resulting static queries.
The other four cases use direct HarfBuzz queries. This distinction is
recorded in each cached result's provenance.

Pixel devices are structurally validated, but are not applied: font-unit
queries have no ppem, as with HarfBuzz at ppem zero. The public raw accent
attachment and italic-correction queries expose explicit absence, rather
than HarfBuzz's half-advance/zero synthesis. The recorder compares absence
with the fontTools coverage and validates the corresponding HarfBuzz
fallback separately.
