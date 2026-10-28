# roc-font backlog

Open work only. Delete an item when it lands; git history is the record.
Design and the reasons behind it are in `docs/architecture.adoc` (cited as
§N), working rules in `AGENTS.md`, tooling in `docs/*.adoc`. Paths to other
repositories are relative to `~/Documents/Github/`.

## To 0.1.0

### Browser parity (§6)

Exit: HarfBuzz agreement on the Latin, Greek and Cyrillic cases of the
in-house and text-rendering-tests suites, except listed known failures;
Chrome widths agree on package-mermaid's oracle texts.

### Tests and measurement

- [ ] `adv-huge-cmap/read` got slower (188 to 222 µs) when strictly less
  work was done: a code-generation effect of the nightly; re-check on the
  next nightly.
- [ ] When roc-fuzz releases `measure_memory!` (PR #82): switch
  `bench/roc/alloc.roc`, ratchet `requested_bytes` and `peak_live_bytes`.

### 0.1.0 polish from rc1 consumers

- [ ] package-mermaid on rc1: oracle sizes and SVGs byte-identical
  (`roc-graph-layout` branch `feature/package-mermaid-roc-font`, 4f77271,
  after regenerating its metrics-only Inter with real contours).
- [ ] roc-pdf on rc1: 417 cases pass, only its 4 roc-font cases re-pinned
  (`roc-pdf-wt-roc-font`, branch `feature/roc-font-latin`, fd005b4).
  Re-verify on main's API (`shape_traced` result, `is_missing`).

### Consumers

- [ ] package-mermaid: proven on `roc-graph-layout` branch
  `feature/package-mermaid-roc-font` (worktree
  `.claude/worktrees/mermaid-roc-font`, roc-font `70f5adb` vendored):
  oracle sizes and SVGs byte-identical, 0 differences over 99,771
  measurements, 2.8x faster. Switch the vendored copy to the 0.1.0-rc1
  URL, re-run its oracle suite, and report API feedback.
- [ ] roc-pdf: proven on branch `feature/roc-font-latin` (worktree
  `~/Documents/Github/roc-pdf-wt-roc-font`, on 0.1.0-rc1): kerning and ligatures via
  `KernelOpenTypeShape`, a `Text.Store` producer, 417 cases with 0 baseline
  differences, 15 strings exact against HarfBuzz. Rebase on roc-pdf's
  `main`, switch to the 0.1.0-rc1 URL, and report API feedback.

### Release

- [ ] Re-check the figures in `docs/releases/0.1.0.adoc` if anything lands before tagging.
- [ ] Gather 0.1.0-rc1 feedback (package-mermaid, roc-pdf), settle names,
  then release 0.1.0 with every check in `AGENTS.md`.

## After 0.1.0

### Font and shaping gaps

- [ ] CFF/CFF2 paths and extents, including CFF2 variation/blend
  evaluation. These currently return `Unknown` where the TrueType outline
  reader cannot supply them.
- [ ] Vertical shaping and vertical metrics/origins, including `VVAR`.
  Current horizontal direction choices do not implement a vertical run.
- [ ] AAT and Graphite shaping for fonts whose substitutions and
  positioning rely on those backends.
- [ ] `avar` version 2: cross-axis coordinate remapping and variation-store
  deltas, with the pinned fontTools/HarfBuzz cases as oracles.
- [ ] Variable TrueType advances from `gvar` phantom points when `HVAR` is
  absent, including composites; compare real locations against HarfBuzz
  and FreeType.
- [ ] Investigate duplicate-axis tags and their order/selection semantics
  against OTS and HarfBuzz. Settle the reader/query policy before changing
  handling; distinguish duplicate font records from repeated query tags.
- [ ] Legacy `kern` offsets when an RTL script is explicitly forced LTR:
  advances can agree while glyph offsets differ. Preserve the explicit
  direction and font-specific oracle cases when resolving this gap.
- [ ] WOFF/WOFF2 unwrapping outside the core.

### Evidence and performance

- [ ] Re-source the AOTS-derived scored suites (`harfbuzz/aots`,
  `hb-pending/*`): OTS refuses their fonts' format 4 `cmap` fields, so
  they now read as rejected by design; regenerate valid fonts with the
  same lookups.
- [ ] Extend real-family/oracle evidence for the remaining USE scripts and
  legacy Indic tags; implemented model selection is broader than the
  dedicated tested-family matrices in `docs/shaping-support.adoc`.
- [ ] Profile software single-precision arithmetic in variable outline
  queries; evaluate U64 fast paths while preserving exact results.
- [ ] Profile eager reading against OTS and HarfBuzz, separating validation
  and outline preparation from reusable query cost. Default fonts are
  prepared at compile time.
- [ ] Reduce script-specific shaping cost and the fixed cost of short
  runs, using the recorded three-size/reference comparisons and allocation
  ratchets rather than transferring costs into repeated queries.

### Consumer follow-up

- [ ] roc-ray measurement and terrocotta's measurer.
- [ ] Re-run roc-pdf's embedding/subsetting pipeline on the current API.
  Subsetting and document-specific validation/embedding policy stay in
  roc-pdf (`roc-pdf-wt-roc-font-replace`,
  `development/roc-font-replacement.md`); consume the names, raw tables,
  stored metrics, side bearings and embedding flags now exposed here.
- [ ] Confirm whether roc-pdf needs substitution provenance beyond the
  existing feature/component counts, and whether consumers need a simpler
  kerning-only shaping choice, before extending the public API.

## Open questions

1. roc-ray: glyph-id drawing with a host atlas, or code-point drawing?
2. WOFF/WOFF2: a module here or a separate package?
3. Cluster levels beyond `Graphemes` and `Characters`?
4. Which `unicode` version can a paragraph layer pin?
