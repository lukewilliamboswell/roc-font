# Myanmar model fixtures

The unmodified Noto Sans Myanmar2.107 and Noto Serif Myanmar2.106 regular
TrueType fonts are pinned to official release archives in `sources.json`.
Each ships its complete SIL OFL1.1 notice. They are test fonts, never
package default fonts or bundle resources. Both expose the modern `mym2`
script and pass OTS9.3.0.

`generate_synthetic.py` creates the original UPL fixtures `modern.ttf`,
`legacy.ttf` and `no-circle.ttf`. They distinguish modern script activation
from the old `mymr` tag, prove feature stage ordering via an eight-step
substitution chain, exercise GDEF-early zero-width marks without GPOS, and
prove that a missing dotted-circle glyph does not substitute glyph zero.

`generate_cases.py` authors the finite JSONC input matrix in
adjacent `myanmar.jsonc`. It covers two real font families and the three
original boundary fonts and four CCMP/reorder stress fonts, both directions, kinzi, stacks, medials, below-vowel mark
classes, repeated pre-vowels and variation selectors, broken clusters,
explicit/missing dotted circles, joiners, language selection and disabled
features. Long syllables cross HarfBuzz's64-glyph syllable-visit boundary
while retaining one DFA serial. The pinned standard HarfBuzz14.6.0 oracle records glyphs,
clusters, advances, offsets and unsafe flags; replay uses the optimized
native conformance driver importing the served package bundle, without
HarfBuzz installed. No `.roc` test source is generated from an oracle.

Reproduce the original fonts and matrix with fontTools4.61.1, then record:

```
python tests/fonts/shaping/myanmar/generate_synthetic.py
python tests/fonts/shaping/myanmar/generate_cases.py
ROC_FONT_ORACLE_VENV=/path/to/pinned/venv python scripts/record_oracle.py tests/fonts/shaping/myanmar/myanmar.jsonc
```

The implementation follows the pinned Myanmar Ragel machine and reordering
in HarfBuzz14.6.0. Generated categories and DFA arrays come from the shared
pinned shaping-data generator. Its linear stable counting sort uses flat
U64 origin/rank lists, and private exhaustive comparisons against HarfBuzz's
insertion-sort cluster-merging algorithm cover729 position permutations
and four monotone cluster patterns. Every phase shares the shaping budget;
dotted-circle insertion also observes the output growth limit.

Modern Myanmar has Unicode composition without the normalization short
circuit, GDEF-based mark advance zeroing before GPOS, and no geometric
fallback mark positioning. The `DFLT`, `latn` and old `mymr` selected script
tags use the default model, matching HarfBuzz. The distinct `Qaag` Zawgyi
encoding mode is not claimed by this modern Unicode model.

The matrix stays outside global gating cases until exact native agreement
proves the Myanmar model activation. Moving the data does not change any
font bytes, expected result or reference key.


The staged matrix has682 exact records. All nine fixture fonts pass OTS9.3.
The four `sort-*.ttf` fonts first multiply one consonant into8,32,64 or256
copies in `ccmp`, after syllable assignment, before visual reordering. They
exercise metadata preservation across GSUB expansion and the64-glyph visit
limit. The fixed32-copy fixture fits a31-pre-vowel sequence into one63-glyph
visit and stresses stable ordering/cluster merges within that bound.

`fuzz/font-myanmar.roc` measures allocation growth at2/8/32 repetitions and
checks determinism, index alignment, font glyph references, monotone input
clusters, growth bounds and leaks. An explicit modern-font witness prevents
accidentally testing only a generic model. `bench/myanmar.py` compares the
same ordinary/stress inputs at8/64/256 repetitions with native HarfBuzz14.6,
using an explicit Myanmar plan and complete checksum agreement. It reports
allocation calls, elapsed time and same-run reference ratios independently.
Requested and peak live allocation bytes are not exposed by roc-fuzz0.4.3;
those metrics are explicitly unavailable rather than approximated by RSS.


Dotted-circle insertion deliberately follows HarfBuzz's remembered last
inserted broken-syllable serial, including the serial-wrap case with14
ordinary syllables between broken clusters. Both its counting and output
passes use that same rule. Budgeted permutation replacement is reserved
before changing glyph order, so exhaustion cannot duplicate or lose a glyph.
The cached wrap cases and private exact-growth/budget regressions protect
these behaviors. The benchmark records the native comparator's actual
`--version` response and hashes both its binary and linked shared library.
