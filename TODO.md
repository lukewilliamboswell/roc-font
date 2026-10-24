# roc-font backlog

Open work only. Delete an item when it lands; git history is the record.
Design and the reasons behind it are in `docs/architecture.adoc` (cited as
§N), working rules in `AGENTS.md`, tooling in `docs/*.adoc`. Paths to other
repositories are relative to `~/Documents/Github/`.

## To 0.1.0

### Browser parity (§6)

- [ ] Restore an in-place fast path for ligature lookups (the adversarial
  100-lookup case went from 7.7x to 10.8x HarfBuzz).
- [ ] Decide the policy for cmap glyph ids past `numGlyphs` (HarfBuzz
  outputs them; roc-font treats them as missing; AOTS cmap4).

Exit: HarfBuzz agreement on the Latin, Greek and Cyrillic cases of the
in-house and text-rendering-tests suites, except listed known failures;
Chrome widths agree on package-mermaid's oracle texts.

### Tests and measurement

- [ ] Narrow fuzz targets still to add: gvar extents, LayoutVar kerning
  deltas and FeatureVariations.
- [ ] `adv-huge-cmap/read` got slower (188 to 222 µs) when strictly less
  work was done: a code-generation effect of the nightly; re-check on the
  next nightly.
- [ ] Optional speed-up: U64 fast paths for TableVar's single-precision
  multiply and add (85 % of gvar extents time).
- [ ] Record time ratios on an idle machine (`bench.py --check
  --update-baseline`, full run).
- [ ] When roc-fuzz releases `measure_memory!` (PR #82): switch
  `bench/roc/alloc.roc`, ratchet `requested_bytes` and `peak_live_bytes`.

### Consumers

- [ ] package-mermaid: proven on `roc-graph-layout` branch
  `feature/package-mermaid-roc-font` (worktree
  `.claude/worktrees/mermaid-roc-font`, roc-font `70f5adb` vendored):
  oracle sizes and SVGs byte-identical, 0 differences over 99,771
  measurements, 2.8x faster. After the 0.1.0 release, switch the vendored
  copy to the released package URL and merge.
- [ ] roc-pdf: proven on branch `feature/roc-font-latin` (worktree
  `~/Documents/Github/roc-pdf-wt-roc-font`, roc-font `ad2e6bb` vendored,
  staged, commit pending signing): kerning and ligatures via
  `KernelOpenTypeShape`, a `Text.Store` producer, 417 cases with 0 baseline
  differences, 15 strings exact against HarfBuzz. Rebase on roc-pdf's
  `main` and switch to the release URL after 0.1.0.

### Release

- [ ] Refresh the figures in `docs/releases/0.1.0.adoc` just before tagging.
- [ ] Just before tagging: the default-branch ruleset from roc-automation's
  settings chapter (pull request, required checks `check` and the release
  dry-run build, signed commits, no bot bypass), verified with a pull
  request whose check fails; then integrate by pull request. Everything
  else in `blueprint run check-settings` already passes.
- [ ] Every check in `AGENTS.md` on interpreter and native; tag 0.1.0.

## After 0.1.0

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
