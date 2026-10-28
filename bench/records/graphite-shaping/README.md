# Graphite shaping measurements

These October27 de79a0f optimized native measurements use the actual Graphite
backend through the served package. Each of three increasing text sizes checks
an ordered checksum of glyphs, clusters, advances, offsets and unsafe-break
flags against the pinned HB14.6 Graphite adapter before timing is accepted.
Preparation is excluded. The JSON retains bundle, compiler, executable and
oracle hashes, five interleaved same-run timing ratios, allocation calls and
leaks. Requested and peak-live bytes are unavailable in roc-fuzz0.4.3.

The wave4 records establish a baseline, not a final performance claim. Charis
and Scheherazade ratios are approximately stable with size. Padauk rises from
about13.5 to59 times HB, despite approximately linear allocation calls. The
paired copy-destructuring experiment preserves identical outputs and counts
and does not improve that growth; it must not be credited as a performance
fix. Later rule-order improvements require their own paired measurements.

Awami is deliberately absent while its remaining reference differences are
being resolved. Its performance must not be presented as equivalent work yet.

The subsequent local deleted-marker gap shortcut also leaves the measured
Padauk scaling unchanged: paired before ratios13.38/22.65/56.50 and after
13.34/22.79/57.99, with the same6405/25560/102172 allocation calls. Ordered
outputs agree exactly and no leaks are reported. This negative result does
not establish that cursor-order searching is the dominant remaining cost.

Byte-preserving pass-prefix diagnostics pin the growing counted work to
Padauk's final positioning pass. Prefixes through the fifth pass have stable
per-scalar budgets; adding the sixth increases the minimum factor from176
at1024 scalars to380 at4096. Its rule10 reads absolute X positions after
other actions have dirtied the full-run geometry cache. Incremental geometry
queries are a concrete optimization direction; this evidence is diagnostic,
not a correctness waiver or a completed optimization.
