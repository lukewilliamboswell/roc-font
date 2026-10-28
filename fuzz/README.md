# Fuzzing

Seeds and dictionaries for roc-font's [roc-fuzz](https://github.com/lukewilliamboswell/roc-fuzz)
targets. `seeds/<target>.json` holds reviewed starting inputs, each with the
reason it is there; `dictionaries/font.dict` holds font tags, signatures and
edge values for mutation, and `dictionaries/narrow.dict` choice bytes for the
narrow targets. `scripts/run_fuzz.py` adds every real font found in
`tests/fonts/` and `tests/corpus/` as a further seed of the targets that read
whole fonts.

The whole-pipeline targets are `font-read.roc` and `font-shape.roc`.
Narrow targets exercise individual features at increasing sizes and check
allocation growth, determinism and the feature's public contract:

- Character maps, coverage/class tables, GSUB lookup types and pair kerning:
  `font-cmap`, `font-coverage`, `font-gsub`, `font-gpos`.
- Contextual and attachment positioning: `font-position` and
  `font-position-context`, including nested order and work/depth limits.
- Variation stores, glyph variations and font locations: `font-var`,
  `font-gvar`, `font-layout-var`.
- Font facts: `font-metadata`, `font-math`, `font-outlines`, `font-color`
  and `font-color-images`.
- Script stages with licensed real fonts: `font-arabic`, `font-thai-lao`,
  `font-hangul`, `font-indic`, `font-khmer`, `font-myanmar`, `font-use`.
- Reading checks shared with OTS, one damaged table at a time: `font-ots`.

All targets import the served package bundle through `--replace-dep`,
exactly as downstream consumers do. Those that construct test fonts import
`FontBuild` through `tests/support/main.roc`; the package never imports
test builders or test fonts. Contracts and reviewed seeds are registered in
`scripts/run_fuzz.py`.

Run every target briefly with the latest Roc nightly:

```sh
python3 scripts/run_fuzz.py smoke
```

Contracts, longer runs, the corpus, and how to turn a failure into a
`## fuzz regression:` expect are described in `docs/fuzzing.adoc`.
