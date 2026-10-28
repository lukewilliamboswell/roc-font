# Whole-neighbor eligibility for collision kerning

These 22 original UPL fonts preserve public Graphite2 1.3.14 observations. The geometry and programs are original, assembled from documented formats; no Graphite2 implementation source was read or translated. The fonts have proper Silf 5 headers and wide class offsets for collision pass flags. All pass OTS 9.3 with every Graphite table retained byte for byte.

The target has vertical bounds 0..600, except translated controls. Its margin sets a fixed allocated bin vector. Neighbor bounds cross both ends of that vector. Actual subbox controls distinguish a whole glyph's eligibility from its rendered ink.

The tested whole-glyph predicate is:

```
wholeMaxY >= cacheMinY - 2*margin
and floor((wholeMinY - cacheMinY + 1) / sliceWidth) < allocatedCount
```

This bounded model matches the preserved cases and 40 independent temporary margin/height boundary challenges. The integer-coordinate data do not distinguish every binary32 association or prove all fractional variable-font boundaries.

Lower eligibility extends below the vector's ordinary signed interval. With margin 10 and cacheMinY=-10, a neighbor whose wholeMaxY=-30 qualifies, while -31 is skipped. Margins 13/101 give inclusive maxima -39/-303. Translations +1000 and-1000 reproduce the boundary. Upper transitions are neighborMinY 922/923, 930/931 and 1109/1110 for margins 10/13/101 respectively. These are allocated-vector boundaries, independent of overlap with actual target cells.

The decisive subbox counterexamples are whole Y bounds [-255,0] with sole subbox upper byte 128 (actualmax=-127), and whole Y bounds [0,1000] with sole subbox lower byte 248 (actualmin approximately972.55). Both whole glyphs qualify even though all actual ink misses the eligible region. They produce a sentinel clamp and segment advance -299, rather than the skipped advance 701. Full-size part controls retain actual overlap. This rejects a per-part interval eligibility predicate and any requirement for actual occupied target/neighbor cell overlap.

Unused glyph 0 has an exact full-size subbox to neutralize the separately established preload geometry defect. Every result matches bit for bit in modes 0/6. The SAME tracing library also gives identical final public results with logging disabled/enabled; those equal the release-library records. This is a local logging-neutrality result, not a blanket claim about logging in Graphite. Exact binary32 positions/advances, links and collision attributes are retained.

`check.py` reproduces fonts/cases, verifies all cache keys, asserts proper Silf 5 from SFNT bytes, checks OTS table retention, compares mode/logging results and verifies the whole-versus-part observations. It needs Python with fontTools for generation but no oracle libraries. Generation used fontTools 4.61.1; records pin Graphite2 1.3.14 and OTS 9.3 binary hashes.

Run `python tests/fonts/graphite-geometry/kern-eligibility-audit/check.py` from the repository root. Refresh raw records with adjacent `record_modes.py`; use the mode 6 case/output paths for mode 6. Refresh public traces with parent `record_traces.py --cases kern-eligibility-audit/cases.jsonc --output kern-eligibility-audit/traces.json`. `record_logging.py` accepts `--library <tracing-library>` and optional `--log-dir <temporary-directory>` for the two instrumentation proofs. `record_ots.py --ots <ots-sanitize>` refreshes acceptance/table-retention evidence.

No core change, selector, generated Roc expected source, tolerance or deliberate oracle exception is included.
