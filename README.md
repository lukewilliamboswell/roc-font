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

# The width of "AV" in font units, shaped with the browser default
# features (ligatures, contextual forms and kerning).
width : List(U8) -> Try(I32, List(Font.Problem))
width = |bytes| {
	font = Font.from_bytes(bytes, Font.ReadOptions.{})?
	Ok(Font.width(font, "AV"))
}

# Glyphs, their advances and offsets, and the UTF-8 byte offset of the text
# each draws, for Bold text in English.
shaped : List(U8) -> Try(Font.Run, List(Font.Problem))
shaped = |bytes| {
	font = Font.at(Font.from_bytes(bytes, Font.ReadOptions.{})?, Font.Variation.{ weight: Bold })
	Ok(Font.shape(font, "office -> home", Font.ShapeOptions.{ script: "Latn", language: "en" }))
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
