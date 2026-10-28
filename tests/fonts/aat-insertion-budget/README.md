# Non-advancing insertion timeout regression

The unmodified 1,836-byte TestMORXThirtysix font is the exact HarfBuzz 14.6 corpus seed that timed out in font-read and font-shape. Its own name table identifies Unicode 2018/Sascha Brawer and OFL 1.1; the font-specific OFL and surrounding test-suite notice are preserved separately. It is not an original UPL fixture.

A type 5 state cycle insertion inserts after the same current glyph without advancing. The previous split buffer repeatedly concatenated the growing unread suffix. Consecutive after-current DontAdvance actions accumulate a flat reversed pending list, then materialize the exact input cursor before an advancing, before-current or marked action, or at the same resource boundary. Each inserted block retains its source mask; unsafe flags use the exact virtual cursor. It does not change limits, operation charges, order, flags or general state-machine handling. The inline source regressions explicitly execute the actual two-state cycle and retain the old iterative implementation and compares full items/charges/stop reasons for three insertion counts, budgets 128/129/256/512, preceding clusters and growth boundaries.

The saved font-read replay exceeded 35 seconds. Three public native allocation runs over 1/4/16 text-A scalars each made 32,783 calls, leaked 0 and took 35.453/35.919/35.391 seconds end to end. Checksums 20136577/20138506/20146312 are pinned independently for comparison. The before binary uses the October 28 compiler and immutable 6653 bundle; all AAT/shaping code is identical to the failing 9fr snapshot (the other source changes are Graphite-only and a Font documentation addition). Timings include process startup/preparation and are not a HarfBuzz speed ratio. `before.json` preserves actual outputs and binary hash.

Native after measurements, exact failure replays and integrated conformance follow separately. No extra benchmark consumer or shared registry is changed here.

The first fixed-state-only prototype did not enter the actual two-state cycle and did not improve native cost. It is superseded; equivalence checks alone are not presented as proof of performance improvement.
