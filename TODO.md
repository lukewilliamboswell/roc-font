# roc-font backlog

Open work only. Delete an item when it lands; git history is the record.
Design and the reasons behind it are in `docs/architecture.adoc` (cited as
§N), working rules in `AGENTS.md`, tooling in `docs/*.adoc`. Paths to other
repositories are relative to `~/Documents/Github/`.

## To 0.1.0

### Reading (§4.4)

- [ ] Lenient reading accepts exactly what OTS accepts: reject (not drop)
  broken GSUB, GPOS, GDEF, OS/2, `post`, `name`; drop only the variation
  tables and an unsorted `kern`. Check every reading case against OTS.

### Variable fonts (§5.7, `docs/variable-fonts.adoc`)

- [ ] Wire phase 2 (`LayoutVar`: kerning deltas via `check_pair` inside
  `LayoutKerning.read_gpos`, `x_advance` with the PairSet base for format
  1; FeatureVariations in the shaping plan) and phase 3 (`TableGlyfPoints`,
  `TableGvar` extents) into `Font.at`; `TableGvar`'s extents replace
  `TableGlyf`'s header boxes.
- [ ] `Font.instances` and `Font.coordinates` (named instances and the
  normalised coordinates `at` resolves to); then the driver answers
  `instance=` and `coords` (20 + 35 recorded cases wait on them).
- [ ] Fuzz targets for the variation readers (`TableVar`, `LayoutVar`,
  `TableGvar`): totality, determinism, bounded steps, differential values
  at fuzzed locations.

### Default fonts (§5.8, `docs/default-fonts.adoc`)

- [ ] Expose `sans`, `serif`, `mono`, `*_bytes`, `*_licence` after variable
  phases 1 and 2 (two faces default to Light).
- [ ] `all_tests.py`: bundle step accepts exactly the files in
  `tools/default-fonts/pins.json`; run `tools/default-fonts/verify.py`.

### Browser parity (§6)

- [ ] `GDEF` glyph and mark attachment classes, mark filtering sets, GSUB
  lookup flags.
- [ ] GSUB types 3 (with the alternate chosen by the feature value) and 8;
  `frac` and `rand`.
- [ ] RTL: Unicode mirroring; the Hebrew shaper's GPOS rule.
- [ ] Language tags whose OpenType tag depends on a region or variant
  subtag (`zh-HK` and similar).
- [ ] Mapping steps of §6.2 (compose/decompose by cmap, default ignorables,
  space fallbacks, variation selectors via cmap 14, documented `.notdef`).
- [ ] Cluster merging to match HarfBuzz (the largest remaining difference
  group: emoji grapheme clusters in AdobeBlank2).
- [ ] Promote curated cases as they pass (now: 10 in M3, 2 in M4) (`tests/cases/curated.jsonc`
  `gating: true`, re-import, record, `--update-scores`).

Exit: HarfBuzz agreement on the Latin, Greek and Cyrillic cases of the
in-house and text-rendering-tests suites, except listed known failures;
Chrome widths agree on package-mermaid's oracle texts.

### Tests and measurement

- [ ] Narrow fuzz targets with allocation scaling (§7.3): cmap formats;
  coverage and class definitions; GSUB per lookup type; GPOS pair and
  `kern`; item variation store and HVAR; gvar.
- [ ] Optional speed-up: U64 fast paths for TableVar's single-precision
  multiply and add (85 % of gvar extents time).
- [ ] Record time ratios on an idle machine (`bench.py --check
  --update-baseline`, full run).
- [ ] When roc-fuzz releases `measure_memory!` (PR #82): switch
  `bench/roc/alloc.roc`, ratchet `requested_bytes` and `peak_live_bytes`.

### Consumers

- [ ] package-mermaid (`roc-graph-layout`, branch `feature/package-mermaid`,
  worktree `.claude/worktrees/package-mermaid/`): depend on roc-font, delete
  its local `Font.roc`/`FontShape.roc`/`FontTest.roc`, keep
  `TextMeasure.roc`; its Mermaid oracle suite (`tests/mermaid/`,
  `OracleSizes.roc`, `tools/mermaid-oracle/`) passes unchanged. Check
  whether `TextMeasure` models canvas `measureText` (word by word) or
  layout.
- [ ] roc-pdf (`roc-pdf/package/`): kerning and default ligatures in
  `KernelFacadeShape.roc`; a `Text.Store` producer from `Run`; under its
  pinned allocation and work counts (`roc-pdf/AGENTS.md`). Settle public
  names with its feedback.

### Release

- [ ] `roc docs` reviewed as the API; README example compiles against it.
- [ ] Bundle: package modules plus the default fonts and licences only.
- [ ] Examples (`examples/` with `spec.json` and the archive step) so the
  release and nightly workflows have something to check.
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
5. Complex-script shapers (Arabic, Indic, USE, Hangul) with a per-script
   support matrix.
6. WOFF/WOFF2 unwrapping outside the core.

## Open questions

1. Can roc-pdf accept aggregated problems instead of a first error, and
   does it need work counters in the public result?
2. Subsetting: in roc-font, or in roc-pdf on raw table access?
3. roc-ray: glyph-id drawing with a host atlas, or code-point drawing?
4. WOFF/WOFF2: a module here or a separate package?
5. Cluster levels beyond `Graphemes` and `Characters`?
6. Which `unicode` version can a paragraph layer pin?
