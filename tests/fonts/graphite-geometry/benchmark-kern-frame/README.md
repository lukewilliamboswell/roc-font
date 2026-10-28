# Kerning-frame scaling baseline

The three cases reuse the original UPL font `kern-frame-audit/collision-kern-frame-child-part-160.ttf` at 4, 8 and 16 copies of `abc`. Its future attached child extends beyond the parent's displayed frame, exercising the per-glyph part bounds and finite sampled range. The original font and licence remain in that directory.

`before.json` records the retained immutable `2quGXL...` public artifact at explicit native speed optimization, with a source-sentinel build. All ordered public glyph fields match pinned HarfBuzz 14.6 before timing. Font preparation is excluded. The three calls allocate 94, 146 and 251 times, leak zero, and take 13.071, 14.000 and 14.317 times the paired reference respectively. Requested bytes and peak live bytes are unavailable from this fuzz platform and remain null.

The candidate frame correction has not yet been measured by this report. This baseline does not claim it is faster or reference-correct. `records.json` stores direct public Graphite2 slot results for the same font and text sizes; native public conformance remains a separate gate.

The isolated corrected candidate now has a separate matched report, `candidate-after-paired.json`. Its full-snapshot source, three-size allocation/timing results and remaining numerical failures are explained in `../kern-frame-audit/lifetime-candidate-evidence/performance.md`. The before evidence above remains unchanged.
