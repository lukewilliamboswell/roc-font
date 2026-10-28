Original UPL fixtures isolate two geometry paths at three increasing sizes.
`attachment.ttf` attaches a zero-advance glyph 80 units after its parent;
repeat `ab` 8, 32 and 128 times. `kerning-parts.ttf` gives both glyphs four
identical full-size Glat subboxes; repeat `ab` 4, 8 and 16 times. Duplicate
rectangles preserve the geometry while exercising the flat subbox cache.

The six cases are included in both public reference matrices. They agree with
the optimized served wave5 query before the pending first-cell correction;
that query's exact source, compiler and bundle are recorded in
`../native-wave5.json`. Timing and allocation results are separate evidence;
this directory does not claim that final performance gates have passed.

`generate.py --check` reproduces both fonts and cases. The parent raw extractor
checks `--cases benchmark/cases.jsonc --output benchmark/records.json --check`.
The fonts are original programs under the adjacent UPL license.

The native baseline reports are `before-attachment.json` and
`before-kerning-parts.json`, built with the explicit October 27 Roc compiler
against the immutable Bph safety bundle (root 6653e4a plus reader 52b7e78).
They use the same ordered output checksum as pinned HarfBuzz 14.6's Graphite2
adapter; all six checks pass. Five interleaved samples run each case 16 times.

| Path | Copies | Allocation calls | Leaks | Median Roc/HB time ratio |
| --- | --- | --- | --- | --- |
| Attachment | 8/32/128 | 82/251/926 | 0/0/0 | 4.34/5.97/6.43 |
| Four subboxes | 4/8/16 | 78/123/211 | 0/0/0 | 80.81/156.09/280.76 |

The subbox case is deliberately repetitive. Its allocation calls grow roughly
linearly, while the measured time ratio exposes a separate CPU scaling problem.
These are baseline results, not a claim that performance is acceptable or that
the final implementation has passed. Requested bytes and peak live bytes are
explicitly absent: the current roc-fuzz counter exposes calls and live allocation
counts, but does not report those byte measures. A failed earlier B16 attempt
used an obsolete case-header helper and produced no valid timing data; it is
excluded from these reports.

`after-attachment.json` and `after-kerning-parts.json` preserve paired native
measurements against the same retained Bph before binaries. The after package
is isolated e3edf5c (Collision exactly f53b287), including the spacing fixes and
both conservative filters but no later NSM direction draft. All nine cases,
including the SHIFT fixture in `../benchmark-shift/`, pass ordered full-output
checksums against both before and pinned HB in every sample.

| Path | Copies | Paired before/after median Roc/HB ratios | Calls before/after |
| --- | --- | --- | --- |
| Attachment | 8/32/128 | 4.32→4.45 /5.93→5.93 /6.23→6.29 | 82→82 /251→251 /926→926 |
| Four subboxes | 4/8/16 | 79.54→35.44 /146.74→36.56 /289.95→39.70 | 78→77 /123→122 /211→210 |

All measured leaks remain zero. The largest kerning control is about 7.3 times
faster than its paired before result; it remains about 39.7 times slower than
HB. The data therefore records a useful improvement and a remaining CPU gap,
not performance parity. Requested/peak byte measures are still unavailable.

`allocation-baseline.json` is the feature-owned exact call-count ratchet.
Run `python check_allocations.py --binary PATH_TO_ARTIFACT_SHAPE_ALLOC` with the
public allocation app built through the served dependency/sentinel. It checks
font hashes, cached independent output checksums, zero leaks and exact calls at
all nine sizes without loading HB. Both increases and decreases fail until an
explicit reviewed baseline update. Compiler provenance is recorded, never used
to pin the compiler. The after binary passes 9/9; the retained before binary
fails exactly the three changed kerning counts, providing a negative control.
Central all-tests registration remains an integrator-owned task.
