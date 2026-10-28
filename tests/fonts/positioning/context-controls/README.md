These original UPL-licensed fonts isolate GPOS context (type7) and chained
context (type8) matching. Regenerate with the pinned oracle Python:

    /path/to/oracle/bin/python generate.py

All five fonts pass OTS9.3.0. Cached HarfBuzz14.6.0 records in
`tests/oracle/records/position-context-controls.jsonl` cover both cluster levels
and show glyph flags. Manual-ZWJ mark-feature **input** matching rejects a ZWJ;
mark backtrack and lookahead matching ignore it. Automatic dist inputs ignore
ZWJ. Both input modes ignore ZWNJ and hidden CGJ during positioning. The
fixture's controls have zero advances and ordinary Latin letters have600.

The context variant is converted from the same valid format3 chained rule to
format3 ContextPos; its two inputs include a second input without a nested
record. This prevents accidentally testing lookahead when intending input.
The parent `LICENSE` applies to the generator and original fonts.
