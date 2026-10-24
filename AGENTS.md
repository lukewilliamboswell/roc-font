# Working Principles

This package reads font files and turns text into positioned glyphs, in pure
Roc. Preserve these principles when designing APIs, implementing tables and
shaping, writing documentation, or adding tests. The architecture these
principles produce, and why, is in `docs/architecture.adoc`; current status
and plans live in `TODO.md`, not here.

## Keep the boundary at the font

- Accept font bytes and the facts needed to shape text: the text, and later
  script, language, direction and feature choices.
- Return font facts (metrics, character maps, glyph extents, outlines),
  glyph runs (ids, advances, offsets, clusters) and useful structural
  results.
- Do not add rendering, rasterisation, hinting emulation, pixel rounding,
  line wrapping, font fallback policy, font discovery, file I/O or UI
  concerns. These belong to consumers.
- The package ships exactly three default fonts (sans, serif, mono),
  unmodified, freely licensed, with their licence text, prepared at
  compile time so a bad file is a build error. Any other font is the
  caller's bytes. Test fonts live under `tests/fonts/` with their
  licences, and only test modules and fuzz apps import them.
- Leave Unicode text segmentation (graphemes, line breaks, bidi, script
  runs) to the `unicode` package. Consume its results; do not duplicate
  its tables. The character properties shaping itself applies
  (normalisation, mirroring, mark classes, grapheme extension for
  clusters) are embedded, generated from pinned Unicode data in
  `tools/ucd/` at the version the reference shaper uses.

## Design from the caller's meaning

- Put data only where it is meaningful. Do not add fields that most callers
  silently ignore.
- Prefer a type that makes an invalid structure impossible over code that
  accepts a weaker structure and checks it later.
- Keep font data in font units at the boundary. Every consumer scales and
  rounds differently.
- Nominal types get equality only by opting in. Derive `is_eq` for public
  values callers compare, such as problem lists; do not derive it for an
  opaque prepared font, and match on a result in tests instead.
- Keep input and output index-aligned. Glyph results follow glyph input
  order; clusters point back into the caller's text.

## Treat bytes as hostile

- Font bytes are untrusted input. Every offset, count and length is checked
  against the data before use, and before any allocation sized by it.
- Reading is the only source of failure. A successfully read font proves
  that every later query and every shaping call is total.
- Lenient reading (the default) drops a broken optional table and reports
  it on the successfully read font; strict reading rejects the font. A
  broken required table always rejects it. Dropping is not repair: a
  table is used as the font defines it or not at all.
- Report all independent problems found in one result.
- Never silently clamp invalid values, repair references, or substitute
  index zero for missing data. Where the format itself defines a fallback
  (such as a glyph past the long metrics taking the last advance), follow
  the format and document it.
- Name what was wrong in terms a caller can act on: the table, and where it
  helps, the offset.

## Separate preparation from use when it earns its cost

- Reading a font (checking and parsing its tables) is preparation; queries
  and shaping are use. Parse once, query and shape many times.
- Prepared work belongs to one exact font file. Any change to the bytes
  requires reading again.
- Inputs that only select a particular result (text, features, positions)
  belong to the query, not to reading.
- Precompute only work that is valid to reuse. Measure before moving work
  into or out of reading.

## Use plain language publicly

- Public names describe what callers provide or accomplish.
- Do not require callers to know OpenType internals to use the default path.
  Terms such as lookup, coverage, class definition and extension stay
  internal unless public documentation explains why they matter.
- Use one term for one concept. In particular, keep units, glyph indices,
  clusters, direction and features consistent across modules.
- Prefer the shortest API that remains unambiguous in generated Roc docs.
- The default call needs no options and behaves like a browser. Every
  option is a defaulted field of a nominal options record
  (`ReadOptions := { strict : Bool ?? False }`, built with
  `ReadOptions.{}`), so adding an option never breaks a caller.

## Respect the module boundary the compiler enforces

- Only a module's namesake type is visible to importers. Every public
  surface is reached through associated items or delegations on the
  namesake.
- Keep public modules small. Table readers and shaping internals must not
  leak into generated API docs.
- Test what you fly: public-behaviour tests (`tests/api/`), fuzz targets,
  the conformance harness and benchmarks import the package through
  `package/main.roc`, exactly what ships, and use only the public API. The
  test-only byte builders live in their own package, `tests/support/`
  (`FontBuild`), which imports nothing from roc-font. `package/main.roc`
  never reaches either, so `roc bundle` leaves them and the test fonts
  out. In-package `package/*Tests.roc` modules are only for what the
  public API cannot observe, and use inline bytes or committed fixtures,
  never the builders.

## Keep internals precise and composable

- Use the specification's names internally (lookup types, formats, table
  tags) even when the public API uses simpler words.
- Express reading and shaping as pure phases with explicit inputs and
  outputs so they can be tested and reused independently.
- Design hot data around flat, deterministic, index-addressed structures.

## Protect performance by construction

Roc ownership, builtin implementations and stack use can change the
observed cost of an algorithm. In hot paths:

- Prefer flat parallel lists, offset tables and index-addressed arrays over
  nested growing lists. Replacing one inner list in `List(List(a))` can copy
  the outer list.
- Reading an element of a list whose items hold lists (tag payloads or
  records with list fields) increments and decrements every inner list on
  each access. In hot prepared data, use scalar records holding spans into
  flat pools. This was the dominant cost of the seed's shaper (about 60 % of
  its time), ahead of allocation.
- Preallocate index-aligned output when its final length is known.
- Treat the fallback of `List.set` as part of ownership design. When
  validation proves an index is in bounds, use an unreachable fallback that
  does not retain the old list, conventionally `?? []`, and state the
  invariant. Never use it when failure is actually possible.
- Do not assume a list threaded through a record-valued `fold` stays unique.
  A local `var`/`for` loop often expresses ownership more reliably.
- Use explicit work lists, not recursion, for nested lookups, composite
  glyphs and other deep structures. Bound the depth.
- Know the cost of builtins on the current nightly. `List.sort_with` picks
  the first item as its pivot, so sorted and equal-key inputs can be
  quadratic. Fonts store most arrays sorted; check order linearly instead of
  sorting when the format requires order.
- Bound every loop over font data by a count the data was checked against,
  and bound shaping work (run growth, nested lookup applications, call
  depth) by documented budgets.
- Use deterministic structures. Hash iteration order must not influence
  results.

When changing a hot path, start from a native optimised benchmark with at
least three increasing sizes, compare elapsed time, allocation calls,
requested bytes and peak live bytes separately, and test adversarial fonts
(huge coverage tables, deep contextual nesting, long ligature sets, many
lookups) as well as large ordinary ones.

Allocation figures are deterministic, so they ratchet in
`bench/baseline.json`: an increase fails, and a decrease must be recorded
with an explicit baseline update in the same change. Elapsed time is
judged as a ratio against the reference implementations measured in the
same run, never as an absolute number.

Shaping budgets follow HarfBuzz's (output at most `max(64 n, 16384)`
glyphs, at most `max(1024 n, 16384)` lookup applications) so that a budget
never changes a result on a legitimate font.

## Preserve totality, determinism and numerical safety

- Every well-typed call on a successfully read font has a defined result,
  including empty text, missing glyphs, glyph indices past the font and
  empty tables.
- Iterative work has a hard bound as well as any natural termination.
- Finite accepted input produces finite output. No NaN or infinity escapes.
- Identical package version, font bytes and arguments produce the same
  bits. Iterate deterministically; use table order and source indices as
  tie-breakers.
- Return work already computed, such as clusters, instead of making callers
  recompute it.

## Treat documentation as the API

- `roc docs` is the authority for what public users can discover.
- Public module documentation is self-contained. Do not refer to local
  design files, issue trackers or plans.
- Lead with when to use an operation and what it gives. Put OpenType
  terminology after the plain-language explanation.
- Keep TODOs and plans out of public module comments.
- Keep the README user-facing: purpose, status, a minimal example, setup
  and licence.
- Examples use the real public API.

## Verify the contract, not only the numbers

`python3 scripts/all_tests.py` runs these checks with the compiler named in
`.roc-version`. CI runs it with `--smoke` (fuzzing and benchmarks only
build and run briefly); the allocation ratchet and fuzz campaigns are
local, so run the full script before pushing hot-path or stage changes. For a public API change or a new table, lookup type or
shaping stage:

- format every changed Roc file (`roc fmt --check package/`);
- run `roc check package/main.roc` and the tests, with the default backend
  and `--opt=interpreter`;
- build and run at least one NATIVE binary exercising the changed path; the
  interpreter and native backend can disagree;
- give every new reading or shaping stage a fuzz target asserting its
  contract (totality, determinism, bounded growth, index alignment, finite
  output), seed it with real fonts, and distil every corpus crash into a
  permanent `## fuzz regression:` expect;
- besides whole-pipeline targets, give each hot feature (a cmap format, a
  coverage or class table, one lookup type, kerning, a variation store) a
  narrow target that measures allocations at two or more generated sizes
  of just that feature, so a scaling or performance problem is pinned to
  the feature that causes it rather than found later in an end-to-end
  number;
- check agreement with a reference implementation (HarfBuzz, fontTools,
  FreeType, OTS, a pinned browser) through cached oracle records, replayed
  by the native conformance driver, so agreement is enforced without the
  oracle installed; cases are JSONC data run by the Python driver through
  the Roc harness, never generated `.roc` files; list every deliberate
  divergence with its reason;
- test aggregated problems, truncated and corrupted files, and empty and
  degenerate inputs;
- generate `roc docs` and confirm internal helpers do not appear;
- bundle the package and confirm it contains only the default fonts (with
  licences) and no test fonts or test modules; and
- run `git diff --check`.

If a check cannot run, run the others and report which were skipped and why.

## Parallel work

- Partition by strict file ownership: each worker modifies only its files.
- `roc test package/Foo.roc` compiles only that file's import closure, so it
  is the isolation boundary between workers.
- Land shared contracts (types, module APIs) before fanning out consumers;
  the integrator alone edits shared manifests.

## Evolve from evidence

- Keep APIs provisional until a consumer proves them end to end.
- Let consumers, oracles and generated documentation correct the design.
- When evidence changes a principle, update this file in the same change.
- Preserve enduring constraints here; keep status and task lists in
  `TODO.md`.
