import Bytes
import FontShape
import LayoutKerning
import TableCmap

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
	shaping : FontShape,
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
	empty = { units_per_em: 1000.0, ascent: 0.0, descent: 0.0, advances: [0], ink: [{ left: 0, right: 0 }], cmap: TableCmap.none, kerning: LayoutKerning.none, shaping: FontShape.none }

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
		match Font.directory(bytes) {
			Err(problem) => Err([problem])
			Ok(tables) => {
				head = Font.read_head(bytes, tables)
				hhea = Font.read_hhea(bytes, tables)
				maxp = Font.read_maxp(bytes, tables)
				cmap = Font.read_cmap(bytes, tables)
				os2 = Font.read_os2(bytes, tables)
				var $problems = []
				$problems = Font.collect($problems, head)
				$problems = Font.collect($problems, hhea)
				$problems = Font.collect($problems, maxp)
				$problems = Font.collect($problems, cmap)
				$problems = Font.collect($problems, os2)
				match (head, hhea, maxp) {
					(Ok(h), Ok(hh), Ok(count_of_glyphs)) => {
						advances = Font.read_hmtx(bytes, tables, hh.metric_count, count_of_glyphs)
						extents = Font.read_ink(bytes, tables, h.long_offsets, count_of_glyphs)
						pairs = Font.read_kerning(bytes, tables, count_of_glyphs)
						shaping = Font.read_shaping(bytes, tables)
						$problems = Font.collect($problems, shaping)
						$problems = Font.collect($problems, advances)
						$problems = Font.collect($problems, extents)
						$problems = Font.collect($problems, pairs)
						match (advances, extents, pairs, cmap, os2, shaping) {
							(Ok(a), Ok(i), Ok(k), Ok(c), Ok(o), Ok(sh)) if $problems.is_empty() => {
								lines = Font.vertical(hh, o)
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

	collect : List(Problem), Try(a, Problem) -> List(Problem)
	collect = |problems, result|
		match result {
			Ok(_) => problems
			Err(problem) => problems.append(problem)
		}

	# Ascent and descent as a browser takes them: the typographic values when
	# the font asks for them (`USE_TYPO_METRICS`), else `hhea`, else the
	# typographic values, else the Windows ones.
	vertical : { ascent : F64, descent : F64, metric_count : U64 }, [Present({ use_typo : Bool, typo_ascent : F64, typo_descent : F64, win_ascent : F64, win_descent : F64 }), Absent] -> { ascent : F64, descent : F64 }
	vertical = |hhea, os2|
		match os2 {
			Present(o) if o.use_typo => { ascent: o.typo_ascent, descent: -o.typo_descent }
			_ if hhea.ascent != 0.0 or hhea.descent != 0.0 => { ascent: hhea.ascent, descent: -hhea.descent }
			Present(o) if o.typo_ascent != 0.0 or o.typo_descent != 0.0 => { ascent: o.typo_ascent, descent: -o.typo_descent }
			Present(o) => { ascent: o.win_ascent, descent: o.win_descent }
			Absent => { ascent: 0.0, descent: 0.0 }
		}

	# ------------------------------------------------------------ bytes

	Table : { tag : U64, offset : U64, length : U64 }

	directory : List(U8) -> Try(List(Table), Problem)
	directory = |bytes| {
		version = Bytes.u32(bytes, 0)
		count = Bytes.u16(bytes, 4)
		if bytes.len() < 12 or (version != 0x00010000 and version != 0x74727565 and version != 0x4F54544F) {
			Err(NotAFont)
		} else if !Bytes.fits(12, 16 * count, bytes.len()) {
			Err(NotAFont)
		} else {
			var $tables = List.with_capacity(count)
			for i in 0..<count {
				at = 12 + 16 * i
				$tables = $tables.append({ tag: Bytes.u32(bytes, at), offset: Bytes.u32(bytes, at + 8), length: Bytes.u32(bytes, at + 12) })
			}
			Ok($tables)
		}
	}

	# A table's bytes, checked to lie inside the file and to hold at least
	# `minimum` bytes.
	table : List(U8), List(Table), Str, U64 -> [Found(List(U8)), Missing, Bad]
	table = |bytes, tables, name, minimum| {
		tag = Font.tag_of(name)
		match tables.find_first(|t| t.tag == tag) {
			Err(_) => Missing
			Ok(t) =>
				if Bytes.fits(t.offset, t.length, bytes.len()) and t.length >= minimum {
					Found(bytes.sublist({ start: t.offset, len: t.length }))
				} else {
					Bad
				}
		}
	}

	tag_of : Str -> U64
	tag_of = |name| name.to_utf8().fold(0, |acc, b| acc * 256 + b.to_u64())

	required : List(U8), List(Table), Str, U64 -> Try(List(U8), Problem)
	required = |bytes, tables, name, minimum|
		match Font.table(bytes, tables, name, minimum) {
			Found(data) => Ok(data)
			Missing => Err(MissingTable(name))
			Bad => Err(BadTable(name))
		}

	# ------------------------------------------------------------ tables

	read_head : List(U8), List(Table) -> Try({ units_per_em : F64, long_offsets : Bool }, Problem)
	read_head = |bytes, tables| {
		head = Font.required(bytes, tables, "head", 54)?
		units = Bytes.u16(head, 18)
		if units < 16 or units > 16384 {
			Err(BadUnitsPerEm)
		} else {
			Ok({ units_per_em: units.to_f64(), long_offsets: Bytes.i16(head, 50) == 1 })
		}
	}

	read_hhea : List(U8), List(Table) -> Try({ ascent : F64, descent : F64, metric_count : U64 }, Problem)
	read_hhea = |bytes, tables| {
		hhea = Font.required(bytes, tables, "hhea", 36)?
		count = Bytes.u16(hhea, 34)
		if count == 0 {
			Err(BadTable("hhea"))
		} else {
			Ok({ ascent: Bytes.i16(hhea, 4).to_f64(), descent: Bytes.i16(hhea, 6).to_f64(), metric_count: count })
		}
	}

	read_maxp : List(U8), List(Table) -> Try(U64, Problem)
	read_maxp = |bytes, tables| {
		maxp = Font.required(bytes, tables, "maxp", 6)?
		count = Bytes.u16(maxp, 4)
		if (count == 0) Err(BadTable("maxp")) else Ok(count)
	}

	read_os2 : List(U8), List(Table) -> Try([Present({ use_typo : Bool, typo_ascent : F64, typo_descent : F64, win_ascent : F64, win_descent : F64 }), Absent], Problem)
	read_os2 = |bytes, tables|
		match Font.table(bytes, tables, "OS/2", 78) {
			Missing => Ok(Absent)
			Bad => Err(BadTable("OS/2"))
			Found(os2) =>
				Ok(
					Present({
						use_typo: Bytes.u16(os2, 62).bitwise_and(0x80) != 0,
						typo_ascent: Bytes.i16(os2, 68).to_f64(),
						typo_descent: Bytes.i16(os2, 70).to_f64(),
						win_ascent: Bytes.u16(os2, 74).to_f64(),
						win_descent: Bytes.u16(os2, 76).to_f64(),
					}),
				)
		}

	read_hmtx : List(U8), List(Table), U64, U64 -> Try(List(U16), Problem)
	read_hmtx = |bytes, tables, metric_count, count_of_glyphs| {
		long = metric_count.min(count_of_glyphs)
		hmtx = Font.required(bytes, tables, "hmtx", 4 * long)?
		var $advances = List.with_capacity(count_of_glyphs)
		for g in 0..<count_of_glyphs {
			at = 4 * g.min(long - 1)
			$advances = $advances.append(Bytes.u16(hmtx, at).to_u16_wrap())
		}
		Ok($advances)
	}

	# Outline extents from the TrueType glyph headers; a font without them
	# (CFF outlines) has no ink extents.
	read_ink : List(U8), List(Table), Bool, U64 -> Try(List({ left : I16, right : I16 }), Problem)
	read_ink = |bytes, tables, long_offsets, count_of_glyphs| {
		none = { left: 1, right: 0 }
		match (Font.table(bytes, tables, "loca", 0), Font.table(bytes, tables, "glyf", 0)) {
			(Bad, _) => Err(BadTable("loca"))
			(_, Bad) => Err(BadTable("glyf"))
			(Found(loca), Found(glyf)) => {
				size = if (long_offsets) 4 else 2
				if !Bytes.fits(0, size * (count_of_glyphs + 1), loca.len()) {
					Err(BadTable("loca"))
				} else {
					offset = |g| if (long_offsets) Bytes.u32(loca, 4 * g) else 2 * Bytes.u16(loca, 2 * g)
					var $ink = List.with_capacity(count_of_glyphs)
					var $bad = False
					for g in 0..<count_of_glyphs {
						start = offset(g)
						end = offset(g + 1)
						if end < start or end > glyf.len() {
							$bad = True
							$ink = $ink.append(none)
						} else if end - start >= 10 {
							$ink = $ink.append({ left: Bytes.i16(glyf, start + 2).to_i16_wrap(), right: Bytes.i16(glyf, start + 6).to_i16_wrap() })
						} else {
							$ink = $ink.append(none)
						}
					}
					if ($bad) Err(BadTable("loca")) else Ok($ink)
				}
			}
			_ => Ok(List.repeat(none, count_of_glyphs))
		}
	}

	# The character map; see `TableCmap` for which subtable is chosen. A
	# symbol map's encoding depends on the Windows 3.1 font page of a version
	# 0 `OS/2` table (the high byte of `fsSelection`).
	read_cmap : List(U8), List(Table) -> Try(TableCmap, Problem)
	read_cmap = |bytes, tables| {
		cmap = Font.required(bytes, tables, "cmap", 4)?
		page = match Font.table(bytes, tables, "OS/2", 78) {
			Found(os2) if Bytes.u16(os2, 0) == 0 => Bytes.u16(os2, 62).bitwise_and(0xFF00)
			_ => 0
		}
		match TableCmap.read(cmap, page) {
			Ok(map) => Ok(map)
			Err(NoUnicodeMapping) => Err(NoUnicodeMapping)
			Err(Bad) => Err(BadTable("cmap"))
		}
	}

	read_shaping : List(U8), List(Table) -> Try(FontShape, Problem)
	read_shaping = |bytes, tables|
		match Font.table(bytes, tables, "GSUB", 10) {
			Missing => Ok(FontShape.none)
			Bad => Err(BadTable("GSUB"))
			Found(gsub) => FontShape.read(gsub).map_err(|_| BadTable("GSUB"))
		}

	## The glyphs that draw a run after the font's default substitutions
	## (ligatures and contextual forms). Each glyph keeps the index of the
	## first character it draws.
	substitute : Font, List({ glyph : U64, cluster : U64 }) -> List({ glyph : U64, cluster : U64 })
	substitute = |font, items| FontShape.apply(font.shaping, items)

	# ------------------------------------------------------------ kerning

	# Pair kerning from the `kern` feature of `GPOS`, or, for a font without
	# `GPOS`, from a TrueType `kern` table.
	read_kerning : List(U8), List(Table), U64 -> Try(LayoutKerning, Problem)
	read_kerning = |bytes, tables, count_of_glyphs|
		match Font.table(bytes, tables, "GPOS", 10) {
			Bad => Err(BadTable("GPOS"))
			Found(gpos) => LayoutKerning.read_gpos(gpos, count_of_glyphs).map_err(|_| BadTable("GPOS"))
			Missing =>
				match Font.table(bytes, tables, "kern", 4) {
					Bad => Err(BadTable("kern"))
					Found(kern) => LayoutKerning.read_kern(kern).map_err(|_| BadTable("kern"))
					Missing => Ok(LayoutKerning.none)
				}
		}
}
