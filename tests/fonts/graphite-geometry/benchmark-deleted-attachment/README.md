# Deleted-intermediate traversal: matched before baseline

This fixture is deliberately degenerate. A→D→activeRoot is established, D is deleted, and A/D attachment deltas and advances are zero. Root and trailing-root advances are ALSO zero, so every repeated word begins at the same pen position. It exercises linked deleted-intermediate traversal at 4/8/16 copies of `abcd` without conflating traversal cost with an already-known public-output correction. It is not representative font performance.

The original requested positive-root variant (root 603/tail 604) is preserved separately as `positive-root-diagnostic.ttf`. Zero attachment deltas alone do not make that variant match: the old engine leaves later A positions at zero instead of the increasing root pen. All three complete Hqk query failures remain in `before-public-proof.json`, with actual and reference answers. They are excluded from matched timing, never filtered from a correctness claim.

The all-zero fixture matches the preserved Hqk public query at all three sizes. Separately, the preserved optimized 2qu speed/allocation apps match the full ordered HarfBuzz 14.6 Graphite glyph/cluster/advance/offset/flag checksum for every timed sample. These are DISTINCT before snapshots: Hqk query source 5e5c31d, and preserved 2qu speed apps. Their exact binary hashes, bundle labels and reported compiler metadata are retained. No Roc binary was rebuilt; the authorized existing original C reference wrapper alone was recompiled.

| Copies | Scalars | Output glyphs | Before allocation calls | Leaks | Median before Roc/HB ratio |
|---:|---:|---:|---:|---:|---:|
| 4 | 16 | 12 | 125 | 0 | 5.56 |
| 8 | 32 | 24 | 225 | 0 | 6.31 |
| 16 | 64 | 48 | 426 | 0 | 7.34 |

These are BEFORE measurements only. Five interleaved samples each execute 16 shapes; font reading, planning and process startup are outside the timed region. Short synthetic timings are noisy and establish no after speedup. Requested bytes and peak live bytes are unavailable from roc-fuzz 0.4.3 and are explicitly null in the report. `before-speed.json` retains every sample rather than only medians.

The font and programs are original UPL data derived from documented formats, with proper Silf 5 headers. No Graphite2 implementation source was read or translated. Both the all-zero fixture and positive-root diagnostic pass OTS 9.3 with all Graphite tables retained byte-identically. Exact public Graphite2 1.3.14 C API and true HB 14.6 Graphite records cover every size in both sets. The generator preserves all state and the checker independently verifies every attachment coordinate/advance assignment from the actual action bytes.

Run `python tests/fonts/graphite-geometry/benchmark-deleted-attachment/check.py` from the repository root. It reproduces fonts/cases, verifies immutable oracle/OTS keys, confirms the before query's three matches and three retained failures, and independently recomputes the ordered native benchmark checksums from cached HB output. No oracle or preserved binary is needed for this offline check.

To rerun the before timing with the preserved apps:

```sh
ROC=/path/to/roc python tests/fonts/graphite/bench_shapes.py --reuse --font tests/fonts/graphite-geometry/benchmark-deleted-attachment/all-zero-advances.ttf --script Latn --direction ltr --text abcd --sizes 4,8,16 --work /path/to/preserved-before-apps --output /tmp/deleted-attachment-before.json
```

Use the existing public bundle benchmark workflow to build a separate after work directory when the corrected traversal is ready. This corpus changes no shared allocation baseline, selector or runtime source and makes no after-performance claim.

The isolated corrected candidate now has a separate matched report, `candidate-after-paired.json`. Its full-snapshot source, three-size allocation/timing results and remaining numerical failures are explained in `../kern-frame-audit/lifetime-candidate-evidence/performance.md`. The before evidence above remains unchanged.
