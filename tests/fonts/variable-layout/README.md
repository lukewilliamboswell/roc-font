# Variable-layout fixtures

Tiny generated fonts for `package/LayoutVarTests.roc`. They are not real
typefaces: every glyph is empty, and only the layout and variation tables
matter. Both have two axes, `wght` 100–400–900 and `wdth` 50–100–150, and no
`avar`.

- `kern-var.ttf`: a `GDEF` version 1.3 item variation store with five
  regions (an intermediate one and a two-axis one among them) and three data
  subtables (16-bit, `LONG_WORDS` 32-bit and 8-bit deltas), and a `GPOS`
  `kern` feature with three lookups over glyphs `a`–`g`:
  - pair adjustment format 1 with x advance devices: `VariationIndex`,
    `NO_VARIATION` (0xFFFF/0xFFFF), a hinting device (format 1) and a null
    offset; then format 2 with x placement and x advance devices on the
    first glyph and y placement devices on the second;
  - format 1 through an extension lookup, with every value and every device
    on the second glyph;
  - format 2 without devices.
  Deltas are chosen so that some locations land exactly on halves, where
  HarfBuzz rounds up (`-50.5` becomes `-50`).
- `feature-var.ttf`: a `GSUB` version 1.1 with `FeatureVariations`: five
  records whose condition sets use axis ranges (format 1), a value from the
  `GDEF` store (format 2) and and, or and not (formats 3, 4 and 5), each
  substituting the lookups of `calt` or `liga` (one substitutes both).

They are generated, byte for byte reproducibly, by `generate.py` (fontTools
4.61.1 from `tools/oracle/`):

    tools/oracle/.venv/bin/python -I tests/fonts/variable-layout/generate.py

`oracle.py` prints HarfBuzz 14.6.0's results for them (pair adjustments and
coordinates at 16 locations; the matching `FeatureVariations` record at 112
locations); the expects in `package/LayoutVarTests.roc` embed those values.

These files and the scripts are original work of the roc-font authors,
released under the repository's licence (`LICENSE`, the Universal Permissive
License 1.0). They contain no third-party font data.
