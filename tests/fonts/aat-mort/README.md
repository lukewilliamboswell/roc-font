# Legacy Apple morphing evidence

These are original UPL fonts; see LICENSE. `generate.py --check` reproduces
their bytes and JSONC cases with fontTools4.61.1. They isolate all five `mort`
types: rearrangement, contextual substitution, ligature substitution,
noncontextual substitution and insertion. Additional fonts exercise signed
contextual offsets, zero-as-missing substitutions, and multiple ligature stores
whose accumulated byte offsets become array indices after each store.

The native gate passes2368/2368 cached HarfBuzz14.6 records exactly,
including glyphs, advances, offsets, clusters and unsafe flags. Cases cover
horizontal/vertical directions, logical/visual/reverse order, features and
overlapping feature ranges, explicit scripts, end-of-text, missing glyphs,
combining marks and257-scalar stress. The record extractor is the repository's
pinned `tools/oracle/extract.py`; no Roc oracle assertions are generated.

`verify.py` imports the shipped package through `flight.flight`'s explicit
`--replace-dep` arguments and builds the optimized native public driver.
Cached replay needs Python's standard library and Roc, not HarfBuzz/fontTools.
`scripts/record_oracle.py --check tests/fonts/aat-mort/mort-cases.jsonc` verifies
record keys and hashes. Recording uses HarfBuzz14.6.0/uharfbuzz0.56.3.

OTS9.3 accepts the surrounding SFNT fonts but **drops** `mort`; this is not an
independent validator for these legacy programs. HarfBuzz's legacy interpreter
and Apple's format definition are the actual program/behavior oracles.

Another36/36 exact cases use a renamed OFL Inter4.1 body with an original
format4 program (`prepare-real.py`, `real-pins.json`, `body-sans-OFL.txt`). This
exercises real outlines, cmap and GDEF/GPOS data; Inter itself does not ship
legacy morphing. No native legacy-producer font is claimed by this fixture set.
The original fonts and byte recipes use this directory's UPL licence.

`scaling-cases.jsonc` adds9/9 exact cases for16/64/192-state machines with
overlapping signed-offset substitutions and a constant257glyph font body.
The highest reachable state is exposed immediately, avoiding repeated reference
sanitizer sweeps. A chain discovering one row at a time exhausted HarfBuzz's
sanitizer budget at192states, causing HarfBuzz to drop the optional program;
it was not used as an agreement/performance fixture. The library accepts such
bounded programs; reference sanitizer rejection is distinct from bad font data.

`build-consumers.py` builds the public tests, optimized fuzz target and narrow
benchmarks against a loopback-served bundle in a source-sentinel checkout.
`bench.c` links pinned HarfBuzz14.6; `bench.py` checks complete output checksums
before timing. `native-measurements.json` records three increasing sizes:
read allocation calls72/124/255, query calls15/14/14 (unchanged from the
pre-feature query baseline), and2.72–2.92 times HarfBuzz in this synthetic
paired4000-query workload. Startup, reading and planning are included. The
pre-feature binary ignores `mort`, so its timing is not equivalent work.
roc-fuzz0.4.3 exposes allocation calls, not requested bytes or peak live bytes;
those measurements remain unavailable. These are not general shaping ratios.

Preparation converts old byte-indexed states and header coverage into the
existing bounded Apple runtime. Signed contextual offsets share one immutable
value pool, with a difference array checking the union of referenced spans;
overlapping offsets do not copy the glyph array repeatedly. Zero retains its
legacy “no replacement” meaning. Ligature components retain their old units,
including rebasing the accumulator at every store. Missing text-dependent
component/action domains abort the action stream as the reference VM does;
they never become component/glyph zero. The shared shaping budgets still bound
non-advancing machines and insertion growth.

Apple deprecates `mort` in favor of `morx`, so this is compatibility for legacy
fonts rather than a reason to produce new fonts in this format. A valid `morx`
program takes precedence, including an empty valid table; `mort` is selected
when no accepted `morx` program exists. The reader reports independent optional
table problems and strict mode rejects them.

Primary sources:

* [Apple mort format](https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6mort.html)
* [HarfBuzz14.6 shared mort/morx interpreter](https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/hb-aat-layout-morx-table.hh)
* [HarfBuzz14.6 legacy offset conversions](https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/hb-aat-layout-common.hh)
