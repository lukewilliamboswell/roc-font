# Contributing to roc-font

Use issues for bugs and design discussion, and pull requests for changes.
Say what behaviour changes, why, and how you checked it. Report a suspected
vulnerability privately, as [SECURITY.md](SECURITY.md) describes.

The working principles every change keeps (the package boundary, treating
font bytes as hostile, totality, performance by construction, and what a
change must verify) are in [AGENTS.md](AGENTS.md). Read it before your
first change; it applies to people as much as to agents.

## What you need

- **The Roc nightly named in [`.roc-version`](.roc-version).** Download it
  from [roc-lang/nightlies](https://github.com/roc-lang/nightlies/releases)
  and put its `roc` first on `PATH`, or set `ROC` to its path. The checks
  refuse any other release compiler, and warn on a local debug build,
  because formatting and code generation differ between nightlies.
- **Python 3.10 or later.** The check scripts under `scripts/` use the
  standard library only. `zstd` (or Python 3.14) lets the bundle check look
  inside the bundle; without it that step is skipped.
- **Optionally, [Blueprint](https://github.com/lukewilliamboswell/roc-blueprint)
  0.8.0**, to run the named tasks below as CI does, and to render the manual
  with the renderer pinned in `Blueprint.lock`. No Nix is needed.

Oracles (HarfBuzz through uharfbuzz, fontTools, FreeType, Chrome) are
needed only to record new reference results, never to run the checks.

## Run the checks

One command runs everything a pull request must pass:

```sh
blueprint run check            # or: python3 scripts/all_tests.py
```

It runs, in order and reporting each step: the compiler pin, `roc fmt
--check`, `roc check`, the tests on the dev backend and on the interpreter,
a native smoke run of every fuzz target, the replay of recorded oracle
results, the allocation ratchet, a check that `roc docs` shows exactly the
public API, a check that the bundle holds no fonts, tests or fuzz targets,
and `git diff --check`. Select steps with `--only`, drop them with `--skip`
and list them with `--list`:

```sh
blueprint run check -- --only fmt,check,test
python3 scripts/all_tests.py --skip fuzz-smoke
```

The other tasks in `Blueprint.roc`:

| Task | What it runs |
| --- | --- |
| `test` | the compiler pin and the tests, dev backend and interpreter |
| `fuzz-smoke` | `scripts/run_fuzz.py smoke`: build each fuzz target and replay its seeds |
| `conformance` | `scripts/conformance.py`: compare with the recorded oracle results |
| `bench-quick` | `scripts/bench.py --quick`: a timing smoke run against the comparison programs present |
| `docs` | render the manual in `docs/` into `.docs-out/` |
| `examples` | build and run every example in `examples/` against its recorded output (`-- --update` re-records) |

Pull-request CI runs `blueprint run check -- --smoke` with the nightly in
`.roc-version` (`.github/workflows/ci.yml`). `--smoke` keeps CI fast:
fuzz targets run 200 inputs each and the benchmarks run one Roc-only pass,
proving both build and run. The allocation ratchet, the comparison
programs and fuzz campaigns are local: run the full `blueprint run check`
(and `scripts/run_fuzz.py campaign`) before pushing a change to a hot path
or a reading or shaping stage. Dedicated CI jobs for them can be added
when there is a need.

## Where things live

| Path | Contents |
| --- | --- |
| `package/` | the package; `package/main.roc` is what ships |
| `package/*Tests.roc` | tests of internal modules, for what the public API cannot observe |
| `tests/api/` | tests of the public API, importing `package/main.roc` as a consumer does |
| `tests/support/` | test-only font builders, never reached from `package/main.roc` |
| `tests/fonts/`, `tests/cases/` | test fonts with their licences, conformance cases and fixtures |
| `tests/oracle/records/` | recorded reference results that `roc test` and the review replay |
| `fuzz/` | roc-fuzz targets, seeds and dictionaries |
| `bench/` | benchmarks, the allocation baseline and comparison programs |
| `tools/` | the conformance driver, oracle tooling and default-font pins |
| `scripts/` | the check, fuzz, benchmark and conformance entry points |
| `docs/` | the manual |

Test modules and test fonts never enter the package's import graph, so
`roc bundle` leaves them out.

## Deeper guides

Each kind of test has a chapter in the manual:

- [docs/conformance.adoc](docs/conformance.adoc): cases, the driver,
  recording oracle results, gating and known failures.
- [docs/fuzzing.adoc](docs/fuzzing.adoc): each target's contract, running
  longer, and turning a crash into a permanent `## fuzz regression:` expect.
- [docs/benchmarks.adoc](docs/benchmarks.adoc): the timing comparison and
  the allocation ratchet, and when to update the baseline.
- [docs/default-fonts.adoc](docs/default-fonts.adoc): the shipped fonts,
  their licences, provenance and how to verify them.
- [docs/variable-fonts.adoc](docs/variable-fonts.adoc): variable-font
  scope, numerics and testing plan.
- [docs/architecture.adoc](docs/architecture.adoc): the design and the
  reasons behind it, cited as "architecture §N".

## Documentation

`roc docs package/main.roc` is the API reference and the authority for
public names; the checks fail when it shows an internal helper. The manual
is AsciiDoc under `docs/`, with `docs/index.adoc` as its entry point; render
it with `blueprint run docs`. It is built by roc-automation's shared
renderer, which accepts a subset of AsciiDoc and rejects the rest: link
between chapters with `xref:chapter.adoc#section-id[text]`, give tables a
header row and explicit `cols`, and avoid escaped `\|` separators in cells.

Each release has notes in `docs/releases/<version>.adoc`, written for a
user deciding whether to upgrade, and included from `docs/releases.adoc`.
Write `{package-url}` where the bundle URL goes; the release workflow fills
it in.

## Changing the compiler pin

Move `.roc-version` to a newer nightly in its own pull request. Expect
formatting and allocation counts to change: run `roc fmt` on every
directory the checks format, record new counts with
`python3 scripts/bench.py --check --update-baseline` and explain the
change, and review the compiler notes below.

## Compiler notes (nightly-2026-10-23)

- Booleans are `True`/`False`. Nested defaulted records work.
- Avoid until fixed on the nightly: wrapping a record field in a tag and
  reading the record again (`Tag(v.value)` then `v.value.id`) segfaults the
  ARC pass; `Dict(k, {})` hangs native builds.
- The nightly reports type errors inside basic-cli 0.23.0/0.25.0 yet
  builds; the scripts tolerate only problems inside the cached platform.
- The pre-nightly debug `roc` on `PATH` panics on this code; use
  `.roc-version`'s nightly (`ROC=...`).
