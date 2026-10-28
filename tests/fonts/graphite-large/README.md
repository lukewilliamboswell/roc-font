This original UPL fixture changes glyph2's hmtx advance to65535 in the original
raw-bounds metric fixture. Text containing only `b` never matches its `ab`
font rule. Five lengths32767–32771 cross the signed32 cumulative position
boundary without a large font or an illegal font-program operand.

The reference is HarfBuzz14.6.0's actual Graphite2 adapter. Its final conversions
use `hb_clamp_to<hb_position_t>`, with `hb_saturate_add/sub` for integer pens
([primary source](https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/hb-graphite2.cc#L427)).
This is a defined output conversion, not a repair of invalid font bytes.

`records.json` retains complete-run SHA256 hashes over big-endian
`glyph:U32,cluster:U32,advanceX:I32,advanceY:I32,offsetX:I32,offsetY:I32`,
a separate SHA256 over every unsafe-break flag, signed64 advance totals and
the first/last three rows. It records reference library and font hashes. All
five full-row hashes also match the independent original contract-audit probe.
`verify.py` receives every native JSON glyph row and checks its complete hash;
it does not test only the displayed samples. No reference library is needed.

```
python tests/fonts/graphite-large/record.py --check
python tests/fonts/graphite-large/verify.py --binary /path/to/graphite/query
```

Regenerate the font with pinned fontTools using `generate.py --check`, and
re-record only with the pinned HB14.6/Graphite2 build using `record.py`.
