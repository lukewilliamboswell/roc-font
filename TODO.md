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

### Font foundation integration

Implementation branch: `integration/font-foundations`. Feature workers use
isolated worktrees; the integrator owns `Font.roc`, `Face.roc`, package and
test manifests, oracle/benchmark/fuzz registration and final validation.

- [ ] MATH: constants, glyph corrections/attachments, corner kerning,
  extended shapes, variants and construction parts, with licensed real
  fonts and recorded HarfBuzz/fontTools oracles.
- [ ] Text correctness: all GPOS positioning types, including attachment
  propagation and bounded contextual application; script-specific shaping
  and surrounding context where needed for end-to-end multilingual cases.
- [ ] Color glyph facts for emoji: palettes/layers, COLRv1 paints, embedded
  SVG and bitmap formats, with an explicit supported-format matrix and
  real-font public consumers.
- [ ] Ligature caret queries, including point/variation forms and absence.
- [ ] PDF font facts: raw tables, full/PostScript/legacy family names,
  embedding flags, stored metrics and side bearings.
- [ ] TrueType outline output at static and variable locations, including
  composites and implied on-curve points, through a public path consumer.
- [ ] For every feature: public bundle tests, cached reference agreement,
  narrow fuzz/scaling targets, examples, generated API docs and clean
  focused commits; run the full integration checks and allocation ratchet.

Shared internal contracts before feature fan-out:

- New standalone table readers import only package internals and take
  checked table bytes plus the glyph count (and any necessary explicit
  variation inputs). Their offsets in failures are relative to that table;
  `Face` translates them to file offsets and aggregates problems.
- `TableMath` owns math reading/query data. `TableOutline` owns path
  conversion, reusing `TableGlyfPoints`/`TableGvar`; `TableCaret` owns GDEF
  caret reading/query data. Feature agents do not edit `Face` or `Font`.
- GPOS extends `LayoutKerning` with its existing `read_gpos`, `combine`
  and `position` entry points where possible; any necessary signature
  changes are sent to the integrator before consumers are changed.
- Font units, explicit absence, deterministic table order, flat prepared
  data and eager hostile-byte validation apply to every new query.
- Feature agents own only their assigned modules, dedicated test files,
  fixtures, examples and fuzz targets. Shared registry edits are integrated
  centrally; no worker changes another worker's files.

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
2. roc-pdf's strict checks (checksums, directory order, overlapping and
   duplicate tables, composite cycles, `fsType`) in strict reading, and raw
   table access for its subsetting, which stays in roc-pdf
   (`roc-pdf-wt-roc-font-replace`, `development/roc-font-replacement.md`).
   Also from that study: PostScript, full and ID-1 names; stored `head`
   and `hhea` values and left side bearings; ligature origins with lookup
   and input glyphs; a feature-free (kerning-only) shaping switch; a lower
   per-call shaping floor (15-17 allocations however short the text).
3. GPOS single, cursive, mark attachment, contextual positioning.
4. Outlines as a listing; CFF and CFF2.
5. Complex-script shapers (Arabic, Indic, USE, Hangul, Tibetan, Thai)
   with a per-script support matrix; 109 in-house Tibetan cases need
   `abvs`/`blws`, and Thai `sara-am` 52.
6. WOFF/WOFF2 unwrapping outside the core.

## Open questions

1. roc-ray: glyph-id drawing with a host atlas, or code-point drawing?
2. WOFF/WOFF2: a module here or a separate package?
3. Cluster levels beyond `Graphemes` and `Characters`?
4. Which `unicode` version can a paragraph layer pin?
