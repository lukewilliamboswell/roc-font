# Outline and ligature caret fixtures

These are original synthetic geometric drawings and table fixtures under
roc-font's UPL licence. No third-party font is derived or modified.

`generate.py` with pinned fontTools 4.61.1 reproduces all `.ttf` files.
`oracle.py` with uharfbuzz 0.56.3 (HarfBuzz 14.6.0) records `oracle.json`:
HarfBuzz draw commands, HarfBuzz caret queries, and independently expanded
fontTools contour points. It also records the existing variable outline
fixture at several locations. The cached answers need no oracle installed
to read or use in tests. No Roc source is generated.

`outlines-carets.ttf` includes ordinary lines, consecutive off-curve
points, a contour containing only off-curve points, anchor placement and
nested composites. The `wght` axis moves a contour point and a phantom
point. Three carets on glyph1 exercise GDEF formats1,2,3: explicit150,
contour point1, and explicit250 plus a variation-store delta up to80.
At weights400,650,900 the point's x values in HarfBuzz's draw output are
500,521.5,543. The fractional value is preserved by roc-font.

HarfBuzz's OpenType font backend returns0 for format2 carets because it
has no contour-point callback. The format2 expected result therefore uses
explicit contour geometry (independently checked with fontTools at default
and endpoint locations), not that unavailable callback result. fontTools
static instancing rounds metrics to whole font units, so its intermediate
instance may differ from unrounded draw geometry.

HarfBuzz emits a closing line before closePath for some contours.
roc-font's Close already closes the contour, so the redundant line is
omitted. Compare geometry rather than command-count identity. Nested
point-attached composites preserve the existing HarfBuzz14.6 placement
order, including its root-relative anchor handling.

`bad-point`, `bad-index`, `bad-coverage` isolate malformed GDEF references.
`deep-identity` has a valid64-level single-child chain. `numeric-overflow`
has the same topology with near2 coefficients in every matrix entry;
its work/depth are bounded but its numeric envelope is not. OTS9.3 accepts
both; roc-font deliberately rejects the latter under its explicit
conservative2^100 font-unit coordinate-envelope limit. The final phantom
shift may double a permitted envelope. No coordinates are silently repaired.

Public tests are `tests/api/OutlineTests.roc` and `CaretTests.roc`;
`tests/api/outlines-carets.roc` is their dedicated app. They must import the
served bundle using `scripts/flight.py`, as all package consumers do.
`fuzz/font-outlines.roc` exercises generated32/128/512-point outlines and
carets, real built-in font seeds, mutated bytes, finite output,
determinism, cardinality, bounded path output, allocation scaling and leaks.
`fuzz/outline-diagnostic.roc` intentionally crashes after reporting native
allocation counts; it is a measurement helper, not a fuzz campaign target.
