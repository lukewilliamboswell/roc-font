# Phase-3 whitespace and group scanning

These 80 original UPL fonts isolate public Graphite2 1.3.14 collision-kerning behavior. They contain original synthetic outlines and original VM programs assembled from the documented public formats. No Graphite2 implementation source was read or translated. These observations explain the final collision-pass spacing difference in Awami text `الحمد لله`; no Awami derivative is distributed here.

Each font has three slots. The target has FIX|KERN flags 17, the middle slot varies, and the last obstacle has flags 0. The first two authored advances are 100; the last is 603. Both native directions are represented. A full-size subbox on unused glyph 0 neutralizes the separately documented preload geometry issue. All 80 mode-0 results match their mode-6 counterparts bit for bit.

For an inked 300 by 600 middle rectangle, the target increments are:

| Middle flags | Native RTL | Native LTR |
|---|---:|---:|
| 0, 4, 8, 12 | +210 | -210 |
| 2, 14 | -393 | -110 |
| 128, 130, 132, 136, 140, 142 | -193 | -310 |

Thus phase-3 neighbor scanning crosses START/END group markers, including markers on inked neighbors. This does not establish any change to normal-shifting grouping. Explicit SPACE 128 takes priority over IGNORE 2. An empty outline also behaves as whitespace, irrespective of the tested flags.

The remaining controls distinguish what “empty” means operationally. A zero-width vertical line, zero-height horizontal line, or point at (5, 10) still supplies ink constraints with flags 0 and is skipped with IGNORE 2. A real point outline at (0, 0), with all four raw bounding-box coordinates zero, behaves as whitespace. The observations support an all-zero bounding-box predicate, not a general zero-area or zero-extent predicate. Explicit SPACE 128 makes each of these shapes whitespace, including with IGNORE 2.

`generate.py --check` reproduces every font and case byte. `check.py` verifies generation, all cache keys, both-mode equivalence and the stated observational relations without loading an oracle. `record_modes.py` calls only the public C ABI and retains exact binary32 positions/advances plus collision attributes. `traces.json` contains normalized public `gr_start_logging` output for mode 0; library hashes and keys pin the tracing reference. Mode-6 records use the same preload option as HarfBuzz's Graphite adapter. The cached libraries report Graphite2 1.3.14; font generation used fontTools 4.61.1.

Reproduce from the repository root using Python with fontTools:

```sh
python tests/fonts/graphite-geometry/phase3-space-audit/check.py
python tests/fonts/graphite-geometry/phase3-space-audit/record_modes.py --cases phase3-space-audit/cases.jsonc --output phase3-space-audit/records.json
python tests/fonts/graphite-geometry/phase3-space-audit/record_modes.py --cases phase3-space-audit/mode6-cases.jsonc --output phase3-space-audit/mode6-records.json
python tests/fonts/graphite-geometry/record_traces.py --cases phase3-space-audit/cases.jsonc --output phase3-space-audit/traces.json
```

No runtime implementation, generated Roc expected source, reference tolerance, or deliberate comparison exception is included.
