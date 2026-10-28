# Matched optimized candidate measurements

These measurements use the immutable FUm candidate described in this directory. The shaping worker built both public consumers with explicit `--opt=speed`; allocation additionally uses `--fuzz`. Both consumers import the served archive through a source-sentinel mirror. Binary and reference-library hashes are in each report. The preserved before apps import the distinct 2qu artifact. This compares complete snapshots, not one isolated causal change.

Five interleaved samples at each increasing size verify the complete ordered HB14.6 Graphite checksum before timing. Font preparation is excluded. Requested bytes and peak live bytes are unavailable from roc-fuzz 0.4.3 and stay null.

| Workload | Copies | Before/after allocation calls | Before/after median Roc/HB ratio |
|---|---:|---:|---:|
| Child-part sampling frame | 4 | 94 / 84 | 13.114 / 12.727 |
| Child-part sampling frame | 8 | 146 / 124 | 13.756 / 13.662 |
| Child-part sampling frame | 16 | 251 / 205 | 14.307 / 14.076 |
| All-zero deleted-intermediate control | 4 | 125 / 125 | 5.514 / 5.604 |
| All-zero deleted-intermediate control | 8 | 225 / 225 | 6.626 / 6.808 |
| All-zero deleted-intermediate control | 16 | 426 / 426 | 7.552 / 7.687 |

Every measured shape leaked zero allocations. The short deleted-intermediate workload is deliberately degenerate and shows roughly 2–3 percent slower ratios; it is not representative font performance. The frame workload reduces calls and has modest ratio reductions. Neither establishes a general speed improvement.

The existing 15-case allocation ratchet reports 12 exact matches. All three changes are decreases in the kerning-parts workload: 77/122/210 become 70/107/179 at 4/8/16 copies, with identical ordered checksums and no leaks. The baseline remains unchanged while this candidate is isolated; adopting its runtime must update those three expected counts in the same integration change. No allocation increase is hidden by this report. Numerical conformance still has two downstream failures and the existing real-font/NSM gaps.

The ordinary Padauk control repeats the real Myanmar phrase at 256/1,024/4,096 scalars. Full ordered HB output matches at all three sizes. Calls remain 6,405/25,560/102,172 with zero leaks. Paired median ratios are 13.397→13.513, 22.600→22.863 and 57.439→58.067, about one percent slower in this run. The severe large-run CPU scaling gap remains visible; unchanged allocation growth does not excuse it. `ordinary-padauk-paired.json` preserves every sample and artifact hash.
