Three original UPL fonts isolate the script policy for legacy kerning.
All glyph advances are 100 font units; each legacy `kern` pair adds 500.
`gpos-dist.ttf` also adds 500 through GPOS `dist`; `gpos-kern.ttf` instead
adds 200 through GPOS `kern`. All three pass OTS 9.3.0.

HarfBuzz 14.6.0 permits legacy kerning only when the selected shaper permits
fallback positioning (`hb-ot-shape.cc`, plan compilation). This restriction
does not disable real GPOS positioning. The 93 cached full-flags cases cover
Latin/Hangul controls and Devanagari/Bengali/Thai/Lao/Khmer/Myanmar/Tibetan,
including feature overrides and three mapped pairs. Five public API expects
exercise suppression and the independent GPOS/legacy paths.

Regenerate and verify from the repository root:

```
python tests/fonts/shaping/kern-policy/generate.py --check
python scripts/record_oracle.py tests/fonts/shaping/kern-policy/kern-cases.jsonc --check
python tests/fonts/shaping/kern-policy/verify.py
```

Generation requires fontTools 4.61.1. Native replay needs Roc and no oracle.
The verifier also accepts `--binary <already-built-public-driver>`.
