# Fuzzing

Seeds and dictionaries for roc-font's [roc-fuzz](https://github.com/lukewilliamboswell/roc-fuzz)
targets. `seeds/<target>.json` holds reviewed starting inputs, each with the
reason it is there; `dictionaries/font.dict` holds font tags, signatures and
edge values for mutation. `scripts/run_fuzz.py` adds every real font found in
`tests/fonts/` and `tests/corpus/` as a further seed.

The targets are `font-read.roc` and `font-shape.roc`. They import the
package through `package/main.roc`, exactly what ships, and the test-only
byte builders (`FontBuild`) through `tests/support/main.roc`, which
`package/main.roc` never reaches.

Run every target briefly with the compiler pinned in `.roc-version`:

```sh
python3 scripts/run_fuzz.py smoke
```

Contracts, longer runs, the corpus, and how to turn a failure into a
`## fuzz regression:` expect are described in `docs/fuzzing.adoc`.
