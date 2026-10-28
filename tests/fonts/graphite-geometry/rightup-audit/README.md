# Complementary RIGHTUP sequencing observations

These 20 original UPL fonts preserve five distinguishing controls in both font
directions and both traversal relations. The forward pass uses raw order 2;
the reversed second pass uses raw order 1 after an attachment-only first pass.
Both select RIGHTUP tags −11..−15. They complement the original 67-case matrix
and the corrected sequencing README; no old font or cache is changed.

Neighbor above.xoffset −100/+100 gives A −20/180 with dx 80, proving the positive
sign in `A=dx+NcenterX−TcenterX+aboveX`. Neighbor below.xlimit −100/+100 gives
B 280/480, proving `B=dx+NmaxX−TminX+belowX`. The below.xlimit −2000 control
makes radial region 13 overlap the current X slice, exposing its full Y range
`[−1300,20]`: the upper endpoint is **C-H**, with C 170/H 150, rather than an
assumed mirrored C+H. This is directly logged, not inferred from the final
best-axis choice. `check.py` pins these exact coordinates for every variant.

Reference data comes only from the public Graphite2 1.3.14 C ABI and public
`gr_start_logging` JSON. No engine implementation sources were used. Programs
reuse the original parent/sequencing builders and documented table format.
Release and tracing-library result bits agree 20/20; oracle-proof.json pins
binary hashes and cached output hashes. Face/segment acceptance is positive
for all 20 controls. Native Roc agreement remains a separate integration gate.

With fontTools 4.61.1, `generate.py --check` reproduces all bytes and JSONC.
Without an oracle/fontTools, `python check.py` validates keys and measured
relations. Parent public extractors reproduce or check the caches:

```
python record.py --cases rightup-audit/cases.jsonc --output rightup-audit/records.json --check
python record_traces.py --cases rightup-audit/cases.jsonc --output rightup-audit/traces.json --check
```
