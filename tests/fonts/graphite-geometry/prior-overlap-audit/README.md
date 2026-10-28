# Prior-offset overlap gates

These 42 original UPL fonts challenge candidate collection after an established collision offset. They use documented GTF/OpCodes structures and original rectangles through the adjacent original builders. Reference observations use only Graphite2 1.3.14's public C API and `gr_start_logging`; no implementation source was read or translated. A full subbox on unused glyph 0 retains the preload-neutral control. Generation is deterministic with fontTools 4.61.1.

This corpus records bounded gate evidence. It does **not** establish a general collision algorithm, arbitrary binary32 association, diagonal projection behavior or native Roc agreement. Original stage-timing counterexamples to unconditional descendant exclusion are separately preserved in `../attachment-lifetime-audit/`.

## 34 actual-prior boundary controls

Each first positioning pass establishes a collision offset on B. A starts IGNORE, so the first obstacle C alone establishes it. The second positioning rule attaches A to B, restores A's flags to zero, ignores C and installs the same signed movement bounds for every member of a comparison. `observations.json` derives the established offset from the first public trace rather than assuming the requested font dimensions produced it; the exact completed positions remain in the unlogged raw records.

Eight Y controls keep both boxes 300x600, attachment relative (80,170), margin zero and second-pass Y limits [-1000,1000]. Priors 100/300/414/415 retain A as an obstacle; priors 416/500/600/800 miss A entirely. The included cases return delta -430, producing final B Y -330/-130/-16/-15. Misses retain the prior. The current physical-displacement-only overlap calculation would accept A in all eight.

Eighteen challenges vary target height 300/900, child relative Y 80/300 and margin 10/30, retaining the child's 300x600 box. Both target heights have the same positive inclusion/miss boundaries:

| Relative Y | Margin | Included prior | Missed prior |
| --- | --- | --- | --- |
| 80 | 10 | 465 | 466 |
| 80 | 30 | 475 | 476 |
| 300 | 10 | 355 | 356 |
| 300 | 30 | 365 | 366 |

The remaining two challenges establish negative Y priors with target height 600, relative Y 170 and margin 0: -885 retains A; -886 misses it. Some included runs have fractional final movement, for example the height 900/relative 300/margin 30 case. The rounded logging text is not substituted for exact binary32 result bits.

Eight X controls use target/child boxes 300x600, relative (80,170), second-pass X limits [-1000,1000] and Y limits [-1,1]. Margin0 retains A at prior 460 and misses at 461; margin 10 retains 465 and misses 466. The negative side is asymmetric: margin 0 retains -1380/misses -1381; margin 10 retains -1390/misses -1391. Included cases return the target to X 0; misses retain the prior.

These observations fit a mixed guard in this matrix: physical displacement still supplies forbidden projections, while the coarse orthogonal rectangular gates use physical displacement minus the retained base offset. In the Y cases, the deciding upper comparison reduces to `priorY + relativeY <= 1000 - priorY + margin`. For X, the upper comparison has the analogous doubled prior, but the lower reflected window remains `-1000` without base subtraction: `priorX + 380 >= -1000 - margin`.

`observations.py` evaluates the explicit gates from measured priors. The Y matrix has the X-direction projection [-220,380], zero orthogonal gap and a false Y-direction overlap gate. The X matrix has the Y-direction projection [-430,770], zero gap and a false X-direction overlap gate. All deciding arithmetic here uses exactly representable integers. It does not distinguish binary32 association alternatives, both-gates-overlap behavior or all other shapes/sign combinations. The isolated boundary facts remain authoritative if a broader hypothesis changes.

## Matched geometry and captured coordinates

Two controls produce A(80,770), B(0,600), C(180,0) before the second collision result, which is zero in both. One attaches A to B with authored A/B advances 100/100. The other keeps A independent, gives it advance 0 and authored shift (80,770), and gives B advance 180. The root/cluster extents then match. Both traces omit A as an obstacle and retain C. Thus ancestry alone cannot explain the earlier second-pass exclusion.

Six controls declare one user attribute in Silf, store public PosY 19 into attr 22 (the first user attribute), and expose that stored value afterward through `gr_slot_attr`. A constant 123 control proves the store. Reading A before attachment captures 0; after attachment captures 770. Reading B through relative slot +1 captures 600 both before/after. All six completed geometries remain A(80,770), B(0,600), C(180,0). This disproves a simple claim that user-visible PosY necessarily remains stale after attachment; it does not expose every internal candidate-collection state. Uninformative multiply-by-zero probes are omitted.

## Reproduce and verify

`records.json` and `mode6-records.json` retain exact position/advance bits, attachment links as glyph ids, collision attributes and the captured user value where applicable. The public extractor's `prior_overlap_extractor` version identifies that schema. Every immutable record key hashes the full case, font bytes and oracle metadata, including library hash. `traces.json` contains normalized public logging, with no raw pointer identities.

`tracing-off-records.json` and `tracing-on-records.json` query the same tracing-capable library with logging disabled/enabled. All 42 results match each other and the release-library mode 0/mode 6 results exactly, including captured values. These ASCII controls contain no NSM text; this does not establish logging neutrality for other programs. All 42 original fonts also pass pinned OTS 9.3.0; `ots-proof.json` preserves the binary/font hashes and diagnostics. `provenance.json` hashes local assets and original helper dependencies.

Run from the repository root with Python and fontTools:

```sh
python -B tests/fonts/graphite-geometry/prior-overlap-audit/check.py
```

This regenerates/checks fonts and cases, verifies every cache key, mode/logging equality, all scalar/capture relations, OTS proof and source/data provenance without loading reference libraries or invoking a Roc compiler.

Deliberate refresh commands use `record.py` with its default mode 0 cases/output, then:

```sh
python -B tests/fonts/graphite-geometry/prior-overlap-audit/record.py --cases prior-overlap-audit/mode6-cases.jsonc --output prior-overlap-audit/mode6-records.json
python -B tests/fonts/graphite-geometry/record_traces.py --cases prior-overlap-audit/cases.jsonc --output prior-overlap-audit/traces.json
python -B tests/fonts/graphite-geometry/prior-overlap-audit/record_ots.py
```

For the logging pair, use the same tracing-capable `record.py --library`, mode 6 cases and respective tracing-off/on output names, with a temporary `--log-dir` only for the on run. Keep raw pointer-bearing log files outside the checkout. After reviewing changes, refresh `observations.py`, then `provenance.py`, and rerun `check.py`.
