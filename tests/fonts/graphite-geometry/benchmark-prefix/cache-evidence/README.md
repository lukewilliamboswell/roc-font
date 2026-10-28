# Exact-prefix cache measurements

The retained before binaries import the immutable `2quGXL...` artifact. The after binaries import `6tcA4...` (source `1bbedbd`), containing the exact-prefix SHIFT cache through `1abce98`. Both use the October 27 Roc nightly recorded by hash in the reports, `--opt=speed`; allocation binaries additionally use `--fuzz`. Builds use served bundles and a source-sentinel mirror. Neither snapshot contains the later broad-window or pass-constraint candidates.

Each timing report interleaves five samples of sixteen executions with the pinned HarfBuzz 14.6 Graphite adapter. Ordered glyph IDs, clusters, advances, offsets and flags must produce the same checksum before timing is accepted. Font preparation is excluded. All six cases match the independent reference and leak zero allocations.

| Input | Copies | Before / HB | Cache / HB | Before calls | Cache calls |
|---|---:|---:|---:|---:|---:|
| SHIFT, unchanged later prefix | 4 | 14.710 | 14.661 | 149 | 150 |
| SHIFT, unchanged later prefix | 8 | 19.258 | 18.982 | 278 | 279 |
| SHIFT, unchanged later prefix | 16 | 23.451 | 22.849 | 534 | 535 |
| SHIFT, changed later prefix | 4 | 10.065 | 9.806 | 103 | 104 |
| SHIFT, changed later prefix | 8 | 16.114 | 15.591 | 175 | 176 |
| SHIFT, changed later prefix | 16 | 22.910 | 22.103 | 320 | 321 |

This is a modest measured CPU improvement, at most about four percent here, with one additional bounded flat pool per call. It does not resolve the remaining real-font geometry differences or default work-budget stops. Earlier dev conformance measured a reduced completion factor, but that result is recorded separately against its exact earlier source, not relabelled as this optimized snapshot.

`allocation-prototype-flat-result.json` and `allocation-prototype-consumed-result.json` preserve failed ownership experiments: unchanged prefixes cost one pool, but genuinely changed prefixes copied the pool once per changed root. Moving the mutable pool to a direct `Work.prefixes` field removed those copies; `allocation-final.json` records exactly one additional allocation at every size on both paths. The before twelve-case ratchet changes only its three SHIFT counts; the updated fifteen-case ratchet also covers the genuinely changing path.

Requested bytes and peak live bytes are unavailable from roc-fuzz 0.4.3 and remain null. RSS is not used as a substitute. The feature ratchet is local evidence; central allocation registration and the complete shared release checks remain integrator work.

The ordinary Padauk control also preserves exact HB output and zero leaks at 64, 256 and 1,024 scalars. Its before/cache ratios are 10.709/10.851, 13.434/13.701 and 22.681/22.908, with identical allocation counts 1,615, 6,405 and 25,560. Thus this run measures about one to two percent slower ordinary shaping, alongside the small collision-case gains. The cache is still provisional; these measurements do not establish a universal speed improvement. `after-padauk.json` retains all interleaved samples.

The final owned modules were replayed together in immutable `HqkKwp...`, source `5e5c31d`, after the refined broad-window fix and the independently owned pass-constraint correction. Both 1,316-case geometry matrices pass, and every previously passing shared matrix remains green. Main real-font conformance stays 1,024/1,069, with the same 45 Awami failures; unresolved NSM geometry remains separate. The full shared report is preserved by commit `d07c05d` under `bench/records/graphite-shaping/pass-conditions/`. These are native dev semantic results, distinct from the optimized measurements above. Whole-package release checks and central ratchet registration remain outstanding.
