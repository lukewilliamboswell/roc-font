These two original UPL fonts isolate an unresolved reference discrepancy.
Both pass OTS9.3 with every Graphite table retained. They have proper Silf5.0
headers, long class offsets, all three long horizontal metrics, a strong
RTL glyph advancing601, and a font-defined NSM glyph advancing0.

Their only action block is COPY_NEXT, RET_ZERO (1b31 hex): copy the current
input unchanged, move forward, and return0. It has no geometry or attachment
writes and makes progress, so no nonprogress/max-loop inference is needed. The two
programs differ only in the pass reverse-direction flag. The public
Graphite2 1.3.14 C API returns two unattached, unshifted slots with authored
advances601/0 in both. Its segment advance is601 without the flag and0
with it. True HB14.6 Graphite answers agree; explicit OpenType controls
retain width601 for both fonts. `record_raw.py --check` independently
checks the bytecode and hmtx facts from the checked SFNT bytes.

These are reviewable evidence, not a declared divergence or a font-specific
workaround. The complete NSM matrix retains the exact reference answers as
a failing gate until the direction/positioning contract is resolved.
