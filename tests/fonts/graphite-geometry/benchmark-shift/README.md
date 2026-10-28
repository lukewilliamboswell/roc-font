Original UPL four-subbox collision-shifting control. Both glyphs have four
identical full-size approximation rectangles. Glyph A uses FIX 1, glyph B is
frozen, and pass flags 1 run one forward SHIFT sweep. Repeating `ab` 4, 8, 16 times
exercises 8, 16, 32 scalar runs before any new coarse filtering.

All three cases match the cached full HarfBuzz 14.6/Graphite2 outputs using the
optimized Fnt query. `before.json` records a separate optimized Bph benchmark
(root 6653e4a plus reader 52b7e78), with ordered HB checksums checked in every
sample: 149/278/534 allocation calls, zero leaks, and median Roc/HB time ratios
16.25/31.11/49.76. Five interleaved samples run each case 16 times. Requested and
peak live bytes are unavailable from the current counter and explicitly null.
These are before measurements, not claims that the scaling problem is solved.

`generate.py --check` reproduces the font and three cases. `records.json` holds
independent raw public CAPI records; `public-records.json` and
`public-oracle.json` hold full cached default-HB glyph runs. No renderer or
engine implementation source was used.

`after-shifting-parts.json` compares the same inputs against the retained Bph
before binaries, with the exact e3edf5c after package (Collision f53b287).
Paired median Roc/HB ratios improve 16.75→14.97,31.24→20.01,48.13→22.37.
Allocation calls remain 149/278/534 with zero leaks. The largest control is
about 2.1 times faster, while still about 22.4 times slower than HB. Every sample
passes the same ordered full-output checksum in before, after and HB. This
measurement does not prove that the real Awami budget failures are resolved.
