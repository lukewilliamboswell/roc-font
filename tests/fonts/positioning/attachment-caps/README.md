Original UPL-licensed fonts isolate the pinned HarfBuzz14.6.0 limits for
attachment propagation (64 recursive propagation frames; the next call
clears its edge) and cursive rerooting (65 visited edges). Native traversal
order matters: RTL visits roots backwards. Regenerate with `generate.py`
using pinned fontTools. All three files pass OTS9.3.0. The108 cached cases
include both directions and cluster levels, boundaries62–66 and sizes8–257.
The real Nastaliq long-mark cases separately exercise the same propagation
limit in an unmodified production font.
