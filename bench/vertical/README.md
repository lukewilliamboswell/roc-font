Vertical native performance consumers. Reading and planning happen before timing.
Both native loops set TTB and the chosen script; the runner verifies the UTF8
length, script, direction and input checksum. HarfBuzz 14.6 is invoked through
the pinned uharfbuzz library in a C loop, avoiding per-call Python overhead.

```
ROC=<nightly> <pinned-oracle-python> bench/vertical/bench.py --model jp
ROC=<nightly> <pinned-oracle-python> bench/vertical/bench.py --model positioning --reuse-from jp-after
ROC=<nightly> <pinned-oracle-python> bench/vertical/bench.py --model mong --reuse-from jp-after
```

All three models use the same two Roc native applications; their explicit input
header selects the script/text. `positioning` uses the original mark-attachment
fixture; `jp` uses the real Japanese subset, and `mong` uses the existing real
Mongolian USE subset with synthetic vertical metrics. Three increasing sizes
measure allocation calls and elapsed-time ratios against HarfBuzz in each run.
Requested bytes and peak live bytes are unavailable from roc-fuzz 0.4.3 and are
reported as unknown, independently of allocation calls.

`horizontal-before.json` preserves the pre-change optimized three-size ordinary
Inter shape/kerning baseline. It was recorded before changing the hot path.
It contains Roc timing only and makes no reference-speed comparison claim.
The integrator owns the final ordinary allocation ratchet and matched reference
timing gate alongside the other concurrent engines.
