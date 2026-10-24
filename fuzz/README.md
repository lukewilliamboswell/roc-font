# Fuzzing

Seeds and dictionaries for roc-font's [roc-fuzz](https://github.com/lukewilliamboswell/roc-fuzz)
targets. `seeds/<target>.json` holds reviewed starting inputs, each with the
reason it is there; `dictionaries/font.dict` holds font tags, signatures and
edge values for mutation, and `dictionaries/narrow.dict` choice bytes for the
narrow targets. `scripts/run_fuzz.py` adds every real font found in
`tests/fonts/` and `tests/corpus/` as a further seed of the targets that read
whole fonts.

The whole-pipeline targets are `font-read.roc` and `font-shape.roc`. The
narrow targets each build fonts exercising one feature at two sizes and
check its contract and allocation growth: `font-cmap.roc` (character map
formats), `font-coverage.roc` (coverage and class definitions),
`font-gsub.roc` (one substitution lookup type at a time), `font-gpos.roc`
(pair kerning formats and `kern`), `font-var.roc` (variable fonts and
`Font.at`), `font-gvar.roc` (glyph variations and `Font.extents`) and
`font-layout-var.roc` (kerning device deltas and feature variations) and
`font-ots.roc` (the checks reading shares with OTS, one damaged table at a
time). All of them import the package through `package/main.roc`, exactly what ships, and the test-only
byte builders (`FontBuild`) through `tests/support/main.roc`, which
`package/main.roc` never reaches.

Run every target briefly with the compiler pinned in `.roc-version`:

```sh
python3 scripts/run_fuzz.py smoke
```

Contracts, longer runs, the corpus, and how to turn a failure into a
`## fuzz regression:` expect are described in `docs/fuzzing.adoc`.
