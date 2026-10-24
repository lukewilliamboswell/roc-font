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

### Default fonts (§5.8, `docs/default-fonts.adoc`)

- [ ] Expose `sans`, `serif`, `mono`, `*_bytes`, `*_licence` after variable
  phases 1 and 2 (two faces default to Light).
- [ ] `all_tests.py`: bundle step accepts exactly the files in
  `tools/default-fonts/pins.json`; run `tools/default-fonts/verify.py`.

### Browser parity (§6)

- [ ] GPOS pair lookups honour lookup flags with the skipping iterator
  (`LayoutGsub.check_glyph_property` and glyph properties are ready).
- [ ] GPOS lookups reached only through FeatureVariations alternates;
  FeatureVariations lookup-variation records (HarfBuzz's 1.1 extension).
- [ ] The driver passes script, language, direction and features (from
  the case, or the oracle's guessed `detail.script`/`direction`): turns
  hundreds of unsupported HarfBuzz cases into measured ones.
- [ ] Restore an in-place fast path for ligature lookups (the adversarial
  100-lookup case went from 7.7x to 10.8x HarfBuzz).
- [ ] Decide the policy for cmap glyph ids past `numGlyphs` (HarfBuzz
  outputs them; roc-font treats them as missing; AOTS cmap4).
- [ ] Tidy: expose `Face.cmap` and a GDEF accessor so `LayoutGsub` stops
  keeping copies.

Exit: HarfBuzz agreement on the Latin, Greek and Cyrillic cases of the
in-house and text-rendering-tests suites, except listed known failures;
Chrome widths agree on package-mermaid's oracle texts.

### Tests and measurement

- [ ] Narrow fuzz targets still to add: gvar extents, LayoutVar kerning
  deltas and FeatureVariations (once wired).
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

### API changes from consumer evidence (before 0.1.0)

- [ ] Report which feature produced each glyph without widening `Run`
  (roc-pdf's `Text.Substitution`, Ligature vs ManyToOne): e.g.
  `shape_traced` returning `origins : List([Mapped, Substituted({ feature }),
  Ligature({ feature, components }), Inserted({ feature })])`.
- [ ] Never return a partial run silently: when a budget stops shaping,
  say so (`shape_checked -> Try(Run, [OverBudget(...)])` or a completeness
  fact), per §6.3 and "never silently clamp".
- [ ] Cluster offsets: `Shaper.decode` clamps at `0xFFFFFFFF`; use `U64`
  for `Run.clusters`, scalar offsets and `Feature.start`/`end`, or define
  and document the bound without clamping.
- [ ] Document the run's guarantees: clusters never decrease in
  left-to-right runs, one cluster's glyphs are adjacent, a missing
  character maps to glyph 0 (with the missing flag).

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
