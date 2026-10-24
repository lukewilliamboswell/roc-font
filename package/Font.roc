import LayoutGsub
import LayoutKerning
import Sfnt
import TableCmap
import TableGlyf
import TableHead
import TableHhea
import TableHmtx
import TableMaxp
import TableOs2

## What text measurement needs from a TrueType or OpenType font file: each
## glyph's advance width and the horizontal extent of its outline, which
## glyph draws each character, the default ligatures and contextual forms,
## pair kerning, and the font's ascent and descent. Outlines are not kept.
##
## `from_bytes` reads any font file and reports what is wrong with one it
## cannot use; the bytes are never trusted. No font is built in: callers
## supply the bytes of the font they use.
##
## All lengths are in font units; divide by `units_per_em` and multiply by
## the font size for pixels.
Font := {
	units_per_em : F64,
	ascent : F64,
	descent : F64,
	advances : List(U16),
	ink : List({ left : I16, right : I16 }),
	cmap : TableCmap,
	kerning : LayoutKerning,
	shaping : LayoutGsub,
}.{

	## Why bytes could not be read as a font. `NotAFont` covers files that are
	## too short, have an unknown signature, or are font collections.
	## `MissingTable` and `BadTable` name the table (`head`, `hhea`, `maxp`,
	## `hmtx`, `cmap`, `OS/2`, `loca`, `glyf`, `GSUB`, `GPOS` or `kern`); a bad table
	## extends past the file or has an internal offset or count that does not
	## fit. `NoUnicodeMapping` means the font has no character map this
	## reader can use: one for Unicode, a Windows symbol map or a Macintosh
	## map, in format 0, 4, 6, 10, 12 or 13.
	Problem : [NotAFont, MissingTable(Str), BadTable(Str), BadUnitsPerEm, NoUnicodeMapping]

	empty : Font
	empty = { units_per_em: 1000.0, ascent: 0.0, descent: 0.0, advances: [0], ink: [{ left: 0, right: 0 }], cmap: TableCmap.none, kerning: LayoutKerning.none, shaping: LayoutGsub.none }

	units_per_em : Font -> F64
	units_per_em = |font| font.units_per_em

	## Height above the baseline, in font units.
	ascent : Font -> F64
	ascent = |font| font.ascent

	## Depth below the baseline, in font units (positive).
	descent : Font -> F64
	descent = |font| font.descent

	## The glyph that draws a Unicode code point, if the font has one. Fonts
	## whose character map is not in Unicode (old symbol fonts and Macintosh
	## fonts) are translated to Unicode the way HarfBuzz does; a symbol font's
	## characters are found at U+0020 to U+00FF as well as at U+F020 to
	## U+F0FF.
	glyph : Font, U32 -> Try(U64, [Missing])
	glyph = |font, code_point| TableCmap.glyph(font.cmap, code_point, font.advances.len())

	## How many glyphs the font has; glyph indices run below this.
	glyph_total : Font -> U64
	glyph_total = |font| font.advances.len()

	## A glyph's advance width. Indices past the last glyph have none.
	advance : Font, U64 -> F64
	advance = |font, index| (font.advances.get(index) ?? 0).to_f64()

	## The horizontal extent of a glyph's outline, or `NoInk` for a glyph that
	## draws nothing (such as a space) or a font without TrueType outlines.
	ink : Font, U64 -> [Ink({ left : F64, right : F64 }), NoInk]
	ink = |font, index|
		match font.ink.get(index) {
			Ok(box) if box.left <= box.right => Ink({ left: box.left.to_f64(), right: box.right.to_f64() })
			_ => NoInk
		}

	## Kerning for a run of glyphs, as the change to each glyph's advance. Each
	## kerning lookup runs over the whole run in order and its adjustments add
	## up, as a shaping engine applies the `kern` feature.
	kerning : Font, List(U64) -> List(F64)
	kerning = |font, glyphs| LayoutKerning.adjust(font.kerning, glyphs, font.advances.len())

	## Read a font file. Every independent problem is reported.
	from_bytes : List(U8) -> Try(Font, List(Problem))
	from_bytes = |bytes| {
		match Sfnt.directory(bytes) {
			Err(problem) => Err([problem])
			Ok(tables) => {
				head = TableHead.from_tables(bytes, tables)
				hhea = TableHhea.from_tables(bytes, tables)
				maxp = TableMaxp.from_tables(bytes, tables)
				cmap = TableCmap.from_tables(bytes, tables)
				os2 = TableOs2.from_tables(bytes, tables)
				var $problems = []
				$problems = Sfnt.collect($problems, head)
				$problems = Sfnt.collect($problems, hhea)
				$problems = Sfnt.collect($problems, maxp)
				$problems = Sfnt.collect($problems, cmap)
				$problems = Sfnt.collect($problems, os2)
				match (head, hhea, maxp) {
					(Ok(h), Ok(hh), Ok(count_of_glyphs)) => {
						advances = TableHmtx.from_tables(bytes, tables, hh.metric_count, count_of_glyphs)
						extents = TableGlyf.from_tables(bytes, tables, h.long_offsets, count_of_glyphs)
						pairs = LayoutKerning.from_tables(bytes, tables, count_of_glyphs)
						shaping = LayoutGsub.from_tables(bytes, tables)
						$problems = Sfnt.collect($problems, shaping)
						$problems = Sfnt.collect($problems, advances)
						$problems = Sfnt.collect($problems, extents)
						$problems = Sfnt.collect($problems, pairs)
						match (advances, extents, pairs, cmap, os2, shaping) {
							(Ok(a), Ok(i), Ok(k), Ok(c), Ok(o), Ok(sh)) if $problems.is_empty() => {
								lines = TableOs2.vertical(hh, o)
								Ok({
									units_per_em: h.units_per_em,
									ascent: lines.ascent,
									descent: lines.descent,
									advances: a,
									ink: i,
									cmap: c,
									kerning: k,
									shaping: sh,
								})
							}
							_ => Err($problems)
						}
					}
					_ => Err($problems)
				}
			}
		}
	}

	## The glyphs that draw a run after the font's default substitutions
	## (ligatures and contextual forms). Each glyph keeps the index of the
	## first character it draws.
	substitute : Font, List({ glyph : U64, cluster : U64 }) -> List({ glyph : U64, cluster : U64 })
	substitute = |font, items| LayoutGsub.apply(font.shaping, items)
}
