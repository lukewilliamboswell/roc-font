# Independent broad-guard challenges

These 14 original UPL fonts challenge the broad/missed boundary independently
of the earlier 84-case fit. Reference evidence is only the public Graphite2
1.3.14 C ABI and public logging JSON. No engine implementation source was read.
All faces/segments accept; release and tracing-library public result bits agree
14/14. Cached full results and traces remain separate from Roc agreement.

For target A at 0, neighbor B at positive distance, both 300×600 and movement
limits ±1000, margin 50 gives FULL at 1649/1650 and MISSED at 1651. Margin 500 gives
FULL at 2099/2100 and MISSED at 2101. The initial 1601 controls also produce FULL
at either margin. Thus the margin 0 last-full 1600 observation cannot simply be
used unchanged for nonzero margins. This falsified a stale margin-free Python
model, **not** the current Roc helper 109113e: its owner confirmed that existing
margin/sqrt2 padding already passes these exact boundary checks. No runtime
change was requested or made by this investigation.

Two controls translate both local bboxes by ±2000 in X/Y; the public reference
logs MISSED even with physical overlap. Four two-pass controls retain a
fractional margin 50 correction before changing distance/limits; all four
produce FULL on the next pass. The cache preserves exact final C-API bits.
Public trace `currOffset` prints 227.273, so recovering its true binary32 value
from those rounded decimals is not a valid precision oracle. These cases do
not claim a complete predicate, an exact association for every intermediate,
or a numerical proof of a conventional broad-phase rectangle.

The original `broad-audit` builder creates the fonts from the recipes included
in each JSONC case. With fontTools 4.61.1, `generate.py --check` reproduces bytes
and cases. `check.py` uses only the standard library and validates complete
keys plus every explicitly observed FULL/MISSED classification. Parent public
extractors accept these paths:

```
python record.py --check --cases broad-extra-audit/cases.jsonc --output broad-extra-audit/records.json
python record_traces.py --check --cases broad-extra-audit/cases.jsonc --output broad-extra-audit/traces.json
```
