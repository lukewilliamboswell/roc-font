# Original kerning association witnesses

These 9 UPL fonts are small public-C-API witnesses for binary32 operation order
in phase 3 kerning. No engine implementation source was opened or used.
`generate.py --check` reproduces their bytes and case JSONC with fontTools 4.61.1;
`check.py` checks cached keys with the standard library alone.

Run the parent `record.py` and `record_traces.py` with
`--cases association-audit/cases.jsonc --output association-audit/records.json`
(or `traces.json` for the trace extractor). Both support `--check`. Every face and
segment is accepted by Graphite2 1.3.14 without an abort; release and tracing-build
public results are bit-identical (`oracle-proof.json`). Native Roc replay is a
separate gate and is not claimed by reference recording.

Eight cases distinguish the following candidates, using exact C-API outputs
rather than rounded trace decimals. `F` means one binary32 rounding; world
bounds have already been translated. Under the occupied-bin model established
by the earlier kerning audit, the matched observations select:

| Branch | Selected in these witnesses | Ruled out in these witnesses |
| --- | --- | --- |
| Left SUM | `F(F(sumMin-hi)-margin)` | `F(sumMin-F(hi+margin))` |
| Right SUM | `F(F(sumMax-hi)+margin)` | `F(sumMax-F(hi-margin))` |
| Right DIFF | `F(F(diffMax+hi)+margin)` | `F(diffMax+F(hi+margin))` |

This does not claim all sample-coordinate or bbox-normalization associations
are identified. The ninth case deliberately preserves a remainder:

* `right-diff--100-100-200-10`: LTR, target bbox `[-100,0,0,1]`, target-only
  diagonal bytes `[0,255,0,200]`, neighbor bbox `[0,0,3,1]`, distance 0, margin 10,
  target flags 17, neighbor flags 0, pass flags 9.
* The observed following origin and target advance are `9.450983047485352`.
  The grouped candidate predicts `9.450984001159668`, and facet-then-margin
  predicts `9.450984954833984` under the current sample model. Neither matches.
* A slightly different sample value can explain the discrepancy, but that is
  an inference requiring another distinguishing probe, not an established rule.

`analytic_association: unresolved` is explanatory metadata. The cached native
reference output remains an exact normative comparison; this case is not an
ignored failure, tolerance exception, or claim that the library reproduces it.
The earlier translated-left-DIFF witness is separate evidence and should not be
silently generalized from these SUM/right cases.
