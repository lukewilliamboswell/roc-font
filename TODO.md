# roc-font: status and plan to 0.1.0

The working plan for the user and future agents. The design and its reasons
are in `docs/architecture.adoc` (cited as "architecture §N"); enduring rules
are in `AGENTS.md`; where the seed came from is in `SEEDED_FROM.md`. This
file holds status, milestones, tasks and open questions only. Paths to other
repositories are relative to `~/Documents/Github/`.

## 1. Status

The package is a faithful extraction of package-mermaid's font code
(`SEEDED_FROM.md`): `package/Font.roc` (reading, metrics, cmap, kerning) and
`package/FontShape.roc` (default GSUB), with unit tests in
`package/FontTests.roc` and `package/FontShapeTests.roc`, a synthetic font
builder in `package/FontTest.roc`, and two fuzz targets in `package/`.
`package/main.roc` exposes only `Font`. Public entry point today:
`Font.from_bytes : List(U8) -> Try(Font, List(Problem))`.

None of the verification, benchmark or corpus tooling of architecture §7
and §9 exists yet. It is being scaffolded under `tools/`, `tests/`,
`bench/`, `fuzz/` and `scripts/`.

## 2. Gap analysis: seed against architecture

| Area | Seed today | Architecture | Ref |
|---|---|---|---|
| Container | `sfnt` (`0x00010000`, `true`, `OTTO`); `ttcf` rejected as `NotAFont` | `sfnt` and `ttcf`, face chosen by `ReadOptions.face`, face count reported | §4.1 |
| Validation model | every table parsed eagerly into nested lists (`List(List(Subtable))`, `List(List(Item))`) | validate eagerly, keep checked table bytes, read in place; indexes only where a benchmark justifies them | §4.2, §4.3 |
| Strict / lenient | one mode: any bad table, optional or not, rejects the font | lenient default (drop broken optional tables, report in `Font.dropped`); strict option incl. checksums and overlapping or unordered tables | §4.4 |
| Problems | `[NotAFont, MissingTable(Str), BadTable(Str), BadUnitsPerEm, NoUnicodeMapping]`, no offsets | every independent problem, naming table and offset | §4.4, AGENTS.md |
| Limits | none in reading; shaping hard-codes its budgets | `ReadOptions.limits` (file size, faces, glyphs, lookups, composite depth) | §4.5 |
| Units and ids | `F64` metrics and advances; `U64` glyph ids | `I32` font units, `U32` glyph ids, no floating point | §3, §5.2 |
| Vertical metrics | ascent and descent chosen browser-style from `hhea` and OS/2 typo/win, honouring `USE_TYPO_METRICS` | the same, plus line gap, cap height, x height exposed | §2 |
| Underline / strikeout | not read | `post` underline and OS/2 strikeout position and thickness | §2 |
| `name` | not read | name records as a listing | §5.6 |
| `post` | not read | italic angle, underline, fixed pitch; glyph names later | §2 |
| cmap | formats 4 and 12 flattened into ranges | formats 4, 12, 14 and the rest (0, 6, 10, 13); variation sequences | §6.1, §6.2 |
| GSUB | lookup types 1, 2, 4, 5, 6 and extension 7; 3 and 8 skipped; lookup flags and mark filtering ignored; fixed feature list for `latn`/`DFLT` | all types, lookup flags, `GDEF` classes and mark filtering sets, script/language/feature selection | §6.1 |
| `GDEF` | not read | glyph classes, mark attachment classes, mark filtering sets | §6.1 |
| GPOS | type 2 pair adjustment (formats 1 and 2, extension), x advance only | full GPOS in time; x/y advances and offsets in the run | §5.4, §6.1 |
| `kern` | fallback when no GPOS kerning | same | §6.1 |
| Mapping steps | cmap only; no composition, ignorables, space fallback or variation selectors | browser-parity mapping | §6.2 |
| Budgets | output `4n+32`, ops `64n+16384`, nested depth 8 | output `max(64n,16384)`, ops `max(1024n,16384)`, depth 64, in `ShapeLimits` | §6.3 |
| Shaping plan | feature lookups chosen once at read time (`active`) | `ShapePlan` from `Font.plan(font, options)`, reusable | §5.5 |
| Shaped result | separate calls: `substitute` (glyph+cluster), `advance`, `kerning` (`List(F64)`) | one `Run` of flat lists: glyphs, advances, offsets, UTF-8 byte clusters, flags | §5.4 |
| Text input | caller maps code points and builds items | `Str` with UTF-8 byte clusters; lower-level scalar entry point | §5.2 |
| Script / language | fixed | ISO 15924 / BCP 47, mapped internally; raw tags as an expert option | §5.2 |
| Listings | none | `Iter` for code points, names, scripts and features, outline commands | §5.6 |
| Outlines | horizontal extents (`ink`) only | glyf, then CFF/CFF2, as listings | §1.1 |
| Subsetting | none (roc-pdf has one) | later | §1.1 |
| Variations | none | location as a query input, later | §5.7 |
| Docs surface | `roc docs` lists about 50 internal readers as items of `Font` (`read_head`, `u16`, `fits`, `pair_in_sets`, `kern_pairs`, ...) and internal types `Table`, `Runs`, `Subtable` | only public namesakes; readers in unexposed `Sfnt`, `Table*`, `Layout*`, `Shaper*` modules | §5.1 |
| Fuzz targets | `fuzz/font-read.roc`, `fuzz/font-shape.roc` via `package/testing.roc` (shape asserts the old `4n+32` bound) | one target per stage, differential target | §7.3, §10 |

## 3. Decided (see the architecture, do not reopen without evidence)

- Integer font units: `I32` lengths, table-native `U16`/`I16` only on raw
  queries; no `F64` anywhere in reading or shaping (§3, §5.2).
- `U32` glyph ids (§5.2).
- Lenient reading by default, `strict` option, `Font.dropped` reports
  dropped optional tables (§4.4).
- Shaping budgets follow HarfBuzz: output `max(64n,16384)`, lookup
  applications `max(1024n,16384)`, nested depth 64. The seed's `4n+32`
  budget is replaced (§6.3).
- Options are nominal records with defaulted fields,
  `Opts := { field : T ?? default }`, constructed as `Opts.{}` (§5.3).
- `ttcf` collections are in scope from the start (§4.1).
- Validate eagerly, then read in place from checked bytes; indexes only
  where measured (§4.2, §4.3).
- `Iter` only for listings; `List` where callers want everything (§5.6).
- Reusable `ShapePlan` (§5.5).
- Browser-parity mapping steps are on the default path (§6.2).
- Text is `Str`, clusters are UTF-8 byte offsets; a lower-level entry takes
  scalars with byte offsets (§5.2).
- Script and language as ISO 15924 and BCP 47 (§5.2).
- Variation coordinates are query inputs, not part of the font (§5.7).
- Conformance cases in HarfBuzz test format, results in `hb-shape`
  notation, cached records keyed by SHA-256 (§7.1).
- Allocation ratchet in `bench/baseline.json`; time compared as a ratio
  against reference implementations (§9.2).

## 4. Consumers and what each needs

**package-mermaid** (branch `feature/package-mermaid` of
`roc-graph-layout`, worktree `roc-graph-layout/.claude/worktrees/package-mermaid/`),
the first consumer. The seed is its code. `TextMeasure.roc` stays there:
Chrome rounding, fallback widths, Mermaid's line and word rules. It needs
cmap, advances, glyph extents ("ink"), ascent/descent, default GSUB and pair
kerning. It proves the extraction changed nothing: its Mermaid oracle suite
(`tests/mermaid/`, `OracleSizes.roc`, `tools/mermaid-oracle/`) must pass
unchanged after it switches to roc-font.

**roc-pdf** (`roc-pdf/package/`), the strongest second consumer.
- Today built-in shaping is cmap to hmtx one-to-one for Latin and Han
  (`KernelShape.roc`, `KernelFacadeShape.roc`), with no kerning, no GPOS
  and no GSUB application (`KernelGsub.roc` only validates one declared
  ligature).
- Near term: kerning and default ligatures for Latin in the built-in path,
  and roc-font as an in-Roc producer for its advanced shaped-run path
  (`Text.roc` `Store`/`Run`/`Cluster`/`Glyph`, with `ClusterKind`,
  per-feature substitutions and `ShapeKey`). It wants optional
  per-substitution feature tags for its `Substitution.feature`.
- Later: merge its stricter reader into roc-font's strict mode
  (`KernelFont.roc`: checksums, duplicate/unordered/overlapping tables,
  composite cycles and depth, `name`, OS/2 CapHeight and `fsType`, caller
  `Limits`, `Work` counters) and its subsetting (`KernelFontSubset.roc`,
  `KernelFontPlan.roc`).
- Constraints: pins exact allocation counts and work counters per case
  (`roc-pdf/AGENTS.md`), `U32` glyph ids, a first error with rich payloads,
  text keyed by UTF-8 byte ranges.

**roc-ray** (`roc-ray/platform/Font.roc`, `Text.roc`) and **terrocotta**
(`terrocotta/package/Text.roc`, `Render.roc`).
- First: pure measurement with kerning from the same bytes the host loads,
  plus the list of code points a cmap maps, for raylib's atlas (today it
  rasterises only ASCII). terrocotta's `MeasureTextFn` then wraps it.
- Later: glyph-id drawing, which needs a host atlas keyed by glyph id and a
  "draw glyph run" command.
- Host raster metrics differ slightly from unhinted font units, so roc-ray's
  parity check needs a tolerance.

**unicode** (`unicode/`): supplies segmentation, bidi and script
itemisation. Its `design.md` (around l.656-667) leaves OpenType and shaping
to "a text engine that consumes this package"; roc-font is that engine's
font half and takes scalars with byte offsets so the core does not depend
on it.

**Should not use it:** roc-gui and roc-signals (the GPUI host shapes with
`font-kit`), roc-ansi (terminal width is a Unicode question), roc-wasm4
(fixed bitmap font).

## 5. Milestones to 0.1.0

Foundations first, so every refactor after milestone 1 is measured against
a recorded baseline and checked against recorded oracle results.

### M0. Faithful extraction (done)

- [x] Seed from package-mermaid at `3eccac6` (`SEEDED_FROM.md`).
- [ ] Re-sync if package-mermaid's font files change before M2 (procedure
  in `SEEDED_FROM.md`); after M2 the code has diverged and fixes are
  ported by hand.

### M1. Harness foundations (before any refactor)

Conformance (§7.1, §7.2):
- [ ] `tests/corpus.json` and `scripts/fetch_corpus.py`: pinned URL at a
  release tag, SHA-256 and licence per font; fail on mismatch.
- [ ] `tools/oracle/requirements.txt` with exact versions and hashes
  (`fonttools==4.61.1`, `uharfbuzz`, `freetype-py`), run from a `.venv`
  with `python3 -I`; each record's provenance holds the tool versions and
  the run fails when they differ from the pin.
- [ ] `scripts/record_oracle.py`: records keyed by SHA-256 of font bytes,
  case, options, tool versions and extractor version; forced re-record is
  byte-identical.
- [ ] `tools/driver/`: native Roc binary, cases in, `hb-shape` notation
  out, each font read once.
- [ ] `scripts/conformance.py` and `tests/known-failures.json` (fails on
  new differences and on stale entries; never edits the list).
- [ ] Generator for a small slice of records as Roc expect modules.
- [ ] Unhappy-path cases: OTS accept / reject / drop-table expectations.

Benchmarks (§9):
- [ ] Protocol: each program prints one JSON line (`iterations`,
  `elapsed_ns`, `successes`, `checksum`); `scripts/bench.py` calibrates,
  warms up, runs batches in fresh processes, reports median, spread,
  throughput, peak RSS.
- [ ] Roc programs in `bench/roc/` for the first cases (section 6).
- [ ] `bench/baseline.json` allocation ratchet (allocation calls, requested
  bytes, peak live bytes per case, compiler version recorded) with an
  explicit update command.
- [ ] `bench/compare/`: HarfBuzz (C, system 8.3.0 or pinned), ttf-parser and
  rustybuzz (Rust, `Cargo.lock`), fontTools (reading only).

Fuzzing and checks (§7.3):
- [x] Move fuzz targets to `fuzz/` with seeds and dictionaries;
  `scripts/run_fuzz.py`.
- [ ] Seed both targets from the corpus.
- [ ] `scripts/all_tests` running format, `roc check`, every test module
  with the default backend and `--opt=interpreter`, native fuzz smoke runs,
  conformance and the allocation ratchet. (`roc test package/main.roc`
  runs nothing because tests live in test-only modules.)

Exit: `scripts/all_tests` passes on a clean checkout with the corpus
fetched; conformance runs the HarfBuzz in-house, AOTS and
text-rendering-tests cases on the seed and the agreeing count and every
known failure are recorded; an allocation baseline exists for every bench
case in section 6; both fuzz targets run natively from corpus seeds.

### M2. Internal module split and docs surface

- [ ] Move table readers to unexposed modules named after the
  specification (`Sfnt`, `Table*`, `Layout*`, `Shaper*`; §5.1).
- [ ] `roc docs` lists only public items; record the before and after item
  count.
- [ ] Split fuzz and unit tests to match the new modules.
- [ ] No behaviour change.

Exit: conformance results and allocation baseline unchanged; `roc docs`
shows no internal helper or type; bundle contains no test modules or fonts.

### M3. API to the architecture

- [ ] `ReadOptions` and `ShapeOptions` nominal records with defaulted fields
  (§5.3); `Limits` and `ShapeLimits`.
- [ ] Integer units and `U32` glyph ids throughout; remove `F64`.
- [ ] `ttcf` collections and face count (§4.1).
- [ ] Lenient and strict reading, `Font.dropped`; problems name table and
  offset (§4.4).
- [ ] Representation: flatten `List(List(...))` in kerning and GSUB data
  and move to reading in place from checked bytes where the benchmark
  agrees (§4.2, §4.3). Each index keeps a comment naming its benchmark.
- [ ] `ShapePlan` and `Font.plan` (§5.5).
- [ ] `Font.shape` returning `Run` with UTF-8 byte clusters and
  unsafe-to-break flags; scalar entry point; HarfBuzz budgets in
  `ShapeLimits` (§5.4, §6.3). Update `fuzz/font-shape.roc`'s growth bound.
- [ ] Metrics: line gap, cap height, x height, underline and strikeout;
  `name` and `post` readers.
- [ ] `Iter` listing of mapped code points (roc-ray), after a native
  benchmark against a `List` query (§5.6).

Exit: every M1 conformance case that agreed still agrees; allocation
baseline moves only downward or with a reviewed reason; fuzz targets for
reading, planning and shaping pass seeded native runs; `roc docs` reviewed.

### M4. Browser parity and GSUB flags

- [ ] cmap formats 0, 6, 10, 13 and 14.
- [ ] `GDEF` glyph classes, mark attachment classes, mark filtering sets;
  GSUB lookup flags.
- [ ] GSUB types 3 (with the `aalt`/`salt` value) and 8.
- [ ] Script, language and feature selection with browser defaults per
  script and direction.
- [ ] Mapping steps of §6.2: compose/decompose by cmap, default ignorables,
  space fallbacks, variation selectors, documented `.notdef` result.
- [ ] GPOS x/y placement in the run for pair adjustment.

Exit: HarfBuzz agreement on all Latin, Greek and Cyrillic cases in the
in-house and text-rendering-tests suites, except listed known failures
each with a reason; Chrome widths agree on package-mermaid's oracle texts.

### M5. package-mermaid switchover

- [ ] package-mermaid depends on roc-font and deletes its local copy.
- [ ] Its Mermaid oracle suite passes unchanged.

Exit: zero changes to recorded Mermaid oracle results.

### M6. roc-pdf Latin prototype

- [ ] Kerning and ligatures in `KernelFacadeShape`.
- [ ] A `Text.Store` producer from `Run`.
- [ ] Work under roc-pdf's exact allocation and work-count regime.

Exit: roc-pdf's tests pass with pinned allocation counts; public names
settled with roc-pdf's feedback.

### M7. Release 0.1.0

- [ ] All checks from `AGENTS.md` ("Verify the contract"), interpreter and
  native.
- [ ] `roc docs` reviewed as the API.
- [ ] Bundle contains no fonts, tests, tools or benches.
- [ ] README example compiles against the released API.

Exit: tagged release; checks pass; `git diff --check` clean.

### After 0.1.0, by tier

1. roc-ray measurement and terrocotta's measurer; glyph extents via FreeType
   agreement.
2. Merge roc-pdf's strict checks (checksums, overlap, composite cycles,
   `fsType`, work counters) and subsetting.
3. GPOS single, cursive, mark-to-base/ligature/mark, contextual.
4. glyf outlines as a listing, then CFF and CFF2.
5. Complex-script shapers (Arabic, Indic, USE, Hangul) with a published
   per-script support matrix.
6. Variable fonts: `fvar`, `avar`, `HVAR`, `MVAR`, `gvar`; `Location` on
   queries.
7. WOFF/WOFF2 unwrapping outside the core (roc-deflate, later Brotli).

## 6. Performance (standing requirement, §9)

Every hot-path change is benchmarked natively at three or more sizes and
the allocation ratchet holds. First cases to record in M1:

- read Inter (`tests/fonts/Inter-Regular-metrics.ttf`), a full Inter, a
  large CJK font and a collection;
- cmap lookups: ASCII, BMP spread, supplementary planes;
- advance and extent queries over all glyphs;
- shape Latin text at 3 or more sizes (about 10, 1k, 100k bytes) with
  default features, and with kerning only;
- adversarial fonts: huge coverage tables, deep contextual nesting, long
  ligature sets, many lookups, maximal `kern` pairs.

Comparisons per operation: HarfBuzz (C), rustybuzz and ttf-parser (Rust),
fontTools for reading only.

**First baseline (2026-10-24, nightly-2026-10-23-18478ff, loaded machine,
indicative only).** `scripts/bench.py` and `bench/baseline.json` (34 cases,
allocations, 0 leaks) are in place. Geometric means of roc-font time against
each library:

| Operation | HarfBuzz | rustybuzz | ttf-parser | fontTools |
|---|---|---|---|---|
| read | 65x slower | 113x slower | 1077x slower | 248x faster |
| cmap | 1.9x faster | – | 6.8x faster | – |
| advance | 4.5x faster | – | 1.4x faster | – |
| shape | 6.9x slower | 1.9x slower | – | – |

**First conformance run (2026-10-24).** 42 seed cases: 36 agree, 5 known,
1 unsupported, 0 fail (native and interpreter). HarfBuzz 14.6.0's suites
imported locally (6203 cases; not committed, regenerate with
`scripts/fetch_corpus.py import-hb-tests`): 83 agree, 1267 unsupported,
4708 differ.

Conformance findings to act on:
- 3861 of the 4708 differences come from 7 fonts using cmap formats 0, 6,
  10, 13 or a (3,0) symbol cmap, which the reader rejects with
  `NoUnicodeMapping`. Supporting them (M4) is the cheapest large win.
- Known: soft hyphen and ZWJ not hidden (§6.2); legacy `kern` values are
  split across the pair by HarfBuzz; OTS drops an unsorted `kern` table
  that roc-font accepts (needs lenient reading, §4.4); OTS rejects the
  Inter subset for lacking `name` (deliberate).
- Build the scored-suite mode (§7.1): per-suite agree counts that ratchet,
  so the imported HarfBuzz suites track progress without gating.
- Build the generator from a slice of records to Roc expect modules.
- Add a FreeType case kind (extents) and a Chrome oracle; OTS is pinned for
  Linux x86-64 only.

Performance findings to act on:
- Reading allocates about once per cmap group or ligature (30k allocations
  for 30k format-12 groups; 69k for 52k ligatures; 5.4k for Inter). Flat,
  preallocated arrays (or reading in place, §4.2) are the M3 fix.
- Shaping Inter takes 24 / 121 / 740 allocations at 0.5 / 4 / 32 KiB; the
  ligature-heavy font 234 / 1146 / 8446. Linear, but the constant is worth
  cutting.
- `corpus-hb-in-house-trak` shape checksum differs from HarfBuzz and
  rustybuzz (both agree): probably AAT `trak`. Decide whether `trak` is in
  scope or a listed known divergence.
- Record time ratios on an idle machine (`bench.py --update-baseline`
  full run); they are left out of the committed baseline for now.
- Add requested-bytes and peak-live counters to the roc-fuzz host, then
  ratchet them.
- The nightly reports type errors inside basic-cli 0.23.0 yet builds;
  `conformance.py` tolerates only problems inside the cached platform.
- The local debug compiler panics building `bench/roc/alloc.roc` with
  `--fuzz` (`ARC: ... use of dead refcounted local`); check against the
  nightly and report upstream if it reproduces.

## 7. Corpus seeding tasks

- [ ] HarfBuzz `test/shape/data`: in-house, `aots`, `text-rendering-tests`
  (fonts and expectations).
- [ ] HarfBuzz `test/fuzzing/fonts` (malformed).
- [ ] OTS test fonts (malformed, accept/reject/drop expectations).
- [ ] fontTools test data.
- [ ] Google Fonts: Inter (glyf, rich GSUB/GPOS), Source Sans 3 (CFF), a
  variable font (Inter or Roboto Flex).
- [ ] Noto: Sans and Serif (Latin, Greek, Cyrillic), Arabic and Devanagari
  (marks, cursive), a CJK or emoji font with cmap format 12, a `.ttc`.
- [ ] A font with only a `kern` table; crafted fixtures for edge cases.

## 8. Oracles on this machine (2026-10-24)

| Oracle | Available |
|---|---|
| HarfBuzz | `libharfbuzz` 8.3.0 with headers and GObject bindings (`gi.repository.HarfBuzz`); no `hb-shape`/`hb-view`; no `uharfbuzz` |
| fontTools | 4.61.1 in user site-packages (`~/.local`), so not visible under `python3 -I` |
| FreeType | `libfreetype` 2.13.2 (pkg-config 26.1.20) with headers; no Python binding |
| OTS | not installed (`ots-sanitize` missing) |
| Chrome | package-mermaid's oracle pins Puppeteer 25.16.0 and its Chrome; system Chrome 153 |
| Rust | `cargo` 1.95.0 (for ttf-parser and rustybuzz comparisons) |

No HarfBuzz, rustybuzz, ttf-parser, fontTools or OTS source checkouts sit
in `~/Documents/Github/`; the corpus fetch pins their release archives.

## 9. Open questions

1. Can roc-pdf accept aggregated problems instead of a first error? How
   detailed must payloads be (table tag, offset; tags as `U32` or `Str`)?
   Does it need `Work` counters in the public result?
2. Exact public names: `from_bytes`, `ReadOptions`, `ShapeOptions`,
   `plan`, `shape`, `dropped`, the measurement helper (`width`?), the
   default-script value.
3. Is `Run` its own public module, or a record alias in `Font` (§5.1)?
4. Does `FontShape` disappear into internal modules, or stay public?
5. Script default: decided (§5.3). Unknown script uses the font's default
   script and language system; roc-font never detects scripts. Remaining:
   confirm with package-mermaid that this matches Chrome for its labels.
6. Subsetting: in roc-font or kept in roc-pdf on raw table access?
7. roc-ray: is glyph-id drawing worth a new host atlas, or is measurement
   with code-point drawing enough?
8. WOFF/WOFF2: separate module in this repository or a separate package?
9. Cluster levels: `ShapeOptions.clusters` exists (§5.3); which HarfBuzz
   levels to offer, and confirm the grapheme default with roc-pdf.
10. Which `unicode` version a paragraph layer can pin, given roc-ray's
    nightly warnings.

## 10. Notes on the current nightly

- Booleans are `True` and `False` (`Bool.true` does not exist). Nested
  defaulted records (`limits : Limits ?? Limits.{}`) compile and work.

- Known bugs (fixed on main, avoid until the nightly catches up): wrapping
  a record field in a tag and then reading the record again
  (`Tag(v.value)` then `v.value.id`) segfaults the arc pass; `Dict(k, {})`
  hangs native builds.
- Defaulted record fields (`?? default`) are supported; nested defaulted
  records had an issue (`roc/test/cli/issue_11946_nested_defaults/`).
  Check the nightly before `ReadOptions.limits : Limits ?? Limits.{}`.
- `List.sort_with` takes the first item as pivot (quadratic on sorted
  input); see `AGENTS.md`.
