# Two-family Indic oracle matrix

These sixteen renamed static subsets of Noto Sans/Serif cover Bengali,
Gurmukhi, Gujarati, Odia, Tamil, Telugu, Kannada and Malayalam. The complete
upstream OFL licences are adjacent. Original fonts and licences come from
one pinned Google Fonts commit; `pins.json` records source URLs, hashes,
subset hashes, selected axes and every retained OpenType script tag.

Use pinned fontTools 4.61.1 to reproduce with `prepare.py --check`.
`cases.py --check` reproduces all1,044 inputs. Every subset passes OTS9.3.
The fonts keep all layout features and script-block characters plus common
controls, Latin punctuation/context and available Vedic characters.
All public family/PostScript names are changed; fixed timestamps make
subsetting reproducible. No test font enters the package bundle.

The cached HarfBuzz14.6.0 records compare glyphs, advances, offsets,
UTF-8 clusters and unsafe-to-break flags, in both requested directions.
Selected cases use character clusters. Inputs include reph, prebase and
other matras, conjuncts, ZWJ/ZWNJ, CGJ, broken and repeated-halant syllables,
word boundaries, Bengali composition exclusions, Tamil AU, Kannada Ra
ordering/double halants and Malayalam encoded repha/chillu/old chains.

`verify.py` replays the complete cache through the optimized native driver
and a served package bundle. This matrix remains outside the global gate
until the corresponding model activations agree. Modern Noto predominantly
uses version2 tags; these records alone do not prove legacy tag coverage.
