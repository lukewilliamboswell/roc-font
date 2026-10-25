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

### Release pipeline

- [ ] The workflow's `GITHUB_TOKEN` cannot create releases on roc-font
  (HTTP 403; a user token needs the `workflow` scope for the same request),
  though roc-ansi's can with identical settings. 0.1.0-rc1 was published
  locally from the run's tested artifact (assets verified byte for byte).
  Fix before 0.1.0: find the difference, or give `publish-release` a
  release token (fine-grained: Contents and Workflows write) from the
  `release` environment.

### Consumers

- [ ] package-mermaid: proven on `roc-graph-layout` branch
  `feature/package-mermaid-roc-font` (worktree
  `.claude/worktrees/mermaid-roc-font`, roc-font `70f5adb` vendored):
  oracle sizes and SVGs byte-identical, 0 differences over 99,771
  measurements, 2.8x faster. Switch the vendored copy to the 0.1.0-rc1
  URL, re-run its oracle suite, and report API feedback.
- [ ] roc-pdf: proven on branch `feature/roc-font-latin` (worktree
  `~/Documents/Github/roc-pdf-wt-roc-font`, roc-font `ad2e6bb` vendored,
  staged, commit pending signing): kerning and ligatures via
  `KernelOpenTypeShape`, a `Text.Store` producer, 417 cases with 0 baseline
  differences, 15 strings exact against HarfBuzz. Rebase on roc-pdf's
  `main`, switch to the 0.1.0-rc1 URL, and report API feedback.

### Release

- [ ] Re-check the figures in `docs/releases/0.1.0.adoc` if anything lands before tagging.
- [ ] Just before tagging: the default-branch ruleset from roc-automation's
  settings chapter (pull request, required checks `check` and the release
  dry-run build, signed commits, no bot bypass), verified with a pull
  request whose check fails; then integrate by pull request. Everything
  else in `blueprint run check-settings` already passes.
- [ ] Gather 0.1.0-rc1 feedback (package-mermaid, roc-pdf), settle names,
  then release 0.1.0 with every check in `AGENTS.md`.

## After 0.1.0

- Re-source the AOTS-derived scored suites (`harfbuzz/aots`,
  `hb-pending/*`): OTS refuses their fonts' format 4 `cmap` fields, so
  they now read as rejected by design; regenerate valid fonts with the
  same lookups.
- Optional speed-up: U64 fast paths for TableVar's single-precision
  multiply and add (85 % of gvar extents time).
- Reading cost: about 150x HarfBuzz (geometric mean; HarfBuzz checks
  lazily, roc-font validates everything up front as OTS does, every glyph
  outline included). Profile the OTS checks and the outline walk; the
  default fonts are prepared at compile time and unaffected.

1. roc-ray measurement and terrocotta's measurer.
2. roc-pdf's strict checks (checksums, overlap, composite cycles, `fsType`,
   work counters) and subsetting (`KernelFontSubset.roc`,
   `KernelFontPlan.roc`).
3. GPOS single, cursive, mark attachment, contextual positioning.
4. Outlines as a listing; CFF and CFF2.
5. Complex-script shapers (Arabic, Indic, USE, Hangul, Tibetan, Thai)
   with a per-script support matrix; 109 in-house Tibetan cases need
   `abvs`/`blws`, and Thai `sara-am` 52.
6. WOFF/WOFF2 unwrapping outside the core.

## Open questions

1. Can roc-pdf accept aggregated problems instead of a first error, and
   does it need work counters in the public result?
2. Subsetting: in roc-font, or in roc-pdf on raw table access?
3. roc-ray: glyph-id drawing with a host atlas, or code-point drawing?
4. WOFF/WOFF2: a module here or a separate package?
5. Cluster levels beyond `Graphemes` and `Characters`?
6. Which `unicode` version can a paragraph layer pin?
