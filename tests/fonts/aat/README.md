# Modern Apple font-program evidence

The original generated fonts are UPL 1.0 fixtures. `generate.py` covers all
five modern morphing types, processing order, feature toggles and ranges.
`generate_language.py` adds language-specific selection. `generate_tracking.py`
adds horizontal/vertical tracking and the STAT activation policy.
`generate_regressions.py` and `generate_rearrangement.py` reproduce class,
applicability and permutation boundaries. Every generator accepts `--check`.

Noto Sans Tamil MN 2.000 is an unmodified OFL font from the pinned HarfBuzz
14.6 corpus; `real-fonts.json` records its source/hash and the adjacent OFL
text accompanies it. One real family plus original programs is evidence
for these cases, not a claim of agreement for every Apple font.

The cached modern morphing matrices have 3,096 cases: 1,960 core cases,
240 language cases, 204 real-family cases, 24 replacement-class cases,
28 applicability cases and 640 rearrangement cases. The optimized public
driver compares glyphs, advances, offsets, original clusters and requested
unsafe flags with actual HarfBuzz 14.6 output. The class tests prove that
replacement glyphs acquire their new GDEF class, while Apple mark-width
zeroing leaves offsets unchanged unless positioning actually changes them.
The applicability tests prove that an end-of-text action alone does not
start a program whose initial-action glyph set does not intersect the run.

`tracking-cases.jsonc` adds 1,600 actual HarfBuzz 14.6 records across sizes,
both axes, graphemes, extrapolation and STAT presence. `record_tracking.py`
sets ptem independently of the 1000-unit scale and converts HarfBuzz
codepoint cluster indices to public UTF-8 byte offsets. Replay uses
`verify_tracking.py`; the reference libraries are unnecessary for replay.

`font-aat.roc` fuzzes hostile program bytes, a real family, shaping choices,
bounded growth, index alignment, deterministic traces and leaks, with
three isolated lookup sizes and three tracking text sizes. The committed
report records a 1,000-input campaign; the final integrated gate may use a
later package artifact. `bench/aat-morx` separates preparation from use and
records matched native allocation/timing comparisons.

OTS can discard valid Apple tables. Container acceptance is not presented
as proof that OTS validated or retained a program. These readers retain
checked supported programs and report a broken optional table in lenient
mode; strict mode rejects the font for any such problem.
