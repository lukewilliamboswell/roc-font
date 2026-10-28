# Graphite2 glyph preloading changes collision geometry

These are original public-format fixtures and public C-API observations, not a
single package-output gate. **Face options are semantic reference inputs here.**
The 224 records cover 43 original fonts in four modes plus 13 real-font strings
in four modes. No Graphite2 implementation sources were read or translated.
Original fonts and scripts are UPL licensed; real fonts are referenced from the
existing `../../graphite/` files and retain their existing licenses and pins.

The public Graphite2 header defines default=0, preloadGlyphs=2, cacheCmap=4 and
preloadAll=6. HarfBuzz 14.6.0's MIT-licensed adapter uses
`gr_make_face_with_ops(..., gr_face_preloadAll)` (`src/hb-graphite2.cc:128`).
Our original probes use the public file-face API with the same explicit flags.
The public-header definitions and adapter are the only engine-related source
consulted; all behavioral evidence comes from public queries/logging.

## Distinguishing observations

For `collision-preload-whole-only.ttf`, all modes accept the same font bytes,
produce the same glyph IDs, advances and segment advance 702, and decode the
same authored collision attributes. Modes 0/4 move B from 100 to 300 (collision
X 200); modes 2/6 leave B at 100 (collision X 0). The public trace identifies a
specific geometry difference: target bbox remains `[0,0,300,600]` in every
mode, but target slantBox changes from `[0,-600,900,300]` in 0/4 to
`[0,0,0,0]` in 2/6. The margin 50 and attachment controls also change output.
Cmap caching alone has no observed effect.

Adding one full-size subbox to **unused glyph 0** restores the expected nonzero
slant box and B=300 in every mode, while A and B still have no subboxes. Adding
that subbox to either A or B also restores agreement. Thus measured behavior
is face-wide, rather than specific to whether the colliding glyph owns a
subbox. This is an observed preload-sensitive geometry defect, not proof of
its internal implementation cause or a general rule for every possible font.
The half-size obstacle subbox changes geometry as authored in every mode;
a half-size target subbox does not change the whole target collision shape.

All eleven VM glyph-metric indices 0..10 give identical results across modes
(`0,302,600,0,0,300,600,300,602,0,0`). All sixteen explicit Glat glyph-attribute
queries also agree. Blank-target, blank-obstacle, no-collision and no-box-data
controls agree. Removing either required Glat or Gloc rejects the face in
every mode; no silent fallback to a missing table is inferred.

## Real-font scope

The matrix includes unmodified Charis, Padauk, Scheherazade and Awami. Its
`source_case` fields identify wave-one failure strings: Charis acute/258-scalar
stress; Padauk Myanmar and prebase sequences; three Scheherazade Arabic mark
sequences; Awami punctuation, Salam in both directions and Allah, plus a
long Arabic control. These are direct UTF32 C-API calls with `gr_nobidi`, not
a replay of HarfBuzz normalization, cluster policy, language or feature ranges.

**All 52 real-font results and normalized collision traces agree across the
four modes.** Awami exercises actual collision phases. Therefore those tested
real-font residuals cannot be excused by the original-font preload defect.
Other strings or feature selections remain unmeasured. No blanket collision
exception or deliberate package divergence is registered by this corpus.

## Cache and reproduction

`records.json` contains public result bits, attachment links and collision
attributes. `traces.json` retains public collision fields, with pointer strings
renamed by initial slot order. Every key includes the complete case (including
face mode), font SHA256 and oracle identity. `oracle-proof.json` records that
release and tracing Graphite2 1.3.14 libraries produced bit-identical results
for all 224 cases, and pins both binaries and cached outputs. The tracing build
source archive SHA256 is included; no implementation code was used.

From the checkout root:

```
python3 tests/fonts/graphite-geometry/preload-audit/check.py
python3 tests/fonts/graphite-geometry/preload-audit/record.py --check
python3 tests/fonts/graphite-geometry/preload-audit/record_traces.py --check
```

Those checks use only the standard library and existing caches/fonts. With
fontTools 4.61.1, `generate.py --check` reproduces every original font byte and
the JSONC cases. Without `--check`, the two recorders call their documented
public reference libraries; `--library` selects an explicit binary. Recording
a tracing-library result file separately and comparing every `result` against
the release file reproduces the bit-identity proof.
