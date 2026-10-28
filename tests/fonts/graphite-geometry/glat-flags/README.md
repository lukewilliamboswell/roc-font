# Original Glat3 flag/header controls

These four UPL fonts independently vary the Glat3 `hasOctaboxes` flag and an
actual six-byte octabox prefix. Each executes documented PushGlyphAttr1 into
advanceX. The authored attribute run gives attribute1 value1. The layout uses
no collision pass, so a valid flag0 table needs no box geometry.

The format-correct flag0/no-header font is decoded by fontTools4.61.1 as
attribute1=1, with no octaboxes. Graphite2 1.3.14's public API returns advance0.
With a header, Graphite2 returns1 whether the flag is0 or1. The no-header
flag1 control also returns0. All four reference faces and segments are accepted.
These are distinguishing raw observations, including intentionally mismatched
flag/header controls, rather than a reason to reject the valid flag0 font.

roc-font preserves the format flag: absent octaboxes are explicit absent
geometry. The valid flag0/no-header case follows decoded font facts and therefore
deliberately differs from the pinned Graphite2 result. `fonttools.json` and
`records.json` preserve both independent oracles. No Graphite2 implementation
source was opened or used.

Reproduce from the repository root:

```
python tests/fonts/graphite-geometry/glat-flags/generate.py --check
python tests/fonts/graphite-geometry/record.py --cases glat-flags/cases.jsonc --output glat-flags/records.json --check
python tests/fonts/graphite-geometry/record_fonttools.py --cases glat-flags/cases.jsonc --output glat-flags/fonttools.json --check
```

The generator uses the parent directory's original builder; its UPL license
applies to these font programs and generated files.
