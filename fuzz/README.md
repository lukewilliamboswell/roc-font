# Fuzzing

Seeds and dictionaries for roc-font's [roc-fuzz](https://github.com/lukewilliamboswell/roc-fuzz)
targets. `seeds/<target>.json` holds reviewed starting inputs, each with the
reason it is there; `dictionaries/font.dict` holds font tags, signatures and
edge values for mutation, and `dictionaries/narrow.dict` choice bytes for the
narrow targets. `scripts/run_fuzz.py` adds every real font found in
`tests/fonts/` and `tests/corpus/` as a further seed of the targets that read
whole fonts.

The reader, shaping and variation targets share three executables built
from `reader_suite.roc`, `shaping_suite.roc` and `variation_suite.roc`.
Each suite builds once per run. Targets keep their individual names,
corpora and reports. Run `python3 scripts/run_fuzz.py list` to see the
suites and target contracts.

`font-read` and `font-shape` exercise the whole pipeline. Narrow targets
exercise one feature and check allocation growth where it applies.
Suites import the shipped bundle and share the test-only byte builders in
`tests/support/main.roc`. The spec models have their own suite in `spec/`.

Run every target briefly with the latest Roc nightly:

```sh
python3 scripts/run_fuzz.py smoke
```

Contracts, longer runs, the corpus, and how to turn a failure into a
`## fuzz regression:` expect are described in `docs/fuzzing.adoc`.
