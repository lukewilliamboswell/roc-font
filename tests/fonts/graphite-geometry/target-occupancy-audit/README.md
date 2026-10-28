# Target upper occupied-bin boundary

These 27 original UPL fonts preserve the distinguishing subset of 177 public Graphite2 1.3.14 observations. No Graphite2 implementation source was read or translated. Each font contains original synthetic geometry and a documented-format VM program. An exact full-size subbox on unused glyph 0 neutralizes the known preload geometry difference. All 27 public C API mode-0 results match their mode-6 counterparts bit for bit.

The target has either its whole bitmap-0 octabox or exactly one actual subbox. The whole glyph bounding box remains unchanged when the subbox shrinks. The measured last occupied target index fits:

```
w = F32(F32(2 * margin) / 3)
c = F32(wholeMinY - margin)
wholeCap = trunc(F32(F32(wholeMaxY - c) + 1) / w) + 1
partUpper = trunc(F32(F32(F32(partMaxY - c) + margin) + 1) / w)
last = min(wholeCap, partUpper)  # actual subbox
last = wholeCap                # whole bitmap 0
```

The data establish adding the upper margin before division, with a separate whole-glyph frame cap. They do not distinguish every binary32 association of the index expression. The cap is independent of allocated slice capacity: the H600/margin10 trace contains 140 slices but whole geometry ends at index 92.

The decisive sole bottom subbox with yMax byte 128, H600 and margin10 occupies through index 48; adding one bin after the unexpanded division would end at 47. Byte127 ends47; byte248 ends90; bytes254/full255 end at whole cap92. Margin30 and101, translation Y32000, a negative translation and thin/near-integer whole-height boundaries independently constrain the cap. Two additional thin-neighbor cases make terminal occupancy observable in final output. Case25 has targetH600, solepart128 and neighborY310..315; its public reference segment advance is911. The preserved pre-fix native query instead clamps a sentinel gap and returns a different run. Case26 (part127, neighborY303..307) is an adjacent control. `before-proof.json` records the old binary hash, exact request and complete answers; it is historical evidence, not a reference substitute.

The full-size actual subbox agrees with bitmap0.

`generate.py --check` reproduces every font/case byte. `check.py` verifies both cache-key sets, public trace keys, mode equivalence and exact observed terminal indices without loading an oracle. The raw C API records retain binary32 bits, authored advances and collision attributes. `traces.json` retains normalized public `gr_start_logging` output, not engine internals. Cached library hashes identify Graphite2 1.3.14; generation used fontTools 4.61.1.

Run `python tests/fonts/graphite-geometry/target-occupancy-audit/check.py` from the repository root. To refresh records, use the adjacent `record_modes.py` with `--cases target-occupancy-audit/cases.jsonc --output target-occupancy-audit/records.json` and the corresponding mode6 paths. Refresh traces with parent `record_traces.py --cases target-occupancy-audit/cases.jsonc --output target-occupancy-audit/traces.json`.

No runtime change, generated Roc expected source, tolerance or deliberate oracle exception is included.
