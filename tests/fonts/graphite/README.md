These original UPL fonts are built from the documented Graphite table and opcode
formats in Graphite2 1.3.14's `doc/GTF.asc` and `doc/OpCodes.asc`. Their programs
and generators are original; no Graphite2 implementation code is copied.
The oracle uses the separately installed library's documented C ABI.
All seven fonts pass OTS9.3.0 with every Graphite table retained, rather than
merely succeeding after those tables were discarded.

`abort-cases.jsonc` and `abort-records.json` establish a text-dependent program
abort contract before the Roc interpreter is activated. All faces are accepted
by Graphite2. Feature 100 declares values 0 and 1; the records check that the public
`gr_fref_set_feature_value` accepts each value.

* `divide-feature.ttf` matches `a` and sets its advance to 5 divided by feature100.
  Value 0 makes `gr_make_seg` return NULL; value 1 succeeds with advance 5.
  The same face with text `b` succeeds under both values, with advance 602.
* `mutate-then-divide-zero.ttf` first changes an advance to 17 and then divides by
  zero. Graphite2 still returns NULL, with no segment or mutated prefix available.
  Both `ab` and `ba` controls show that earlier completed text is not observable.
* `replace.ttf` and `set-advance.ttf` are successful substitution/positioning
  controls. `version.ttf` and `version-shift.ttf` establish that the accepted
  `PUSH_VERSION` opcode produces 0 in Graphite2 1.3.14.

NULL segment is distinct from a rejected face, an empty successful segment and
an exhausted work budget. The total Roc contract is an empty run/origins plus
`ProgramAbort`, with no implicit OpenType fallback. The checked public API can
then report this diagnostic without misclassifying it as a budget.

Regenerate with fontTools 4.61.1 and Graphite2 1.3.14:

```
python tests/fonts/graphite/generate.py --check
python tests/fonts/graphite/record_abort.py
python tests/fonts/graphite/record_abort.py --check
```

The last command validates cached case/font/oracle keys without loading the
reference library. `oracle.json` records its actual engine version and binary
SHA256; pkg-config's API package version is not the engine version.

The four unmodified SIL families named in `real-fonts.json` come from the pinned
Graphite2 source archive; their adjacent licences travel with the font bytes.
`check_real.py` verifies both font hashes and their archive members. The public
reader tests load each through the served package and assert that no Graphite
table is dropped. This is a reader proof, not a shaping agreement claim.

Real compiler output can disagree with OTS's interpretation of advisory Silf
header offsets. These files are retained unmodified and validated using their
actual checked spans; Graphite2 accepts them. The original small fixtures above
also satisfy OTS's stricter header interpretation.

`semantics-cases.jsonc` and `semantics-records.json` pin sixteen successful
controls for rule-input snapshots and integer conversions. Replacing A with B
and then copying input offset 0 restores A. Reading glyph metrics at input
offset 0 after that replacement still reads A's original advance. Trunc8 keeps
the low unsigned byte; Trunc16 sign-extends the low short in the pinned engine.
These programs are original and all four additional fonts retain every
Graphite table under OTS9.3.

```
python tests/fonts/graphite/record_abort.py --cases semantics-cases.jsonc --output semantics-records.json
python tests/fonts/graphite/record_abort.py --cases semantics-cases.jsonc --output semantics-records.json --check
```

`shape-cases.jsonc` and `shape-records.json` are the public-run oracle matrix,
recorded through HarfBuzz14.6.0's Graphite2 adapter linked to Graphite2 1.3.14.
The pinned uharfbuzz wheel does not enable Graphite2; these records do not use it.
`shape-oracle.json` records both reference binary hashes and the build command.
The four unmodified families exercise Latin, Myanmar, Arabic and Nastaliq;
all their declared feature values and Sill languages are included. Range cases
select by original UTF8 character-start offsets. Vertical requests deliberately
record the adapter's horizontal Graphite positions; no vertical-layout claim is
inferred from those requests. The OpenType-only controls use fonts without
Apple layout tables so they do not introduce a hybrid provider ambiguity.

```
python build_oracle.py --source /path/to/harfbuzz-14.6.0
python cases.py --check
python record_shapes.py
python record_shapes.py --check
```

The additional original stack fonts distinguish accepted programs that succeed
with peak depth1023, abort on matching text at depth1024, and abort on return
with an unconsumed stack value. Empty and nonmatching controls succeed. These
are text-dependent program aborts, not malformed font tables or work budgets.

The later live-attribute controls refine input protection: slot attributes stay
live, while glyph-writing actions protect original input for later glyph reads
and copies. `live-copy` keeps an authored advance17; `set-glyph-copy` restores
original advance601. Conditional and SetFeat controls pin stack operand order
and unsigned feature-value clipping before narrowing. All these original
fonts retain their Graphite tables under OTS9.3.

`feature-divergences.json` lists exactly16 Feat2.1 alias cases. The official
GTF FeatureFlags section defines bit0 as an alias of the previous feature.
We interpret that as sharing the selected value, setting domain and Sill
language default, while allowing a different UI label. Graphite2 1.3.14 ignores
this flag and treats the second feature as independent. Its raw cached answers
remain in `feature-records.json`. `check_aliases.py` independently decodes the
original font with fontTools and constructs the normative runs from its two
0/1 settings and explicit language default. The verifier checks every complete
normative run against an exact cached reference key; no general feature or
font mismatch is ignored. Enable this registry only for its dedicated matrix:

```
python check_aliases.py --check
python verify.py --cases feature-cases.jsonc --records feature-records.json \
  --oracle feature-oracle.json --divergences feature-divergences.json
```

The path arguments above are relative to the current directory; run this example
from this fixture directory, or supply paths from the repository root.
