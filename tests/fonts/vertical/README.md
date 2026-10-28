The original UPL fixtures isolate vertical metrics, substitutions, positioning,
origin fallback and VVAR advance/origin maps. Both static and variable CFF origins
are exercised. All 13 bundled fonts pass OTS 9.3.0.

Two renamed static Japanese OFL subsets preserve real `vhea`/`vmtx`, `vert` and
positioning data. `pins.json` records their upstream revision and source SHA256.
The existing OFL Mongolian USE subset supplies joining/FVS cases; that font has
no vertical metrics, so its oracle verifies synthetic vertical metrics, rather
than claiming a real Mongolian `vmtx` implementation.

Cached HarfBuzz 14.6.0 matrices (including glyph flags):

| File | Cases | Purpose |
| --- | ---: | --- |
| vertical-cases |340| Original metrics, controls, substitutions, positioning, VVAR |
| real-cases |528| Two Japanese families, TTB/BTT and explicit feature toggles |
| mongolian-cases |144| One Mongolian family, joining variants and controls |
| cff-cases |60| CFF/CFF2 VORG, VVAR origin maps and missing-VORG centering |
| vert-selection-cases |24| Selected-language preference and cross-table global fallback |
| vorg-policy-cases |2| Deliberate TrueType VORG policy difference |

The policy matrix follows the [OpenType VORG specification](https://learn.microsoft.com/en-us/typography/opentype/spec/vorg):
TrueType fonts must ignore VORG. HarfBuzz 14.6 uses that table with either outline
format. Those two differences need explicit known-case registration; they are
separate from the 1096 ordinary reference cases.

Pinned HarfBuzz enables `vert` by default in vertical text and searches it across
language systems. `vrt2` and `vkrn` are explicit feature requests; the fixtures
check these independently. The engine does not rotate outlines or implement
Unicode text orientation, column layout, bidi or line wrapping.

Generate/check from the repository root using fontTools 4.61.1:

```
python tests/fonts/vertical/generate.py --check
python tests/fonts/vertical/generate_cff.py --check
python tests/fonts/vertical/prepare.py --check
python scripts/record_oracle.py tests/fonts/vertical/vertical-cases.jsonc --check
python tests/fonts/vertical/verify.py
python tests/fonts/vertical/verify.py --cases real-cases --binary <public-driver>
```

`prepare.py` checks pinned source bytes in `/private/tmp` by default and downloads
missing sources. Pass `--source-dir` to use another directory. Native replay needs
no oracle installation. Verification status, including dependencies awaiting the
integrator's final native replay, is recorded in `verification.json`.
