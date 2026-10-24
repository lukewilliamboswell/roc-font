# roc-font backlog

Open work only. Delete an item when it lands; git history is the record.
Design and the reasons behind it are in `docs/architecture.adoc` (cited as
§N), working rules in `AGENTS.md`, tooling in `docs/*.adoc`. Paths to other
repositories are relative to `~/Documents/Github/`.

## To 0.1.0

### Internal structure and API (§5.1, §5.9)

- [ ] The §5.9 surface: `ReadOptions`/`Limits`, `ShapeOptions`/`ShapeLimits`,
  integer font units, `U32` glyph ids, `Run`, `ShapePlan`, `plan`, `shape`,
  `shape_planned`, `shape_scalars`, `width`, `metrics` (line gap, cap and x
  height, underline, strikeout), `extents`, `family_name`, `glyph_name`
  (`name`, `post`), `code_points` as an `Iter` (benchmark against a `List`
  first, §5.6). Drop `substitute` and `kerning`.
- [ ] `ttcf` collections and `face_count` (§4.1); lenient and strict
  reading with `dropped`, problems naming table and offset (§4.4).
- [ ] HarfBuzz budgets in `ShapeLimits` (§6.3); update the growth bound in
  `fuzz/font-shape.roc`. Nested contextual lookups use an explicit work
  list once depth rises to 64.

### Variable fonts (§5.7, `docs/variable-fonts.adoc`)

- [ ] Phase 1: wire `TableVar` into `Font` (`Variation`, `at`, `axes`,
  Regular by default; HVAR advances, MVAR metrics).
- [ ] Wire phase 2 (`LayoutVar`: kerning deltas via `check_pair` inside
  `LayoutKerning.read_gpos`, `x_advance` with the PairSet base for format
  1; FeatureVariations in the shaping plan) and phase 3 (`TableGlyfPoints`,
  `TableGvar` extents) into `Font.at`; `TableGvar`'s extents replace
  `TableGlyf`'s header boxes.
- [ ] Driver protocol 2 (`docs/conformance.adoc`, "The driver"): kinds
  `coords`, `advances`, `metrics`, `extents`, flags `face`, `instance`,
  `weight`, `width`, `optical-size`, `axis`; then `DRIVER_PROTOCOL = 2`.
  Unlocks 250 recorded cases (default fonts at many locations, collections).
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
  lookup flags; the required feature of a language system.
- [ ] GSUB types 3 (with the alternate index) and 8.
- [ ] Script, language and feature selection with browser defaults per
  script and direction.
- [ ] Mapping steps of §6.2 (compose/decompose by cmap, default ignorables,
  space fallbacks, variation selectors via cmap 14, documented `.notdef`).
- [ ] GPOS x/y placement for pair adjustment; legacy `kern` values split as
  HarfBuzz does.
- [ ] Cluster merging to match HarfBuzz (the largest remaining difference
  group: emoji grapheme clusters in AdobeBlank2).
- [ ] Promote curated cases as they pass (`tests/cases/curated.jsonc`
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
