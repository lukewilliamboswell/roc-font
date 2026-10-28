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

Recorded vertical results use the same two immutable native binaries. Output
checksums match a separate HarfBuzz shaping call at every measured size.

| Work | Scalars | Allocations per call | Roc/HarfBuzz elapsed ratio |
| --- | --- | --- | --- |
| Japanese |192/768/3072|12/12/12|11.67/12.08/16.15|
| Mark attachment |80/320/1280|21/21/21|8.06/9.88/9.66|
| Mongolian |96/384/1536|19/19/19|45.52/45.58/50.04|

These show bounded allocation cost and substantial remaining runtime work.
They do not claim HarfBuzz performance parity. See the adjacent JSON records
for exact source, bundle, runner and native binary identities.

Both new native fuzz targets passed 1000 seeded inputs with leak detection:
`fuzz-shaping.json` covers real Japanese fonts and explicit vertical pair/cursive
positioning; `fuzz-tables.json` covers malformed vertical tables, active VVAR
queries and 16-times larger metric arrays. Their package is immutable bundle
`EohUtiz6VoHoLukQRBnEtvSw5Dzd6gYPDvUqjcx7Fvkw`; the CI source revision identifies
the fuzz consumer. Later combined integration checks use the integrator's bundle.
