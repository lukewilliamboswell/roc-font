Original fonts licensed under the adjacent UPL licence. With pinned fontTools,
run `generate.py` and `generate_win1256.py` to reproduce their exact bytes and
case data. Every file passes OTS9.3.0.

The first matrix isolates presentation forms and every ligature in the pinned
HarfBuzz14.6.0 fallback table, including historical private-use mappings.
Partial GSUB and missing-form fonts test fallback activation boundaries.

The Windows matrix isolates the exact legacy glyph-order heuristic, all five
hardcoded lookups, failed heuristic controls and Unicode-fallback precedence.
The fallback table is generated from committed SHA256-pinned HarfBuzz sources
by `tools/ucd/generate_arabic_fallback.py --check`; full required notices are
embedded in its regular source comments.

Cached reference records are adjacent JSONL files, replayed through the public
native driver. These fonts are deliberately geometric test fixtures, with no
claim to typographic design or real-font coverage.
