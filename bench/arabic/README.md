Native Arabic fallback and Syriac stretch evidence. The consumers import a
served package bundle and measure shaping after font reading and planning.
The runner checks script, RTL direction, UTF8 length and an input checksum
for every timing sample. The native C loop calls pinned HarfBuzz 14.6.0 from
the oracle wheel; timing uses 128 iterations and five samples per size.

| Scenario | Input scalars | Allocation calls | Roc / HB elapsed ratio |
| --- | --- | --- | --- |
| Unicode presentation fallback |128 /512 /2048 |23 /23 /23 |2.81 /2.64 /2.65 |
| Windows-1256 fallback |128 /512 /2048 |23 /23 /23 |3.49 /2.82 /2.84 |
| Real Noto Sans Syriac joining/stretch |96 /384 /1536 |261 /936 /3627 |52.06 /55.37 /49.79 |
| Before Syriac activation, generic shaping |96 /384 /1536 |203 /731 /2843 |29.96 /31.28 /32.02 |

The real Syriac workload remains a substantial performance opportunity.
Its time and allocations scale with input size. The before implementation
produced different glyphs from HarfBuzz, so its lower cost is not an
agreement-preserving speed comparison. Presentation fallback has constant
allocation calls over these sizes. These font-specific results do not imply
an overall shaper performance ratio.

Each JSON records the exact font, bundle/archive and optimized binary hashes,
compiler and reference versions, and same-run elapsed ratios. The final
bundle is the integrated `f795f7f` snapshot, including positioning numerical
safety corrections. `syriac-before.json` uses an immutable `package/` export
of commit `7563e51`. All measured operations released their allocations.
Requested bytes and peak live bytes are unavailable in roc-fuzz 0.4.3;
JSON fields explicitly leave them unknown. Fuzz peak RSS is separate.

`oracle-verification.json` records 6,525 exact native cached comparisons in
the script worker snapshot. The root aggregate gate covers the later
integrated numerical corrections. `fuzz-final.json` records 1,500 native
runs on the final integrated bundle with seven fonts, stage-entry witnesses,
determinism, growth, cluster/index alignment, tracing and leak checks.

Run a fresh final measurement from a checkout with the pinned oracle Python:

    ROC=/path/to/latest/roc /path/to/oracle/bin/python bench/arabic/bench.py \
      --font 'tests/fonts/shaping/arabic-extra/NotoSansSyriac[wght].ttf' \
      --script Syrc --label final --output /tmp/syriac-final.json

`--bundle <hash>.tar.zst` selects an immutable before/after snapshot.
`--reuse --binary-label Syrc-final` reuses both native consumers for a second
font/script workload; the input guards still apply. The benchmark apps for
bundle-consumer registration are `bench/arabic/bench.roc` and
`bench/arabic/alloc.roc`; `ArabicBench.roc` is their shared pure helper.
