# Scan-cell facet selection and exact boundary observations

These 24 original UPL fixtures preserve the public observations that replaced
a proposed first-cell exception with a per-cell geometric rule. No Graphite2
implementation source was read or translated. The directory retains its initial
`first-cell-audit` name, but later-cell controls are essential to the evidence.

The whole glyph, actual subbox, fractional subbox, combined diagonal cuts,
shifted origins, translated equalities and later-cell controls use original
public-format font programs. Every font includes a full subbox on UNUSED
glyph 0, which never occurs in `ab`. The tested neighbor remains bitmap 0 or an
actual part as declared. This avoids the independently established face-wide
preload bug: all 24 direct public results are bit-identical in modes 0 and 6.
Release/tracing Graphite2 1.3.14 results likewise agree 24/24. All faces and
segments accept; no abort is hidden.

## Geometric conclusion and rejected alternatives

For a right-edge scan, let S/D be the translated upper SUM/DIFF bounds of the
actual octabox being sampled, and X its right rectangle bound. The diagonal
intersection has Y=(S−D)/2. The reference chooses the active diagonal by that
intersection relative to the CURRENT CELL midpoint, then evaluates the chosen
diagonal at the strip's high sample and caps it by X. This is not restricted
to the first occupied cell. Cells 3/20/26/46 expose clear differences from
always taking `min(X,S−HI,D+HI)`.

Default full DIFF makes `S−D` algebraically equal to
`(S−wholeGlyphXmax)+wholeGlyphYmin`, which explained an earlier whole-bounds
hypothesis. Combined SUM/DIFF cuts disprove that proxy. Fractional actual parts
also disprove substituting their rectangle bounds for the true diagonal corner.
A full-size actual subbox seeds exactly as its geometrically identical whole
glyph; actual parts do not always use the formal minimum.

The exact recorded outputs are authoritative. `check.py` pins selected cells
and the public result bits; it does not claim a complete mathematical proof
for every accepted font.

## Floating-point association limits

All arithmetic in the tested models is binary32. With cache origin c, width w
and cell index i, these two midpoint associations remain indistinguishable in
our measured campaigns:

```
A = f32(f32(2*f32(c-1)) + f32((2*i+1)*w))
B = f32(2*f32(f32(c + f32((i+0.5)*w))-1))
```

The comparison uses `f32(S-D) >= A` (or B). The following alternatives are
REJECTED, without an epsilon or broadened tolerance:

* `f32(f32(2*LOW)+w)` changes the result at exact margin 101 equalities.
* Dividing the normalized corner by w before comparing with i+0.5 fails the
  translated equality. At target Y 32000/neighbor X 1000, the reference's needed
  movement is EXACTLY 101 and its target physical X is EXACTLY 1301; the rejected
  association would choose the formal edge 1199.998046875 instead of 1200.
* Applying the choice only in the first cell fails the later-cell controls.

The named `recurrence-unresolved` case preserves a further numerical remainder:
later logged slanted-edge values can differ from directly recomputing
worldDiagonal−HI by a few binary32 units. Choosing the right facet does not
prove the edge-value operation sequence. No source exception, generated Roc
expectation, cache rewrite or tolerance masks that unresolved association.

## Reproduction and cache checks

`generate.py --check` reproduces the 24 font bytes and the mode 0/mode 6 JSONC
cases with fontTools 4.61.1. Only original parent fixture builders are imported.
`records.json` and `mode6-records.json` contain full public C-API result bits;
`traces.json` preserves public logging with pointer names normalized by initial
slot order. Keys include the complete case, font SHA and oracle identity.
`oracle-proof.json` pins both binaries and all outputs.

Offline, with Python's standard library and no oracle/fontTools:

```
python3 tests/fonts/graphite-geometry/first-cell-audit/check.py
python3 tests/fonts/graphite-geometry/first-cell-audit/record_modes.py --check
python3 tests/fonts/graphite-geometry/first-cell-audit/record_modes.py --check --cases first-cell-audit/mode6-cases.jsonc --output first-cell-audit/mode6-records.json
python3 tests/fonts/graphite-geometry/record_traces.py --check --cases first-cell-audit/cases.jsonc --output first-cell-audit/traces.json
```

Native Roc replay and any additional default-HarfBuzz adapter records belong
to integration; recording these public reference caches alone does not claim
that the runtime agrees.
