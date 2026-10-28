# Original Graphite sequencing witnesses

These 67 UPL font programs isolate collision sequencing using documented table
formats, the public Graphite2 1.3.14 C ABI, and public `gr_start_logging` JSON.
No Graphite2 implementation source was opened or used. The generator reuses the
parent directory's original program/font builders and original fontTools patches.
The author-facing starting point is SIL's [GDL manual, section 6.8.1.1](https://static-scripts.sil.org/cms/sites/projects/download/gdldocumentation/GDLdocumentation.pdf).
The equations below describe measured reference behavior, including quirks;
they are not presented as requirements stated by that manual.

Reproduce bytes/JSONC with fontTools 4.61.1: `python generate.py --check`.
Check both caches without any oracle installed: `python check.py`.
From the parent geometry directory, record or check using:

```
python record.py --cases sequencing-audit/cases.jsonc --output sequencing-audit/records.json
python record_traces.py --cases sequencing-audit/cases.jsonc --output sequencing-audit/traces.json
```

Both extractors support `--check`. The reference build/library hashes are in
each cache. All 67 reference faces and segments were accepted, without an abort.
Release and tracing-build public results are bit-identical (`oracle-proof.json`).
Native Roc agreement is a separate gate and is not claimed by recording oracles.

## Selection and ownership

`canonical` has A attached to B, with movable target B and preceding obstacle A.
Sequencing is inactive in the otherwise matching `separate-trees` control.
`siblings` proves it also applies to two children sharing another parent.
The target's sequence class must be nonzero. Its proximity class selects the
neighbor class; proximity 0 falls back to its own class. Class 0 does not become 1,
and an explicit proximity match does not enable a class 0 target. Unsigned 65535
works, including Glat signed−1 encodings. The target owns order selection; the
neighbor owns above/below/alignment parameters. The neighbor's own order is
irrelevant to these controls. Independent target/neighbor collision margins do
not change the sequencing-region coordinates or coefficients here; they still
affect ordinary ink collision costs.

Both exact orders 1 and 2 enable diagonal sequencing. For a preceding
neighbor, raw 1 selects the canonical LEFTDOWN branch (tags −21..−25), while
raw 2 selects the complementary RIGHTUP branch (tags −11..−15). For a following
neighbor those choices exchange: raw 2 selects the identical canonical
LEFTDOWN equations; raw 1 selects RIGHTUP. The earlier prose omitted this
second branch; the unchanged `order-2-ltr/rtl` cached traces already contain it.
Neither branch is inactive merely because the relation differs.

Raw 4 enables the upper forbidden region and raw 8 the lower one for a
preceding neighbor; their vertical roles exchange for a following neighbor.
A two-pass program establishes the tree without collisions, then runs flags 33:
the relationship flips despite unchanged text and attachments. It therefore
follows reversed pass traversal. Font LTR/RTL alone does not change it.
Exact-order controls 0/3/5/6/9/10/12/15 add no sequencing regions here, despite
the manual describing an order bitmap.

## Canonical rectangles and costs

Use target/neighbor local bounding boxes T/N. Let Cx/Cy be the target bbox center,
Wx/Hy its half width/height, and dx/dy the already positioned neighbor origin
minus the target's unshifted origin. Let own collision offset be ox/oy. All
arithmetic is binary32; the C-API result bits are exact evidence, while logged
coefficients are rounded decimals. Cases retain offset bboxes and repeated
nonzero offsets to distinguish the coordinate spaces.

The finite outer rectangle is:

```
XL=movementMinX-Wx; XH=movementMaxX+Wx
YL=movementMinY-Hy; YH=movementMaxY+Hy
A=dx+NcenterX-Cx+neighbor.above.xoffset
B=dx+NminX-TmaxX-neighbor.below.xlimit
C=dy+NcenterY-Cy
E=dx+NmaxX-Cx
H=neighbor.valign.height
```

Public trace tags identify these overlapping regions. Bounds are the projected
coordinate frame, so use the explicit projection rules below rather than an
ordinary point-in-rectangle interpretation.

| Tag | Rectangle | Penalty |
| --- | --- | --- |
| −21 | `[A,XH] × [YL,C]` | `aboveWeight*(x-A)^2` |
| −22 | `[B,XH] × [C,YH]` | hard exclusion |
| −23 | `[XL,B] × [C-H,YH]` | `belowWeight*(x²+y²)` |
| −24 | `[XL,E] × [C,C+H]` | `valignWeight*(y-(C+H))²` |
| −25 | `[XL,E] × [C-H,C]` | radial below penalty plus `valignWeight*(y-(C-H))²` |

The complementary RIGHTUP branch uses the same A and C, with:

```
B=dx+NmaxX-TminX+neighbor.below.xlimit
E=dx+NminX-Cx
```

| Tag | Rectangle | Penalty |
| --- | --- | --- |
| −11 | `[XL,A] × [C,YH]` | `aboveWeight*(x-A)^2` |
| −12 | `[XL,B] × [YL,C]` | hard exclusion |
| −13 | `[B,XH] × [YL,C-H]` | `belowWeight*(x²+y²)` |
| −14 | `[E,XH] × [C,C+H]` | `valignWeight*(y-(C+H))²` |
| −15 | `[E,XH] × [C-H,C]` | radial below penalty plus `valignWeight*(y-(C-H))²` |

The positive sign of above.xoffset is unchanged: supplementary original public
trace probes at −100/+100 give A=−20/180 with dx=80. Below.xlimit −100/+100
gives B=280/480. The −13 upper Y endpoint is **C-H**, not a conventional
mirrored C+H: a below.xlimit −2000 probe exposes its Y interval `[−1300,20]`
with C=170 and H=150. Those supplementary read-only probes informed this prose
correction; they do not replace or alter any of the 67 original cached answers.

For upper/lower hard vertical regions define
`L=dx+NminX-TmaxX-Cx`, `R=dx+NmaxX-TminX-Cx`.
Tag−31 uses `[L,R] × [dy+NmaxY-Cy,YH]`;
tag−32 uses `[L,R] × [YL,dy+NminY-Cy]`.

## Projection intervals

For rectangle `[l,r] × [b,t]`, X emits `[l,r]` when the current Y span
`oy±Hy` overlaps `[b,t]`; Y emits `[b,t]` when `ox±Wx` overlaps `[l,r]`.
The isolated controls pin ordinary interior overlaps; extreme endpoint and
operation-association behavior remains subject to differential tests.
Let `d=ox-oy`, `s=ox+oy`, `P=Wx+Hy`.

Soft SUM intersects `[2l-d,2r-d]` and `[2b+d,2t+d]`.
Soft DIFF intersects `[2l-s,2r-s]` and `[s-2t,s-2b]`.
Discard empty intersections. Hard intervals retain whole-target overlap:

```
SUM.low = max(l+b,2l-d-P,2b+d-P)
SUM.high = min(r+t,2r-d+P,2t+d+P)
DIFF.low = max(l-t,2l-s-P,s-2t-P)
DIFF.high = min(r-b,2r-s+P,s-2b+P)
```

These are distinct from soft center slices. For the canonical −22 rectangle
`[-170,1150] × [170,1300]`, SUM is `[0,2450]`, DIFF `[-790,110]`.
The asymmetric movement rectangle pins finite bounds independently of font UPEM.

## Quadratic coefficients

Coefficients mean `a*z² - 2*b*z + c`. Define
`Fx=Cx+ox`, `Fy=Cy+oy`, `D=Fx-Fy`, `S=Fx+Fy`.
Transform each penalty component independently, then add coefficients where
components/regions overlap. The diagonal transforms contain measured quirks;
a conventional 2D quadratic rotation gives different results.

| Component | X | Y | SUM | DIFF |
| --- | --- | --- | --- | --- |
| `w*(x-A)^2` | `(w,wA,wA²)` | `(0,0,w*(Fx²+A²))` | `a=w/8; k=2A+2Cx-D; (a,ak,ak²)` | `a=w/8; k=2A+2Cx-S; (a,ak,ak²)` |
| `w*(y-K)^2` | `(0,0,w*(Fy²+K²))` | `(w,wK,wK²)` | `a=w/8; k=2K+2Cy+D; (a,ak,ak²)` | `a=w/8; k=2K+2Cy+S; (a,ak,ak²)` |
| `w*(x²+y²)` | `(w,0,wFy²)` | `(w,0,wFx²)` | `(w/4,0,wD²/4)` | `(w/4,0,wS²/4)` |

In particular, orthogonal square constants omit the linear cross term. First
pass above-offset 0 gives the Y constant 8670000 rather than1470000. In the
repeated pass, own offset(−220,−220) makes the radial X constant 640000, proving
that the fixed coordinate includes bbox center300 plus offset −220, not either
one alone. The fractional-output case returns Y bits for−33.33333206176758.
The README records the experimentally established algebra; it does not prove
every reassociation at extreme binary32 magnitudes.
