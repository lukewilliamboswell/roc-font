# roc-font

A pure Roc font library: font file bytes in, metrics, glyphs and kerning
out. It needs no host, no system fonts and no file access, so it works the
same in a package, an app, a test or a browser.

**Status: pre-0.1.0. The API is provisional and will change.** The design
it is moving towards is described in `docs/architecture.adoc`.

Today it reads TrueType and OpenType (`glyf` or `CFF`) files and gives:

- units per em, ascent and descent;
- the glyph for each Unicode code point (character maps 4 and 12);
- each glyph's advance width and outline extent;
- pair kerning (`GPOS`, or the older `kern` table);
- the default ligatures and contextual forms (`GSUB`).

The bytes are never trusted: a file that cannot be used is reported with
every problem found, and every query on a font that was read succeeds.

## Example

```roc
import font.Font

# The width of "AV" in font units: advances plus kerning, after the
# font's default substitutions.
width : List(U8) -> Try(F64, List(Font.Problem))
width = |bytes| {
	font = Font.from_bytes(bytes)?
	missing = Font.glyph_total(font)
	items = [0x41, 0x56].map_with_index(|cp, i| { glyph: Font.glyph(font, cp) ?? missing, cluster: i })
	glyphs = Font.substitute(font, items).map(|item| item.glyph)
	advances = glyphs.map(|g| Font.advance(font, g))
	kerning = Font.kerning(font, glyphs)
	Ok(advances.concat(kerning).fold(0.0, |sum, x| sum + x))
}
```

Divide font units by `Font.units_per_em(font)` and multiply by the font
size to get pixels. Rounding to a pixel grid is left to the caller.

No font is bundled; pass the bytes of the font you use.

## Development

Checks run with the Roc nightly named in `.roc-version` (set `ROC` to its
`roc` binary if it is not first on your `PATH`).

```sh
python3 scripts/all_tests.py           # every check: fmt, check, tests, fuzz smoke, docs, bundle
python3 scripts/run_fuzz.py smoke      # just the fuzz targets in fuzz/
roc test tests/api/main.roc            # tests of the public API
```

Tests live in `tests/api/` and `tests/support/`, which `package/main.roc`
does not reach, so neither they nor the test fonts are part of the
published package.

## Licence

The package is under the Universal Permissive License 1.0 (`LICENSE`).
The test font `tests/fonts/Inter-Regular-metrics.ttf` is a metrics-only
copy of Inter, under the SIL Open Font License 1.1
(`tests/fonts/Inter-OFL.txt`).
