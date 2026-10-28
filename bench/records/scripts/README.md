Default shaping and kerning after adding script-specific stages, on the latest available Roc nightly. These native consumers imported an immutable bundle served by `scripts/flight.py`.

`default-queries.json` records source bundle content hashes, checkout metadata, binary SHA256 hashes, case checksums, samples and same-run HarfBuzz comparisons. The nominal 512/4096/32768-byte cases contain 505/4088/32744 bytes of text.

Across those sizes, kerning uses 14 allocation calls and shaping 21, with zero leaks: unchanged from the untouched compiler baseline. The shape-time ratio to the same system HarfBuzz13.2.1 comparator is 1.395 geometrically, against 1.426 before; this difference is within timing variation and is not claimed as a speedup. Script-specific costs and font reading are separate measurements.

The allocation-only command was `python3 scripts/bench.py --ops shape,kerning --langs roc --only inter --label scripts-after --check`; timing used `--no-allocations`. The paired replay reused the optimized bundle binary, built the current C comparator, and used the same benchmark measurement function for seven 200ms batches per implementation and size. The recorded compiler is nightly-2026-10-27-de79a0f. The stored allocation ratchet still names the older Oct23 compiler, so its metadata check exits nonzero even though every measured count agrees.

roc-fuzz0.4.3 cannot report requested bytes or peak-live bytes. Those fields are null; timing peak RSS is recorded separately. The temporary bundle archives were pruned after serving, so their native content identifiers, rather than an invented archive SHA256, identify the exact source.
