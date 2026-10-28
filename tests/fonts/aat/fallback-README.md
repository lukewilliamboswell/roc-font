# Mark fallback after Apple substitutions

These original UPL fixtures isolate the original script's mark-positioning and
mark-advance policy when a font uses Apple `morx` substitutions. The program
leaves the base glyph unchanged. No GPOS table positions the mark.

`fallback-marks.ttf` exactly reproduces the initial Hebrew/Arabic witness.
Hebrew RTL `סְ` yields glyphs `[7,1]`, advances `[0,700]` and offsets
`[(300,-162),(0,0)]` in HarfBuzz 14.6.0. `fallback-script-marks.ttf` additionally
maps real base/mark pairs for eleven script tags. `fallback-nonzero-marks.ttf`
uses the same mapping with mark advance 230 so retaining or zeroing that
advance is observable independently of the mark's offset.
`fallback-dflt-marks.ttf` additionally selects a GSUB DFLT script through an
identity rule; `fallback-gdef-dflt-marks.ttf` also explicitly classifies g7 as
a mark in GDEF. These distinguish the selected original default model from
an Indic or Myanmar model even though the caller supplies the same script.
`fallback-gpos-dflt-marks.ttf` adds a zero-valued GPOS pair. This disables
geometric fallback without moving either glyph, so original default-model
late mark-zeroing is independently visible. HarfBuzz returns zero mark advance
for Syriac/Devanagari/Myanmar in this variant.
HarfBuzz zeroes and positions the mark for Devanagari/Myanmar with DFLT here,
but retains its 230 advance without that DFLT selection.

`fallback-cases.jsonc` contains five preparation variants across Hebrew, Arabic,
Syriac, Hangul, Thai, Lao, Devanagari, Khmer, Myanmar, Tibetan and Latin, each
in all four directions: 220 cases. These are authored scripts and directions,
including deliberate direction overrides. The cached oracle controls the
expected policy; the tests do not enable geometric fallback for every script.
In particular Devanagari/Myanmar horizontal mark advance remains 230 in these
fonts; Hebrew/Arabic horizontal marks are positioned and zeroed. Vertical
Arabic provides a distinct original-model/default-policy control.

The files derive from the original UPL `direct-logical.ttf`; licensing is in
`fallback-LICENSE.txt`. Regenerate with fontTools 4.61.1:

```
python3 tests/fonts/aat/fallback-generate.py --check
python3 scripts/record_oracle.py --check tests/fonts/aat/fallback-cases.jsonc
```

The first command reproduces every font byte and case; the second validates
cache keys without running an oracle. Recording uses the repository's pinned
uharfbuzz 0.56.3/HarfBuzz 14.6.0 extractor with full output flags. All six
original fonts are accepted by pinned OTS 9.3.0. Native/public replay evidence
is reported separately after the served-bundle check, rather than inferred
from the reference records.

Native evidence in `fallback-proof.json` records an actual regression:
the initial fallback-policy fix agrees 214/220, with six nonzero mark-advance
differences in Syriac/Devanagari/Myanmar horizontal GPOS-DFLT cases; the
refined original-model selection fix agrees 220/220. Both optimized binaries
were built with Oct 27 against served bundles in source-sentinel mirrors.
The final public API expects are likewise checked through the served bundle.
