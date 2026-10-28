# Fixed-state insertion timeout regression

The unmodified 1,836-byte TestMORXThirtysix font is the exact HarfBuzz14.6 corpus seed that timed out in font-read and font-shape. Its own name table identifies Unicode2018/Sascha Brawer and OFL1.1; the font-specific OFL and surrounding test-suite notice are preserved separately. It is not an original UPL fixture.

A fixed-state type5 insertion inserts after the same current glyph without advancing. The previous split buffer repeatedly concatenated the growing unread suffix. The narrow shortcut materializes the identical budget/growth-limited partial output once. It does not change limits, operation charges, order, flags or general state-machine handling. The inline source regression retains the old iterative implementation and compares full items/charges/stop reasons for three insertion counts, budgets128/129/256/512, preceding clusters and growth boundaries.

The saved font-read replay exceeded35seconds. Three public native allocation runs over1/4/16 text-A scalars each made32,783calls, leaked0 and took35.453/35.919/35.391seconds end to end. Checksums20136577/20138506/20146312 are pinned independently for comparison. The before binary uses the Oct28 compiler and immutable6653 bundle; all AAT/shaping code is identical to the failing9fr snapshot (the other source changes are Graphite-only and a Font documentation addition). Timings include process startup/preparation and are not a HarfBuzz speed ratio. `before.json` preserves actual outputs and binary hash.

Native after measurements, exact failure replays and integrated conformance follow separately. No extra benchmark consumer or shared registry is changed here.
