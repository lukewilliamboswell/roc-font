# Graphite raw bounds and default variation metrics

These original UPL fixtures isolate raw metrics, variation behavior and
default engine eligibility. There are 45 fonts: 28 ordinary positive fixtures
and 17 explicitly diagnostic header/outline combinations. No
Graphite2 implementation sources were read or translated. Programs and tables
use the public format; behavior comes from Graphite2 1.3.14's public C API and
a true Graphite-enabled HarfBuzz 14.6.0 public API. The pinned uharfbuzz wheel
has no Graphite backend and is deliberately not used here.

## Raw TrueType bounds are not OpenType-facing extents

Twenty-two fixtures query VM metric indices 0..10 with hmtx left-side bearing
-100 or 100, while glyf header xMin 0/xMax 300 and advance 602 remain unchanged.
The program writes the metric into the second glyph's Y shift. All eleven
values are identical for both bearings and public face modes 0/6:

```
0,302,600,0,0,300,600,300,602,0,0
```

Thus Graphite's bbox uses the raw glyf header; it does not shift xMin to the
stored left-side bearing. The old package GraphiteMetrics reused OpenType
extents, which did apply that shift. This is a real metric/geometry defect,
independent of variation and of the separate preload-mode subbox defect.
All metric-only fixtures have no collision stage or collision attribute.

`raw-records.json` has 44 public Graphite2 result-bit records. `hb-records.json`
additionally has 22 exact full-flag results through HarfBuzz's actual
`graphite2` shaper, proving the adapter uses the same raw metric values.
Release and tracing Graphite2 libraries agree bit-for-bit on all 44 raw results;
`oracle-proof.json` pins both identities and the output digests.

## Variable outlines do not make the reference Graphite adapter variable

`variable-default.ttf` has an fvar wght axis 0..1 and gvar right phantom-point
variation +200 on glyph 2. Its program reads glyph 2's horizontal advance and
writes it into Y shift. At wght 0/.5/1, the same true HB font's OT advance is
602/702/802. Explicit `ot` shaping also advances 602/702/802. Explicit
`graphite2` shaping keeps advance 602 and metric-derived Y offset 602 in every
location. Each record independently captures HB's variation-aware OT glyph
advance so a broken variation setup cannot silently pass this control.

This agrees with the MIT HarfBuzz 14.6 adapter's
`gr_make_seg(nullptr,grface,...)` call (`src/hb-graphite2.cc:282`). Graphite's
default-metric behavior is intentional reference compatibility, not a reason
to ignore variation for the package's ordinary font queries or OpenType path.
All three design locations and both engines have cached full outputs.

## Default Graphite eligibility: maxp version and byte length

Five ordinary CFF1-only fonts preserve valid maxp 0.5 tables and original Silf
programs. Both raw file-face modes 0/6 reject them. The true HB adapter's
`hb_graphite2_face_get_gr_face` also returns null and explicit `graphite2`
shaping fails. Crucially, **default HB shaping succeeds and exactly matches
explicit OT shaping**. The pinned `hb_shape_list_shapers` order is
`["graphite2","ot","fallback"]`; the extractor uses a NULL shaper list for
these automatic runs, not a named substitute.

A diagnostic maxp 1 CFF-only control establishes that rejecting those fonts
is not proof that glyf is required. A full factorial then checks maxp version
0.5/1.0 × table length 6/32 × outlines CFF-only/glyf-only/both/neither. The
Graphite face is available only at **version 1.0 AND length 32**, independently
of these four outline combinations. Padded maxp 0.5 still fails; truncated
maxp 1.0 still fails. Every automatic result matches explicit OT when the face
is unavailable and explicit Graphite when it is available.

These 16 factorial fonts and the additional maxp 1 CFF-only control are
explicit diagnostics, not claims of valid OpenType combinations. OTS rejects
ten; some accepted diagnostics are repaired by OTS (for example a CFF maxp1
version is corrected). The original bytes are preserved; no oracle ever uses
the sanitized bytes. Ordinary CFF maxp 0.5 positives pass OTS unchanged.
The maxp 1 CFF-only face's acceptance does not establish useful CFF support:
its Graphite glyph2 advance is 0 while the ordinary OT advance is 600.

`raw-records.json` now contains 56 explicit-mode results, including the 12
CFF file-face rejections. `hb-records.json` has 94 true HB results, including
all automatic/explicit engine comparisons. The file-face loader rejects the
OTTO diagnostic even when HB's public callback-based face accepts it; therefore
engine selection conclusions use the HB callback face, not file-face alone.

## Reproduction and provenance

`generate.py --check` reproduces all 45 font bytes and both JSONC case lists with
fontTools 4.61.1. `record_ots.py` records acceptance for every original font by
OTS 9.3.0 and pins source commit/binary SHA. All 28 nondiagnostic fonts pass
without table warnings; diagnostic outcomes and warnings remain explicit.
`record_hb.py` captures explicit engine choice and uses
`hb_font_set_variations`; `hb-oracle.json` pins the Graphite-enabled HB library
and its linked Graphite library. Raw face modes are explicit case inputs.
Every cache key includes the entire case, font bytes and oracle identity.

Offline, without any oracle or fontTools:

```
python3 tests/fonts/graphite-metrics/check.py
python3 tests/fonts/graphite-metrics/record_hb.py --check
python3 tests/fonts/graphite-metrics/record_raw.py --check
python3 tests/fonts/graphite-metrics/record_ots.py --check
```

Native Roc replay and public regression registration are integration work;
these reference caches alone do not claim that the runtime fix has passed.
