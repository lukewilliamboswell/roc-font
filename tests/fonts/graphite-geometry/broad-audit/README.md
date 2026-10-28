# Original broad-guard observations

These 84 UPL fonts preserve 76 original boundary/point witnesses plus 8 displayed
broad-limit controls. They record Graphite2 1.3.14 public C-API results and public
`gr_start_logging` observations. No engine implementation source was opened or
used. No complete guard predicate is claimed.

`generate.py --check` reproduces bytes and case JSONC with fontTools 4.61.1.
`check.py` uses the standard library to verify both caches, and additionally
checks that the renamed fixtures retain the original public result bits and
full/missed classifications in `recipes.json`. Each cached mode remains a
normative observation, including cases where final public positions happen to
coincide. It must not become an ignored comparison or tolerance exception.

The parent extractors accept:

```
python record.py --cases broad-audit/cases.jsonc --output broad-audit/records.json
python record_traces.py --cases broad-audit/cases.jsonc --output broad-audit/traces.json
```

Both have `--check`. All 84 reference faces/segments are accepted without an
abort; release and tracing-build public results are bit-identical. Library and
original-generator hashes are in `oracle-proof.json`. Native Roc agreement is a
separate gate and is not claimed by caching reference results.

## What these cases establish

The simple eight-point fit for equal, zero-origin rectangles is not general.
With target 100×200 and neighbor 300×600, limits ±100, the last observed full
positive distance is 350. Substituting target sizes into that fit predicts 300.
A 300×600 target and 100×200 neighbor retain positive distance 850 but have
negative extent 200, versus 400 for equal boxes. Offset-box, dy and signed
controls distinguish observer ownership and the relevant coordinate spaces.

The full/missed decision is not monotonic in distance for arbitrary movement
limits. With X bounds `[-500,-101]`, Y bounds `[-300,-20]`, distance −199 is a
full solve, while −200, −100 and 0 are missed. Generic binary search assuming a
full point at zero is invalid. The retained scan endpoints are observations,
not assertions that every point closer to zero is full. Some scan endpoints
have no full point; their cached classification states that explicitly.

A full solve does not require a projected removal to clip a final movement
interval. A prior-offset control has X/Y constraints absent, diagonal removal
`[1100,1400]` and collapsed movement slices `[0,0]`, yet still performs a full
solve. At the next missed point it preserves the old offset. The earlier retry
audit separately pins neighbor filtering before this guard is evaluated.

## Displayed broad rectangle differs from final movement slices

The asymmetric and prior-offset controls establish this observed trace field:

```
broad.left   = -authoredMaxX
broad.bottom = authoredMinY - passStartOffsetY
broad.right  = authoredMaxX - passStartOffsetX
broad.top    = authoredMaxY - passStartOffsetY
```

In particular, the left field ignores authored X minimum and pass-start X offset.
Final axis ranges still retain authored min/max. Examples:

| Authored bounds / prior offset | Displayed broad rectangle |
| --- | --- |
| `[101,-300,201,300]` / `(0,0)` | `[-201,-300,201,300]` |
| `[-500,-300,-101,-20]` / `(0,0)` | `[101,-300,-101,-20]` |
| `[-100,-100,100,100]` / `(200,0)` | `[-100,-100,-100,100]` |
| `[-50,-30,200,70]` / `(0,100)` | `[-200,-130,200,-30]` |

This may create an inverted broad rectangle even when authored movement bounds
are ordered. Do not repair it, substitute final axis ranges, or silently equate
this displayed rectangle with a conventional search box. It is measured
reference behavior, not a claim that the remaining candidate predicate is known.

## Remaining boundary of the evidence

A complete conservative preprojection guard has **not** been identified. The
cases reject current-ink overlap, ordinary Euclidean search rectangles, and
"active iff a final interval is clipped" as general replacements. They retain
unequal/offset boxes, vertical positions, asymmetric bounds and prior offsets so
that a later concrete derivation can be checked exactly instead of broadening
an agreement tolerance.
