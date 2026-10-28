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

- [ ] Finish integration checks for implemented CFF/CFF2 paths, control
  extents and variation/blend evaluation. Dedicated native proof: 2,943
  normative cases, 160 FreeType comparisons, and three explicitly cached
  HarfBuzz default-location draw discrepancies; two 1,000-input fuzz runs.
- [ ] Finish integration checks for implemented vertical shaping,
  metrics/origins and `VVAR`: 1,098 cached cases, including two declared
  VORG/TrueType policy differences; real Japanese and Mongolian fonts.
- [ ] Finish shared integration checks for implemented AAT morphing,
  positioning and tracking. Modern morphing/language/real-font/regression
  matrices contain 3,096 exact native cases; tracking adds 1,600. Legacy
  morphing has 2,413 exact cases and positioning has 5,064 comparisons,
  including 16 independent fontTools contour controls. Dedicated native
  fuzz campaigns pass; the final shared-bundle workflow remains required.
- [ ] Complete experimental Graphite coverage: 45 main Awami cases
  (37 geometry differences and eight default operation stops), 544 broad
  nonspacing-mark/reverse-pass differences and overlapping focused
  diagnostics remain individually pinned. User-approved integration ships
  these as documented limits, not claims of reference agreement. The
  verified geometry snapshot passes 1,549 cases in both reference modes
  and 100 deletion cases; final shared checks remain required.
- [ ] Improve Graphite CPU scaling. Paired native measurements retain a
  Padauk positioning cost that grows disproportionately with input size.
  Lookup allocation counts alone do not establish linear elapsed time.
- [ ] Finish integration checks for implemented `avar` version 2,
  `gvar` phantom advances (including composites and vertical metrics),
  duplicate-tag setters and removal of the arbitrary 64-axis cap.
  Dedicated proof: 139 HarfBuzz cases, 61 FreeType comparisons, 41 public
  expects, 33 OTS-accepted positive fonts and a 1,000-input fuzz run.
- [ ] Legacy `kern` offsets when an RTL script is explicitly forced LTR:
  advances can agree while glyph offsets differ. Preserve the explicit
  direction and font-specific oracle cases when resolving this gap.
- [ ] WOFF/WOFF2 unwrapping outside the core.
- [ ] Interpreted `BASE` baseline facts for consumers aligning different
  scripts or font families. Original table bytes are available now; a
  consumer should establish the query shape before adding a public API.
- [ ] Font-defined target-width justification, if a downstream layout
  package needs it. Reading Graphite justification attributes does not
  expose `gr_seg_justify`/HarfBuzz justification as a Roc query; paragraph
  and line-breaking policy remain outside this package.

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
