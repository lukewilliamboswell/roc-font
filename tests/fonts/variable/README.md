# Variable-font fixtures

Tiny generated fonts for the variation tests: the public API tests in
`tests/api/` (`ReadTests.roc`, `VariationTests.roc`) read them, and the
expects in `package/TableVar.roc` and `package/TableGvar.roc` embed some of
their tables (printed by `../inline_tables.py`). They are not real
typefaces: only the variation tables, and for `var-outlines.ttf` a few
outlines, matter.

- `var-mapped.ttf`: two axes (`wght` 100–400–900, `wdth` 75–100–125), a
  non-linear `avar` map on `wght`, three named instances, an `HVAR` with five
  regions (including an intermediate one and a two-axis one), 8-bit, 16-bit
  and 32-bit (`LONG_WORDS`) deltas, an advance map shorter than the glyph
  list, and an `MVAR` with `xhgt` and `undo`.
- `var-implicit.ttf`: one axis whose default is its minimum (`wght`
  300–300–700, as Merriweather and Fira Code), no `avar`, and the implicit
  glyph-id advance mapping.
- `var-format1.ttf`: a format 1 advance map with 1-byte entries and 3 inner
  bits, and a data subtable with no regions.
- `var-outlines.ttf`: outlines with glyph variations (`gvar`): simple
  glyphs (one whose side bearing is not its xMin), composite glyphs (an
  offset, a scale, an x and y scale, a 2x2 transform with scaled offsets,
  `USE_MY_METRICS`, anchor points, a nested composite), an empty glyph,
  shared tuples, embedded peaks, intermediate regions, shared and private
  point numbers with untouched points to infer, zero, 8-, 16- and 32-bit
  deltas, deltas on phantom points, and two glyphs whose extents tell
  HarfBuzz's double-precision tuple scalar from a single-precision one.

They are generated, byte for byte reproducibly, by `generate.py` (fontTools
4.61.1 from `tools/oracle/`):

    tools/oracle/.venv/bin/python -I tests/fonts/variable/generate.py

`oracle.py` prints HarfBuzz 14.6.0's coordinates, advances and metrics for
them, and glyph extents for `var-outlines.ttf`; the expects in
`tests/api/VariationTests.roc` embed those values.

fontTools 4.61.1 cannot read `var-format1.ttf`'s `HVAR`: it reads `HVAR`
advance maps with its format 0 layout only. HarfBuzz reads it, and the
OpenType specification allows format 1 there.

These files and the scripts are original work of the roc-font authors,
released under the repository's licence (`LICENSE`, the Universal Permissive
License 1.0). They contain no third-party font data.
