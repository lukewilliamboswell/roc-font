# Allocation compiler-flag comparison

`oct27-main.json` independently replays all 64 preserved main benchmark cases
on main commit `8befe25`, using the same Oct27 Roc compiler. The preserved
`--fuzz` binary and a new `--fuzz --opt=speed` binary agree on every allocation
count, leak count, result and checksum. Both also reproduce the preserved
dev records: 64 identical, zero different.

The new consumer imported the immutable bundle through `scripts/flight.py`;
source, compiler, binary and case hashes are recorded. The baseline package,
consumer and scripts were not edited. Read, cmap, advance, kerning, shape,
labels and plan-labels cover ordinary/corpus/adversarial cases, including
three increasing Inter shape and label sizes. This isolates the optimization
flag for this compiler and matrix; it does not prove invariance on every
Roc program or nightly.

This is an allocation comparison, not a timing measurement. Requested bytes
and peak live bytes are unavailable in roc-fuzz 0.4.3.
