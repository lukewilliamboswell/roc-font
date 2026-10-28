These are static, renamed Devanagari subsets of two OFL families from the
pinned Google Fonts commit in `pins.json`. Both retain the script's complete
layout features and the marks, join controls, dotted circle and Vedic ranges
selected by `prepare.py`. The original fonts are caller-independent test
assets; no package module imports them. Their complete OFL notices are beside
the files. `prepare.py --check` reproduces the exact bytes with the pinned
oracle environment (fontTools4.61.1). Both pass OTS9.3.0.

`indic-cases.jsonc` contains220 two-family cases, covering reph, pre-base
matras, conjuncts, below forms, nukta, broken clusters, join controls, Vedic
marks and explicit LTR/RTL requests. `indic-cases-records.jsonl` caches exact
HarfBuzz14.6.0/uharfbuzz0.56.3 records. Regenerate with the repository oracle
recorder; `verify.py` replays every record using an optimized native served
bundle consumer and the standard conformance protocol. The Indic matrix is registered in the global gate after full glyph,
cluster, position and flag agreement. Other model matrices are explicitly
selected and must pass their own complete replay before activation.

`bench.py --label before` captures native timing against a native HarfBuzz
loop and allocation counts at16/64/256 increasing text copies before model
activation. Use `--label after` on the same compiler and font bytes after
activation. Both loops exclude font preparation; allocation counters expose
calls and leaks, while requested bytes and peak live bytes are unavailable
with roc-fuzz0.4.3. Before-model results shape with the generic engine, so
cost ratios alone do not imply equivalent shaping behavior.


`khmer-cases.jsonc` and adjacent cached records cover280 two-family cases,
including coeng-Ro ordering, left matras, all five split matras, broken
clusters, join controls, feature choices, directions and cluster levels.
`prepare-khmer.py --check` reproduces the71/101KB renamed OFL subsets;
both pass OTS9.3. Run `verify.py --model khmer` for the independent native
activation gate. The shared benchmark selects Khmer only when passed its
known Khmer fixture (`bench.py --model khmer --label before|after`).
