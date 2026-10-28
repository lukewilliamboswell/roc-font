# Original Graphite kerning witnesses

These UPL fonts isolate rules discovered through Graphite2's **public C API**
and **public `gr_start_logging` JSON**. No Graphite2 implementation source was
opened or used to construct the programs or equations. The generator uses only
the parent directory's original `generate.program` and `collision_generate.make`
APIs plus original fontTools patches of documented tables. See LICENSE.

`generate.py --check` reproduces all 68 font files and the JSONC case data with
fontTools 4.61.1. `check.py` checks cached keys and font hashes with the Python
standard library alone. The parent extractors reproduce the references:

```
python record.py --cases kerning-audit/cases.jsonc --output kerning-audit/records.json
python record_traces.py --cases kerning-audit/cases.jsonc --output kerning-audit/traces.json
```

Run those commands in the parent directory, using the oracle Python environment.
`records.json` is from the public ABI of Graphite2 1.3.14; `traces.json` is from a
same-version Release AppleClang17 build with tracing enabled. Each cache records
its library hash and extractor provenance. Every reference face/segment was
accepted, without a program abort. The release and tracing libraries give
bit-identical public results on all 68 cases (`oracle-proof.json`). Native Roc
agreement is a separate gate;
recording a reference result does not claim that the package reproduces it.

The focused cases cover these independent observations:

| Cases | Rule isolated |
| --- | --- |
| `base`, `edge-*` | Kerning changes advances; occupied-bin left/right octabox equations are asymmetric. |
| `float-margin-*` | Binary32 association: `F32(2*m/3)` differs from multiplying by pre-rounded `F32(2/3)`. Translate bounds before edge arithmetic. |
| `bins-*` | Short glyphs and near/disjoint vertical ranges pin occupied-bin endpoints; no vertical overlap can retain the reference's large sentinel gap and clamp to a movement limit. |
| `bounds-*` | Asymmetric and inverted bounds. Increment clamps to `min(maxX−previous,max(needed,minX−previous))`; inverted limits choose the upper increment. |
| `prior-bounds-*` | Old offsets outside new bounds, without repairing either value. |
| `prior-x`, `prior-y` | Two passes preserve prior collision offsets. LTR KERN suppresses the entire own collision offset in physical placement; authored slot shifts remain. RTL retains it. |
| `blank-*` | Empty outlines do not add IS_SPACE128. Phase1 empty bounds constrain as points; phase3 empty target/neighbor behavior differs. |
| `space-*`, `ignore-*` | Whitespace contributes twice its advance to clearance in these reference controls; IGNORE does not. |
| `child-*` | Attachment-root advancement and scan-order eligibility; final inherited flags alone do not determine which root is processed. |
| `exclude-*` | Dynamic valid/invalid exclude-glyph IDs and offsets remain queryable; they do not change these phase3 pair results. This says nothing about phase1 excludes. |

For isolated rectangles/diagonals the occupied-bin fit is:

```
m = max(authored_margin,10)
w = F32(2*m/3)
c = target_min_y - m
lo_i = c + i*w - 1
hi_i = lo_i + w
left = max(x_min, sum_min-hi_i, diff_min+hi_i-w)
right = min(x_max, sum_max-hi_i, diff_max+hi_i)
```

Target edges subtract/add `m`. Target occupied indices start at
`floor((glyph_min_y-c+1)/w)` and end at
`floor((glyph_max_y-c+1)/w)+1`, inclusive; neighbor occupied indices omit the final
`+1`. Intersect neighbor indices with occupied target bins. The trace includes
additional empty storage bins; its capacity-growth rule is not a geometry rule.
Every extreme-coordinate operation association remains subject to differential
proof; the cached C-API position/advance bits, rather than rounded trace decimals,
are the exact reference for floating results.

`stillBad` is **not directional** in these controls: forcing RTL needed 210 up to500
or LTR needed −210 down to−500 still reports true. Equal requested/result moves
report false; non-equal clamps tested here report true. This does not assert an
unmeasured epsilon threshold.

The author-facing collision contract is documented in SIL's
[Graphite Description Language manual](https://static-scripts.sil.org/cms/sites/projects/download/gdldocumentation/GDLdocumentation.pdf).
These intentionally small fonts test collision facts and program behavior; they
are not substitutes for a real-font shaping corpus or a performance benchmark.
