# Sinhala USE oracle matrix

`UseSinhSans.ttf` and `UseSinhSerif.ttf` are renamed static subsets of Noto
Sans/Serif Sinhala. Both have the `sinh` OpenType script. Original source
URLs, hashes, selected axes and subset hashes are in `pins.json`; complete
SIL OFL notices are beside the fonts. Sources come from the same pinned
Google Fonts commit as the broader Indic matrix. Test fonts are excluded
from the package bundle.

Reproduce with pinned fontTools4.61.1: `prepare.py --check`. Both subsets
pass OTS9.3.0. `cases.py --check` reproduces400 inputs covering independent
and split vowels, conjuncts, reph, join controls, CGJ, variation selectors,
broken clusters, long64-bounded syllable visits, feature overrides and
all Sinhala invalid-vowel constraints from the pinned Microsoft data.

`sinhala-cases-records.jsonl` records independent HarfBuzz14.6.0 results,
including exact advances, offsets, UTF-8 clusters and unsafe flags. No
oracle installation is needed for replay. Until activation is proven,
this matrix remains outside default conformance gates. Run the staged
matrix explicitly with:

    python3 scripts/conformance.py tests/fonts/shaping/use-sinhala/sinhala-cases.jsonc
