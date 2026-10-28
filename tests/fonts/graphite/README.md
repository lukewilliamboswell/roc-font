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
