import Font
import FontTest
import "../tests/fonts/Inter-Regular-metrics.ttf" as inter_file : List(U8)

## The tests of `Font`. Test-only: `main.roc` does not import this module, so
## neither it nor the Inter test font is part of the published package. Run
## with `roc test package/FontTests.roc`.
FontTests :: {}.{}

# Inter Regular (version 4, SIL Open Font License 1.1), as a metrics-only
# file: its outlines are reduced to their bounding boxes. See
# `tests/fonts/Inter-OFL.txt`.
inter : Font
inter = match Font.from_bytes(inter_file) {
	Ok(font) => font
	# The file is checked by the first test below.
	Err(_) => Font.empty
}

expect
	match Font.from_bytes(inter_file) {
		Ok(font) => Font.glyph_total(font) == 2937 and Font.units_per_em(font) == 2048.0
		Err(_) => False
	}

expect
	match Font.from_bytes([]) {
		Err(problems) => problems == [NotAFont]
		Ok(_) => False
	}

expect
	match Font.from_bytes([0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) {
		Err(problems) => problems == [MissingTable("head"), MissingTable("hhea"), MissingTable("maxp"), MissingTable("cmap")]
		Ok(_) => False
	}

# Inter's default substitutions: `->` becomes one arrow glyph, and an
# asterisk after a capital is raised.
expect Font.substitute(inter, [{ glyph: 1459, cluster: 0 }, { glyph: 1517, cluster: 1 }]) == [{ glyph: 1805, cluster: 0 }]
expect Font.substitute(inter, [{ glyph: 137, cluster: 0 }, { glyph: 1547, cluster: 1 }]) == [{ glyph: 137, cluster: 0 }, { glyph: 1548, cluster: 1 }]
expect Font.substitute(inter, [{ glyph: 993, cluster: 0 }]) == [{ glyph: 993, cluster: 0 }]

# A truncated file: its tables run past the end.
expect
	match Font.from_bytes(inter_file.take_first(4096)) {
		Err(problems) => !problems.is_empty() and problems.all(|p| p != NotAFont)
		Ok(_) => False
	}

# Every byte of a font corrupted in turn never crashes reading.
expect {
	var $read = 0
	for k in 0..<16 {
		at = (k * 9973 + 12) % inter_file.len()
		match Font.from_bytes(inter_file.set(at, 0xFF) ?? inter_file) {
			Ok(_) => {
				$read = $read + 1
			}
			Err(problems) => {
				$read = $read + (if (problems.is_empty()) 100 else 1)
			}
		}
	}
	$read == 16
}

# ------------------------------------------------------------ test helpers
#
# Synthetic fonts are built from `FontTest.basic`: four glyphs (0 missing,
# 1 `A`, 2 `B`, 3 `C`) with advances 500 to 800 and 1000 units per em.

read_tables : List({ tag : Str, data : List(U8) }) -> Try(Font, List(Font.Problem))
read_tables = |tables| Font.from_bytes(FontTest.file(tables))

problems_of : List({ tag : Str, data : List(U8) }) -> List(Font.Problem)
problems_of = |tables|
	match read_tables(tables) {
		Ok(_) => []
		Err(found) => found
	}

# `basic` with one table replaced or added.
basic_with : Str, List(U8) -> List({ tag : Str, data : List(U8) })
basic_with = |tag, data| FontTest.replace(FontTest.basic, tag, data)

# The glyph of each code point, 9999 where the font has none.
glyphs_for : List({ tag : Str, data : List(U8) }), List(U32) -> List(U64)
glyphs_for = |tables, code_points|
	match read_tables(tables) {
		Ok(font) => code_points.map(|cp| Font.glyph(font, cp) ?? 9999)
		Err(_) => []
	}

# A font whose only character map is the given subtable.
cmap_only : U64, U64, List(U8) -> List({ tag : Str, data : List(U8) })
cmap_only = |system, encoding, subtable| basic_with("cmap", FontTest.cmap([{ system, encoding, subtable }]))

kerning_of : List({ tag : Str, data : List(U8) }), List(U64) -> List(F64)
kerning_of = |tables, glyphs|
	match read_tables(tables) {
		Ok(font) => Font.kerning(font, glyphs)
		Err(_) => [9999.0]
	}

# A `GPOS` table whose `kern` feature uses every lookup given.
gpos : List({ kind : U64, subtables : List(List(U8)) }) -> List(U8)
gpos = |lookups| FontTest.layout("DFLT", [{ tag: "kern", lookups: FontTest.counting(lookups.len()) }], lookups)

# Pairs (1, 2) -50 and (1, 3) -30, and (2, 1) +20, x advance of the first
# glyph only.
simple_pairs : List(U8)
simple_pairs = FontTest.pair1(4, 0, [{ glyph: 1, pairs: [{ second: 2, values: [-50] }, { second: 3, values: [-30] }] }, { glyph: 2, pairs: [{ second: 1, values: [20] }] }])

# ------------------------------------------------------------ reading a font

# The minimal font: metrics, glyph count and advances. Without `OS/2` the
# vertical metrics come from `hhea`; without `loca`/`glyf` nothing has ink.
expect {
	match read_tables(FontTest.basic) {
		Ok(font) =>
			Font.glyph_total(font) == 4
				and Font.units_per_em(font) == 1000.0
				and Font.ascent(font) == 800.0
				and Font.descent(font) == 200.0
				and [0, 1, 2, 3, 4, 1000000].map(|g| Font.advance(font, g)) == [500.0, 600.0, 700.0, 800.0, 0.0, 0.0]
				and [0, 1, 3].all(|g| Font.ink(font, g) == NoInk)
				and Font.kerning(font, [1, 2, 3]) == [0.0, 0.0, 0.0]
				and Font.substitute(font, [{ glyph: 1, cluster: 0 }]) == [{ glyph: 1, cluster: 0 }]
		Err(_) => False
	}
}

# Reading is deterministic.
expect FontTest.file(FontTest.basic) == FontTest.file(FontTest.basic)
expect {
	bytes = FontTest.file(FontTest.basic)
	match (Font.from_bytes(bytes), Font.from_bytes(bytes)) {
		(Ok(a), Ok(b)) => a.advances == b.advances and a.ranges == b.ranges and a.ink == b.ink and a.ascent == b.ascent
		_ => False
	}
}

# ------------------------------------------------------------ cmap format 4

# Delta segments: the first and last character of each segment map, the
# characters just outside do not.
expect {
	cmap = FontTest.cmap4([{ first: 0x20, last: 0x22, delta: 65536 - 0x1F, glyphs: [] }, { first: 0x30, last: 0x30, delta: 65536 - 0x2D, glyphs: [] }])
	glyphs_for(cmap_only(3, 1, cmap), [0x1F, 0x20, 0x21, 0x22, 0x23, 0x2F, 0x30, 0x31]) == [9999, 1, 2, 3, 9999, 9999, 3, 9999]
}

# Segments that map through a glyph array (idRangeOffset), with and without
# a delta, beside a delta segment; a zero entry leaves its character
# unmapped.
expect {
	cmap = FontTest.cmap4([
		{ first: 0x41, last: 0x42, delta: 1, glyphs: [1, 2] },
		{ first: 0x50, last: 0x50, delta: 65536 - 0x4F, glyphs: [] },
		{ first: 0x61, last: 0x63, delta: 0, glyphs: [3, 0, 2] },
	])
	glyphs_for(cmap_only(3, 1, cmap), [0x40, 0x41, 0x42, 0x43, 0x50, 0x61, 0x62, 0x63, 0x64]) == [9999, 2, 3, 9999, 1, 3, 9999, 2, 9999]
}

# The delta wraps modulo 65536 at the top of the range; U+FFFF and code
# points beyond the Basic Multilingual Plane are never mapped by format 4.
expect {
	cmap = FontTest.cmap4([{ first: 0xFFFE, last: 0xFFFE, delta: 4, glyphs: [] }])
	glyphs_for(cmap_only(3, 1, cmap), [0xFFFD, 0xFFFE, 0xFFFF, 0x10000, 0x10FFFF]) == [9999, 2, 9999, 9999, 9999]
}

# Platform 0 (Unicode) is a Unicode mapping too.
expect glyphs_for(cmap_only(0, 3, FontTest.cmap4([{ first: 0x41, last: 0x41, delta: 65536 - 0x40, glyphs: [] }])), [0x41]) == [1]

# A character mapped to a glyph the font does not have is unmapped, and a
# run that only partly fits keeps the characters whose glyphs exist.
expect {
	cmap = FontTest.cmap4([{ first: 0x44, last: 0x44, delta: 65536 + 9 - 0x44, glyphs: [] }, { first: 0x45, last: 0x48, delta: 65536 + 2 - 0x45, glyphs: [] }])
	glyphs_for(cmap_only(3, 1, cmap), [0x44, 0x45, 0x46, 0x47, 0x48]) == [9999, 2, 3, 9999, 9999]
}

# Segments out of order are a bad table.
expect {
	cmap = FontTest.cmap4([{ first: 0x50, last: 0x51, delta: 0, glyphs: [] }, { first: 0x41, last: 0x42, delta: 0, glyphs: [] }])
	problems_of(cmap_only(3, 1, cmap)) == [BadTable("cmap")]
}

expect {
	cmap = FontTest.cmap4([{ first: 0x41, last: 0x45, delta: 0, glyphs: [] }, { first: 0x45, last: 0x46, delta: 0, glyphs: [] }])
	problems_of(cmap_only(3, 1, cmap)) == [BadTable("cmap")]
}

# A glyph array that runs past the end of the table.
expect {
	table = FontTest.cmap([{ system: 3, encoding: 1, subtable: FontTest.cmap4([{ first: 0x41, last: 0x43, delta: 0, glyphs: [1, 2, 3] }]) }])
	problems_of(basic_with("cmap", table.drop_last(2))) == [BadTable("cmap")]
}

# A segment count larger than the table.
expect {
	table = FontTest.cmap([{ system: 3, encoding: 1, subtable: FontTest.u16(4).concat(FontTest.u16(14)).concat(FontTest.u16(0)).concat(FontTest.u16(0xFFFE)).concat(List.repeat(0, 6)) }])
	problems_of(basic_with("cmap", table)) == [BadTable("cmap")]
}

# ------------------------------------------------------------ cmap format 12

expect {
	cmap = FontTest.cmap12([{ first: 0x41, last: 0x43, glyph: 1 }, { first: 0x1F600, last: 0x1F601, glyph: 2 }])
	glyphs_for(cmap_only(3, 10, cmap), [0x40, 0x41, 0x43, 0x44, 0x1F5FF, 0x1F600, 0x1F601, 0x1F602, 0x10FFFF]) == [9999, 1, 3, 9999, 9999, 2, 3, 9999, 9999]
}

# Groups whose glyphs run past the last glyph keep the glyphs that exist.
expect {
	cmap = FontTest.cmap12([{ first: 0x50, last: 0x55, glyph: 2 }, { first: 0x60, last: 0x60, glyph: 4 }])
	glyphs_for(cmap_only(3, 10, cmap), [0x50, 0x51, 0x52, 0x55, 0x60]) == [2, 3, 9999, 9999, 9999]
}

# The highest code point Unicode allows.
expect glyphs_for(cmap_only(0, 4, FontTest.cmap12([{ first: 0x10FFFF, last: 0x10FFFF, glyph: 3 }])), [0x10FFFF]) == [3]

# Format 12 is preferred to format 4, whatever the record order.
expect {
	table = FontTest.cmap([
		{ system: 3, encoding: 1, subtable: FontTest.cmap4([{ first: 0x41, last: 0x41, delta: 65536 - 0x40, glyphs: [] }]) },
		{ system: 3, encoding: 10, subtable: FontTest.cmap12([{ first: 0x41, last: 0x41, glyph: 2 }]) },
	])
	glyphs_for(basic_with("cmap", table), [0x41]) == [2]
}

expect problems_of(cmap_only(3, 10, FontTest.cmap12([{ first: 0x50, last: 0x55, glyph: 1 }, { first: 0x41, last: 0x42, glyph: 1 }]))) == [BadTable("cmap")]
expect problems_of(cmap_only(3, 10, FontTest.cmap12([{ first: 0x50, last: 0x55, glyph: 1 }, { first: 0x55, last: 0x56, glyph: 1 }]))) == [BadTable("cmap")]
expect problems_of(cmap_only(3, 10, FontTest.cmap12([{ first: 0x50, last: 0x4F, glyph: 1 }]))) == [BadTable("cmap")]
expect problems_of(cmap_only(3, 10, FontTest.cmap12([{ first: 0x10FFFF, last: 0x110000, glyph: 1 }]))) == [BadTable("cmap")]

# A huge group count is checked against the table before anything is
# allocated.
expect {
	subtable = FontTest.u16(12).concat(FontTest.u16(0)).concat(FontTest.u32(16)).concat(FontTest.u32(0)).concat(FontTest.u32(0xFFFFFFFF))
	problems_of(cmap_only(3, 10, subtable)) == [BadTable("cmap")]
}

# ------------------------------------------------------------ cmap selection

# No Unicode subtable: a Macintosh one, a format 12 one under an encoding
# that is not Unicode, a format 4 one under the full-repertoire encoding,
# an unknown format, an offset past the table, or no subtables at all.
expect problems_of(cmap_only(1, 0, FontTest.cmap4([{ first: 0x41, last: 0x41, delta: 0, glyphs: [] }]))) == [NoUnicodeMapping]
expect problems_of(cmap_only(3, 0, FontTest.cmap12([{ first: 0x41, last: 0x41, glyph: 1 }]))) == [NoUnicodeMapping]
expect problems_of(cmap_only(3, 10, FontTest.cmap4([{ first: 0x41, last: 0x41, delta: 0, glyphs: [] }]))) == [NoUnicodeMapping]
expect problems_of(cmap_only(3, 1, FontTest.u16(6).concat(List.repeat(0, 8)))) == [NoUnicodeMapping]
expect problems_of(basic_with("cmap", FontTest.u16(0).concat(FontTest.u16(1)).concat(FontTest.u16(3)).concat(FontTest.u16(1)).concat(FontTest.u32(5000)))) == [NoUnicodeMapping]
expect problems_of(basic_with("cmap", FontTest.u16(0).concat(FontTest.u16(0)))) == [NoUnicodeMapping]

# More encoding records than the table holds.
expect problems_of(basic_with("cmap", FontTest.u16(0).concat(FontTest.u16(3)).concat(List.repeat(0, 8)))) == [BadTable("cmap")]

# ------------------------------------------------------------ hmtx

# Glyphs past the long metrics take the last advance.
expect {
	match read_tables(FontTest.basic.map(|t| if (t.tag == "hhea") { tag: t.tag, data: FontTest.hhea(800, -200, 2) } else if (t.tag == "hmtx") { tag: t.tag, data: FontTest.hmtx([500, 600]).concat([0, 0, 0, 0]) } else t)) {
		Ok(font) => [0, 1, 2, 3, 4].map(|g| Font.advance(font, g)) == [500.0, 600.0, 600.0, 600.0, 0.0]
		Err(_) => False
	}
}

# One long metric covers every glyph.
expect {
	match read_tables(FontTest.basic.map(|t| if (t.tag == "hhea") { tag: t.tag, data: FontTest.hhea(800, -200, 1) } else if (t.tag == "hmtx") { tag: t.tag, data: FontTest.hmtx([432]) } else t)) {
		Ok(font) => [0, 1, 2, 3].map(|g| Font.advance(font, g)) == [432.0, 432.0, 432.0, 432.0]
		Err(_) => False
	}
}

# More long metrics than glyphs: only the glyphs' metrics are needed.
expect {
	match read_tables(basic_with("hhea", FontTest.hhea(800, -200, 60000))) {
		Ok(font) => Font.advance(font, 3) == 800.0
		Err(_) => False
	}
}

# The largest advance a font can hold.
expect {
	match read_tables(basic_with("hmtx", FontTest.hmtx([65535, 0, 1, 2]))) {
		Ok(font) => Font.advance(font, 0) == 65535.0
		Err(_) => False
	}
}

expect problems_of(basic_with("hmtx", FontTest.hmtx([500, 600, 700]))) == [BadTable("hmtx")]
expect problems_of(FontTest.without(FontTest.basic, "hmtx")) == [MissingTable("hmtx")]

# ------------------------------------------------------------ loca and glyf

outline_glyphs : List(List(U8))
outline_glyphs = [[], FontTest.outline(10, 490), [], FontTest.outline(-5, 700)]

with_outlines : Bool, { loca : List(U8), glyf : List(U8) } -> List({ tag : Str, data : List(U8) })
with_outlines = |long, tables|
	basic_with("head", FontTest.head(1000, long))
		.append({ tag: "loca", data: tables.loca })
		.append({ tag: "glyf", data: tables.glyf })

inks_of : List({ tag : Str, data : List(U8) }) -> List([Ink({ left : F64, right : F64 }), NoInk])
inks_of = |tables|
	match read_tables(tables) {
		Ok(font) => [0, 1, 2, 3, 4].map(|g| Font.ink(font, g))
		Err(_) => []
	}

# Glyph extents from short and from long offsets; glyphs without an
# outline, and glyph indices past the last glyph, have no ink.
expect inks_of(with_outlines(False, FontTest.outlines(outline_glyphs, False))) == [NoInk, Ink({ left: 10.0, right: 490.0 }), NoInk, Ink({ left: -5.0, right: 700.0 }), NoInk]
expect inks_of(with_outlines(True, FontTest.outlines(outline_glyphs, True))) == [NoInk, Ink({ left: 10.0, right: 490.0 }), NoInk, Ink({ left: -5.0, right: 700.0 }), NoInk]

# A glyph shorter than its header, and one whose extent is inverted.
expect inks_of(with_outlines(False, FontTest.outlines([[], [1, 2, 3, 4], FontTest.outline(5, 4), []], False))) == [NoInk, NoInk, NoInk, NoInk, NoInk]

# The `loca` format must match `head`: short offsets read as long ones
# run past the end of `loca`.
expect problems_of(with_outlines(True, FontTest.outlines(outline_glyphs, False))) == [BadTable("loca")]

# Too few offsets, an offset past `glyf`, and offsets that go backwards.
expect problems_of(with_outlines(False, { loca: FontTest.outlines(outline_glyphs, False).loca.drop_last(2), glyf: FontTest.outlines(outline_glyphs, False).glyf })) == [BadTable("loca")]
expect problems_of(with_outlines(False, { loca: [0, 0, 0, 5, 0, 5, 0, 10, 0, 11], glyf: FontTest.outlines(outline_glyphs, False).glyf })) == [BadTable("loca")]
expect problems_of(with_outlines(False, { loca: [0, 0, 0, 5, 0, 5, 0, 2, 0, 10], glyf: FontTest.outlines(outline_glyphs, False).glyf })) == [BadTable("loca")]

# `loca` without `glyf` (or the reverse) gives no extents.
expect inks_of(basic_with("loca", FontTest.outlines(outline_glyphs, False).loca)) == [NoInk, NoInk, NoInk, NoInk, NoInk]

# ------------------------------------------------------------ vertical metrics

vertical_of : List({ tag : Str, data : List(U8) }) -> { ascent : F64, descent : F64 }
vertical_of = |tables|
	match read_tables(tables) {
		Ok(font) => { ascent: Font.ascent(font), descent: Font.descent(font) }
		Err(_) => { ascent: -1.0, descent: -1.0 }
	}

expect vertical_of(basic_with("OS/2", FontTest.os2({ use_typo: True, typo_ascent: 900, typo_descent: -300, win_ascent: 1000, win_descent: 400 }))) == { ascent: 900.0, descent: 300.0 }
expect vertical_of(basic_with("OS/2", FontTest.os2({ use_typo: False, typo_ascent: 900, typo_descent: -300, win_ascent: 1000, win_descent: 400 }))) == { ascent: 800.0, descent: 200.0 }
expect vertical_of(FontTest.replace(basic_with("hhea", FontTest.hhea(0, 0, 4)), "OS/2", FontTest.os2({ use_typo: False, typo_ascent: 900, typo_descent: -300, win_ascent: 1000, win_descent: 400 }))) == { ascent: 900.0, descent: 300.0 }
expect vertical_of(FontTest.replace(basic_with("hhea", FontTest.hhea(0, 0, 4)), "OS/2", FontTest.os2({ use_typo: False, typo_ascent: 0, typo_descent: 0, win_ascent: 1000, win_descent: 400 }))) == { ascent: 1000.0, descent: 400.0 }
expect vertical_of(basic_with("hhea", FontTest.hhea(0, 0, 4))) == { ascent: 0.0, descent: 0.0 }

# ------------------------------------------------------------ problems

expect Font.from_bytes(List.repeat(0, 11)).is_err()
expect problems_of([]) == [MissingTable("head"), MissingTable("hhea"), MissingTable("maxp"), MissingTable("cmap")]

# Signatures: TrueType, `true` and `OTTO` are fonts; a collection is not.
expect {
	match Font.from_bytes(FontTest.u32(0x74727565).concat(FontTest.file(FontTest.basic).drop_first(4))) {
		Ok(_) => True
		Err(_) => False
	}
}
expect {
	match Font.from_bytes(FontTest.u32(0x4F54544F).concat(FontTest.file(FontTest.basic).drop_first(4))) {
		Ok(_) => True
		Err(_) => False
	}
}
expect {
	match Font.from_bytes(FontTest.u32(0x74746366).concat(FontTest.file(FontTest.basic).drop_first(4))) {
		Err(found) => found == [NotAFont]
		Ok(_) => False
	}
}

# A table directory longer than the file.
expect {
	match Font.from_bytes(FontTest.patch(FontTest.file(FontTest.basic), 4, FontTest.u16(200))) {
		Err(found) => found == [NotAFont]
		Ok(_) => False
	}
}

# Each required table missing on its own.
expect ["head", "hhea", "maxp", "cmap"].all(|tag| problems_of(FontTest.without(FontTest.basic, tag)) == [MissingTable(tag)])

# Without `head`, `hhea` or `maxp` the tables that depend on them are not
# read, so only the missing table is reported.
expect problems_of(FontTest.without(FontTest.basic.append({ tag: "GPOS", data: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] }), "maxp")) == [MissingTable("maxp")]

# Tables too short for their fields, and empty counts.
expect problems_of(basic_with("head", FontTest.head(1000, False).drop_last(1))) == [BadTable("head")]
expect problems_of(basic_with("hhea", FontTest.hhea(800, -200, 4).drop_last(1))) == [BadTable("hhea")]
expect problems_of(basic_with("hhea", FontTest.hhea(800, -200, 0))) == [BadTable("hhea")]
expect problems_of(basic_with("maxp", FontTest.maxp(0))) == [BadTable("maxp")]
expect problems_of(basic_with("maxp", [0, 0, 0, 0, 0])) == [BadTable("maxp")]
expect problems_of(basic_with("OS/2", FontTest.os2({ use_typo: False, typo_ascent: 0, typo_descent: 0, win_ascent: 0, win_descent: 0 }).take_first(77))) == [BadTable("OS/2")]
expect problems_of(basic_with("cmap", [0, 0, 0])) == [BadTable("cmap")]

# A table whose length runs past the end of the file.
expect {
	bytes = FontTest.file(FontTest.basic)
	# The first record is `head`; its length is at byte 12 + 12.
	match Font.from_bytes(FontTest.patch(bytes, 24, FontTest.u32(100000))) {
		Err(found) => found == [BadTable("head")]
		Ok(_) => False
	}
}
expect {
	bytes = FontTest.file(FontTest.basic)
	match Font.from_bytes(FontTest.patch(bytes, 20, FontTest.u32(0xFFFFFFFF))) {
		Err(found) => found == [BadTable("head")]
		Ok(_) => False
	}
}

# Units per em must lie in 16 to 16384.
expect problems_of(basic_with("head", FontTest.head(15, False))) == [BadUnitsPerEm]
expect problems_of(basic_with("head", FontTest.head(16385, False))) == [BadUnitsPerEm]
expect problems_of(basic_with("head", FontTest.head(0, False))) == [BadUnitsPerEm]
expect problems_of(basic_with("head", FontTest.head(16, False))) == []
expect problems_of(basic_with("head", FontTest.head(16384, False))) == []

# Independent problems are reported together, in table order.
expect {
	tables = FontTest.basic
		.map(
			|t|
				if t.tag == "head" {
					{ tag: t.tag, data: FontTest.head(1, False) }
				} else if t.tag == "hhea" {
					{ tag: t.tag, data: FontTest.hhea(1, 1, 0) }
				} else if t.tag == "cmap" {
					{ tag: t.tag, data: FontTest.cmap([{ system: 1, encoding: 0, subtable: FontTest.cmap4([]) }]) }
				} else {
					t
				},
		)
		.append({ tag: "OS/2", data: [0] })
	problems_of(tables) == [BadUnitsPerEm, BadTable("hhea"), NoUnicodeMapping, BadTable("OS/2")]
}

expect {
	tables = FontTest.basic
		.map(|t| if (t.tag == "hmtx") { tag: t.tag, data: [0, 1] } else t)
		.concat([{ tag: "GSUB", data: List.repeat(0xFF, 12) }, { tag: "GPOS", data: List.repeat(0xFF, 12) }, { tag: "loca", data: [0] }, { tag: "glyf", data: [] }])
	problems_of(tables) == [BadTable("GSUB"), BadTable("hmtx"), BadTable("loca"), BadTable("GPOS")]
}

# Every prefix of a font, and every byte of it set to 0 or 0xFF, is read or
# rejected with problems; nothing crashes.
full_font : List(U8)
full_font = {
	outlines = FontTest.outlines(outline_glyphs, False)
	FontTest.file(
		FontTest.basic.concat([
			{ tag: "OS/2", data: FontTest.os2({ use_typo: True, typo_ascent: 900, typo_descent: -300, win_ascent: 1000, win_descent: 400 }) },
			{ tag: "loca", data: outlines.loca },
			{ tag: "glyf", data: outlines.glyf },
			{ tag: "GPOS", data: gpos([{ kind: 2, subtables: [simple_pairs] }]) },
			{ tag: "GSUB", data: FontTest.layout("latn", [{ tag: "liga", lookups: [0] }], [{ kind: 4, subtables: [FontTest.pack([U16(1), Ref(FontTest.coverage1([1])), U16(1), Ref(FontTest.pack([U16(1), Ref(FontTest.pack([U16(3), U16(2), U16(2)]))]))])] }]) },
		]),
	)
}

expect {
	match Font.from_bytes(full_font) {
		Ok(font) =>
			Font.kerning(font, [1, 2]) == [-50.0, 0.0]
				and Font.substitute(font, [{ glyph: 1, cluster: 0 }, { glyph: 2, cluster: 1 }]) == [{ glyph: 3, cluster: 0 }]
				and Font.ascent(font) == 900.0
		Err(_) => False
	}
}

expect {
	var $outcomes = 0
	for n in 0..<full_font.len() {
		match Font.from_bytes(full_font.take_first(n)) {
			Ok(_) => {
				$outcomes = $outcomes + 1
			}
			Err(found) => {
				$outcomes = $outcomes + (if (found.is_empty()) 1000000 else 1)
			}
		}
	}
	$outcomes == full_font.len()
}

expect {
	var $outcomes = 0
	for at in 0..<full_font.len() {
		for value in [0, 0x7F, 0xFF] {
			match Font.from_bytes(full_font.set(at, value) ?? []) {
				Ok(font) => {
					# Queries on whatever was read are total.
					_ = Font.kerning(font, [0, 1, 2, 3, 70000])
					_ = Font.substitute(font, [{ glyph: 1, cluster: 0 }, { glyph: 2, cluster: 1 }, { glyph: 70000, cluster: 2 }])
					$outcomes = $outcomes + (if (Font.units_per_em(font) >= 16.0) 1 else 1000000)
				}
				Err(found) => {
					$outcomes = $outcomes + (if (found.is_empty()) 1000000 else 1)
				}
			}
		}
	}
	$outcomes == 3 * full_font.len()
}

# The sample font that seeds the fuzz targets reads, with every table in
# use: format 12 is preferred, metrics repeat past the long ones, `OS/2`
# typographic metrics apply, and `GPOS` overrides `kern`.
expect {
	match Font.from_bytes(FontTest.sample) {
		Ok(font) =>
			Font.glyph_total(font) == 40
				and Font.units_per_em(font) == 2048.0
				and Font.ascent(font) == 1800.0
				and Font.descent(font) == 400.0
				and [0x41, 0x5A, 0x61, 0x1F600].map(|cp| Font.glyph(font, cp) ?? 9999) == [1, 26, 9999, 30]
				and [0, 3, 39].map(|g| Font.advance(font, g)) == [1000.0, 1300.0, 1300.0]
				and [0, 1, 2].map(|g| Font.ink(font, g)) == [NoInk, Ink({ left: -4.0, right: 10.0 }), Ink({ left: -3.0, right: 20.0 })]
				and Font.kerning(font, [1, 2]) == [-61.0, 2.0]
				and Font.substitute(font, [7, 1, 2, 3].map_with_index(|glyph, cluster| { glyph, cluster })).map(|item| item.glyph) == [7, 11, 2, 3]
		Err(_) => False
	}
}

# The fonts the scaling fuzz target builds read, at every size.
expect {
	[[0, 1, 2, 3, 4, 5], [1, 2, 3, 4, 5, 0], [2, 4], [3, 3, 3], [5], []].all(
		|choices|
			[1, 2, 16].all(
				|copies|
					match Font.from_bytes(FontTest.scaled(choices, copies)) {
						Ok(font) => Font.glyph_total(font) == 16 + 4 * choices.len() * copies
						Err(_) => False
					},
			),
	)
}

# Patching bytes wraps positions to the length.
expect FontTest.mutate([1, 2, 3], [0, 0, 4, 9, 0, 0, 0, 7, 0, 0]) == [7, 9, 3]
expect FontTest.mutate([], [0, 0, 4, 9]) == []

# ------------------------------------------------------------ GPOS kerning

# Format 1: pairs listed per first glyph. Pairs not listed, and glyphs not
# covered, are not adjusted; an empty or single-glyph run has no pairs.
expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [simple_pairs] }])), [1, 2, 3, 1]) == [-50.0, 0.0, 0.0, 0.0]
expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [simple_pairs] }])), [2, 1, 3]) == [20.0, -30.0, 0.0]
expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [simple_pairs] }])), []) == []
expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [simple_pairs] }])), [1]) == [0.0]
expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [simple_pairs] }])), [1, 70000, 2]) == [0.0, 0.0, 0.0]

# The x advance is found after an x placement in the value record; other
# fields are ignored.
expect {
	subtable = FontTest.pair1(0x05 + 0x0A, 0, [{ glyph: 1, pairs: [{ second: 2, values: [7, 8, -40, 9] }] }])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2]) == [-40.0, 0.0]
}

# A record without an x advance adjusts nothing.
expect {
	subtable = FontTest.pair1(0x01, 0, [{ glyph: 1, pairs: [{ second: 2, values: [7] }] }])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2]) == [0.0, 0.0]
}

# With a value for the second glyph, the second glyph is adjusted and the
# pair after it is skipped.
expect {
	subtable = FontTest.pair1(4, 4, [{ glyph: 1, pairs: [{ second: 2, values: [-10, 5] }] }, { glyph: 2, pairs: [{ second: 3, values: [-7, 0] }] }])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 3, 1, 2]) == [-10.0, 5.0, 0.0, -10.0, 5.0]
}
expect {
	subtable = FontTest.pair1(4, 0, [{ glyph: 1, pairs: [{ second: 2, values: [-10] }] }, { glyph: 2, pairs: [{ second: 3, values: [-7] }] }])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 3]) == [-10.0, -7.0, 0.0]
}

# Format 2: classes. Glyph 1 is first class 0, glyphs 2 and 3 first class
# 1; glyphs 2 and 3 are second class 1, others second class 0.
class_pairs : List(U8)
class_pairs = FontTest.pair2(4, 0, FontTest.coverage1([1, 2, 3]), FontTest.classes1(1, [0, 1, 1]), FontTest.classes2([{ first: 2, last: 3, class: 1 }]), 2, 2, [0, -11, -22, -33])

expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [class_pairs] }])), [1, 2, 3, 1, 0, 1]) == [-11.0, -33.0, -22.0, 0.0, 0.0, 0.0]

# A first glyph outside the coverage is not adjusted, even when its class
# has values.
expect {
	subtable = FontTest.pair2(4, 0, FontTest.coverage1([2]), FontTest.classes1(1, [1, 1, 1]), FontTest.classes2([]), 2, 1, [0, -5])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 3]) == [0.0, -5.0, 0.0]
}

# A class past the class counts is not adjusted.
expect {
	subtable = FontTest.pair2(4, 0, FontTest.coverage1([1, 2]), FontTest.classes1(1, [0, 5]), FontTest.classes1(1, [7, 0, 0]), 1, 1, [-5])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 2, 1, 1]) == [-5.0, 0.0, 0.0, 0.0, 0.0]
}

# Format 2 with a second value record skips the pair after it.
expect {
	subtable = FontTest.pair2(4, 4, FontTest.coverage1([1, 2, 3]), FontTest.classes1(1, [0, 0, 0]), FontTest.classes1(1, [0, 0, 0]), 1, 1, [-3, 2])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 3]) == [-3.0, 2.0, 0.0]
}

# In a lookup, the first subtable that has the pair decides it; later
# lookups add to it.
expect {
	first = FontTest.pair1(4, 0, [{ glyph: 1, pairs: [{ second: 3, values: [-1] }] }])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [first, simple_pairs] }])), [1, 2, 1, 3]) == [-50.0, 20.0, -1.0, 0.0]
}
expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [simple_pairs] }, { kind: 2, subtables: [class_pairs] }])), [1, 2]) == [-61.0, 0.0]

# Extension lookups (type 9) hold their subtables behind a 32-bit offset.
expect kerning_of(basic_with("GPOS", gpos([{ kind: 9, subtables: [FontTest.extension(2, simple_pairs), FontTest.extension(2, class_pairs)] }])), [1, 2, 3]) == [-50.0, -33.0, 0.0]

# Lookups of other types, extensions of other types, and lookups of other
# features are not kerning.
expect kerning_of(basic_with("GPOS", gpos([{ kind: 1, subtables: [simple_pairs] }, { kind: 9, subtables: [FontTest.extension(4, simple_pairs)] }])), [1, 2]) == [0.0, 0.0]
expect kerning_of(basic_with("GPOS", FontTest.layout("DFLT", [{ tag: "mark", lookups: [0] }], [{ kind: 2, subtables: [simple_pairs] }])), [1, 2]) == [0.0, 0.0]

# Pair formats 1 and 2 with a coverage of format 2.
expect {
	subtable = FontTest.pack([U16(1), Ref(FontTest.coverage2([{ first: 1, last: 2, index: 0 }])), U16(4), U16(0), U16(2), Ref(FontTest.pack([U16(1), U16(3), I16(-9)])), Ref(FontTest.pack([U16(1), U16(3), I16(-8)]))])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 3, 2, 3]) == [-9.0, 0.0, -8.0, 0.0]
}

# A GPOS table takes precedence over a `kern` table.
expect kerning_of(basic_with("GPOS", gpos([])).append({ tag: "kern", data: FontTest.kern([{ coverage: 1, pairs: [{ left: 1, right: 2, value: -5 }] }]) }), [1, 2]) == [0.0, 0.0]

# Broken GPOS tables: a lookup index past the lookups, an unknown pair
# format, a coverage past the table, a truncated table, and pair sets that
# do not fit.
expect problems_of(basic_with("GPOS", FontTest.layout("DFLT", [{ tag: "kern", lookups: [3] }], [{ kind: 2, subtables: [simple_pairs] }]))) == [BadTable("GPOS")]
expect problems_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [FontTest.patch(simple_pairs, 0, FontTest.u16(3))] }]))) == [BadTable("GPOS")]
expect problems_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [FontTest.patch(simple_pairs, 2, FontTest.u16(60000))] }]))) == [BadTable("GPOS")]
expect problems_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [simple_pairs] }]).drop_last(3))) == [BadTable("GPOS")]
expect problems_of(basic_with("GPOS", [0, 1, 0, 0, 0, 10, 0, 10, 0, 10, 0, 0])) == []
expect problems_of(basic_with("GPOS", [0, 1, 0, 0, 0, 10, 0, 10, 0, 10])) == [BadTable("GPOS")]
expect problems_of(basic_with("GPOS", [0, 1, 0, 0, 0, 10, 0])) == [BadTable("GPOS")]

# A class grid larger than the table.
expect problems_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [FontTest.pair2(4, 0, FontTest.coverage1([1]), FontTest.classes1(1, [0]), FontTest.classes1(1, [0]), 100, 100, [])] }]))) == [BadTable("GPOS")]

## fuzz regression: a class grid whose value records are empty takes no
## bytes however many classes it has; it must not take time or memory in
## proportion to the 65535 x 65535 cells.
expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [FontTest.pair2(0, 0, FontTest.coverage1([1]), FontTest.classes1(1, [0]), FontTest.classes1(1, [0]), 65535, 65535, [])] }])), [1, 2]) == [0.0, 0.0]

# Coverage ranges that overlap are read as browsers read them, and are
# not expanded glyph by glyph: a few bytes of them could list billions of
# glyphs. A range that goes backwards covers nothing.
expect {
	ranges = List.repeat({ first: 0, last: 65535, index: 0 }, 20).append({ first: 9, last: 2, index: 0 })
	subtable = FontTest.pack([U16(1), Ref(FontTest.coverage2(ranges)), U16(4), U16(0), U16(0)])
	tables = basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }]))
	problems_of(tables) == [] and kerning_of(tables, [1, 2]) == [0.0, 0.0]
}
expect {
	set = FontTest.pack([U16(1), U16(2), I16(-9)])
	subtable = FontTest.pack([U16(1), Ref(FontTest.coverage2([{ first: 3, last: 1, index: 0 }, { first: 1, last: 1, index: 0 }])), U16(4), U16(0), U16(1), Ref(set)])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 3, 2]) == [-9.0, 0.0, 0.0, 0.0]
}

# A pair set shared by many first glyphs is read once, not once per glyph.
expect {
	n = 300
	set = FontTest.pack([U16(n)].concat(FontTest.counting(n).join_map(|g| [U16(g), I16(-1)])))
	# Every set offset points at the one set, after the coverage.
	subtable = FontTest.pack([U16(1), U16(10 + 2 * n), U16(4), U16(0), U16(n)].concat(List.repeat(U16(20 + 2 * n), n)).append(Raw(FontTest.coverage2([{ first: 0, last: n - 1, index: 0 }]))).append(Raw(set)))
	tables = FontTest.basic
		.map(|t| if (t.tag == "maxp") { tag: t.tag, data: FontTest.maxp(n) } else t)
		.append({ tag: "GPOS", data: gpos([{ kind: 2, subtables: [subtable] }]) })
	match read_tables(tables) {
		Ok(font) => {
			stored = font.kerning.join_map(|lookup| lookup.map(Font.stored_size)).sum()
			Font.kerning(font, [5, 7, 299, 0]) == [-1.0, -1.0, -1.0, 0.0] and stored < 4 * n
		}
		Err(_) => False
	}
}

# Many lookups that all point at one lookup with many subtables, all the
# same: more work than the table could describe without sharing, so the
# table is refused.
expect {
	lookups = 300
	header = [U32(0x00010000), U16(10), U16(12), U16(0)]
	features = [U16(0), U16(1), Tag("kern"), U16(8), U16(0), U16(lookups)].concat(FontTest.counting(lookups).map(|i| U16(i)))
	# The lookup list: every offset points at one lookup after the list.
	lookup_at = 2 + 2 * lookups
	list = [U16(lookups)].concat(List.repeat(U16(lookup_at), lookups))
	lookup = [U16(2), U16(0), U16(lookups)].concat(List.repeat(U16(6 + 2 * lookups), lookups))
	table = FontTest.pack(header).concat(FontTest.pack(features)).concat(FontTest.pack(list)).concat(FontTest.pack(lookup)).concat(simple_pairs)
	patched = FontTest.patch(table, 8, FontTest.u16(24 + 2 * lookups))
	problems_of(basic_with("GPOS", patched)) == [BadTable("GPOS")]
}

# ------------------------------------------------------------ legacy kern

expect kerning_of(basic_with("kern", FontTest.kern([{ coverage: 1, pairs: [{ left: 1, right: 2, value: -50 }, { left: 2, right: 3, value: -30 }] }])), [1, 2, 3, 1]) == [-50.0, -30.0, 0.0, 0.0]

# Each horizontal subtable is applied in turn and the adjustments add up;
# vertical and cross-stream subtables are ignored.
expect {
	kern = FontTest.kern([
		{ coverage: 1, pairs: [{ left: 1, right: 2, value: -50 }] },
		{ coverage: 0, pairs: [{ left: 1, right: 2, value: -1000 }] },
		{ coverage: 5, pairs: [{ left: 1, right: 2, value: -2000 }] },
		{ coverage: 1, pairs: [{ left: 1, right: 2, value: 7 }] },
	])
	kerning_of(basic_with("kern", kern), [1, 2]) == [-43.0, 0.0]
}

expect problems_of(basic_with("kern", FontTest.kern([{ coverage: 1, pairs: [{ left: 1, right: 2, value: -50 }] }]).drop_last(1))) == [BadTable("kern")]
expect problems_of(basic_with("kern", FontTest.patch(FontTest.kern([]), 2, FontTest.u16(3)))) == [BadTable("kern")]

# A `kern` table in Apple's layout (version 1.0), as browsers read it:
# horizontal format 0 subtables kern; vertical, cross-stream and variation
# subtables and other formats do not.
apple_kern : List({ coverage : U64, format : U64, pairs : List({ left : U64, right : U64, value : I64 }) }) -> List(U8)
apple_kern = |subtables| {
	body = subtables.join_map(
		|t| {
			n = t.pairs.len()
			FontTest.u32(16 + 6 * n)
				.concat([t.coverage.to_u8_wrap(), t.format.to_u8_wrap(), 0, 0])
				.concat(FontTest.pack([U16(n), U16(0), U16(0), U16(0)].concat(t.pairs.join_map(|p| [U16(p.left), U16(p.right), I16(p.value)]))))
		},
	)
	FontTest.u32(0x00010000).concat(FontTest.u32(subtables.len())).concat(body)
}

expect {
	kern = apple_kern([
		{ coverage: 0, format: 0, pairs: [{ left: 1, right: 2, value: -50 }, { left: 2, right: 3, value: 4 }] },
		{ coverage: 0x80, format: 0, pairs: [{ left: 1, right: 2, value: -1000 }] },
		{ coverage: 0x40, format: 0, pairs: [{ left: 1, right: 2, value: -1000 }] },
		{ coverage: 0x20, format: 0, pairs: [{ left: 1, right: 2, value: -1000 }] },
		{ coverage: 0, format: 2, pairs: [{ left: 1, right: 2, value: -1000 }] },
		{ coverage: 0, format: 0, pairs: [{ left: 1, right: 2, value: -1 }] },
	])
	kerning_of(basic_with("kern", kern), [1, 2, 3]) == [-51.0, 4.0, 0.0]
}
expect problems_of(basic_with("kern", apple_kern([{ coverage: 0, format: 0, pairs: [{ left: 1, right: 2, value: -50 }] }]).drop_last(1))) == [BadTable("kern")]
expect problems_of(basic_with("kern", FontTest.patch(apple_kern([]), 4, FontTest.u32(0xFFFFFFFF)))) == [BadTable("kern")]
expect problems_of(basic_with("kern", FontTest.patch(apple_kern([{ coverage: 0, format: 0, pairs: [] }]), 8, FontTest.u32(8)))) == [BadTable("kern")]
expect kerning_of(basic_with("kern", apple_kern([])), [1, 2]) == [0.0, 0.0]

# ------------------------------------------------------------ Inter

# Known values, checked against fontTools and HarfBuzz reading the same
# file.
expect {
	font = inter
	Font.ascent(font) == 1984.0 and Font.descent(font) == 494.0 and Font.glyph_total(font) == 2937
}
expect {
	font = inter
	cps = [0x41, 0x56, 0x54, 0x6F, 0x2D, 0x3E, 0x20, 0x2A, 0x31, 0xE9, 0x20AC, 0x2192, 0x1F852, 0x378, 0x10FFFF]
	cps.map(|cp| Font.glyph(font, cp) ?? 9999) == [2, 456, 411, 790, 1459, 1517, 1777, 1547, 1342, 618, 1316, 1805, 1807, 9999, 9999]
}
expect {
	font = inter
	[2, 456, 411, 790, 1459, 1517, 1777, 1547, 1342, 618, 1316, 1805, 2936].map(|g| Font.advance(font, g)) == [1413.0, 1413.0, 1322.0, 1228.0, 942.0, 1355.0, 576.0, 1026.0, 833.0, 1194.0, 1365.0, 1954.0, 434.0]
}
expect {
	font = inter
	[0, 2, 1547, 1548, 1777, 1805, 2936].map(|g| Font.ink(font, g)) == [Ink({ left: 328.0, right: 1016.0 }), Ink({ left: 52.0, right: 1361.0 }), Ink({ left: 114.0, right: 912.0 }), Ink({ left: 195.0, right: 1126.0 }), NoInk, Ink({ left: 256.0, right: 1752.0 }), Ink({ left: 80.0, right: 354.0 })]
}

# Kerning pairs A V, T o, V A, A A, W a, y period, T y, L T, and A with the
# raised asterisk.
expect {
	font = inter
	pairs = [(2, 456), (411, 790), (456, 2), (2, 2), (459, 507), (998, 1502), (411, 998), (281, 411), (2, 1548)]
	pairs.map(|(l, r)| Font.kerning(font, [l, r])) == [[-140.0, 0.0], [-160.0, 0.0], [-140.0, 0.0], [30.0, 0.0], [-104.0, 0.0], [-90.0, 0.0], [-128.0, 0.0], [-197.0, 0.0], [-69.0, 0.0]]
}

# Inter shaped by HarfBuzz 15.0.0 (through uharfbuzz 0.57.0) with its default
# features: the glyphs, the first character each draws, and each glyph's
# advance including kerning, in font units.
inter_cases : List({ text : Str, code_points : List(U32), glyphs : List(U64), clusters : List(U64), advances : List(F64) })
inter_cases = [
	{ text: "Hello World", code_points: [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100], glyphs: [161, 614, 736, 736, 790, 1777, 459, 790, 852, 736, 597], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], advances: [1522.0, 1194.0, 496.0, 496.0, 1228.0, 576.0, 1914.0, 1228.0, 803.0, 496.0, 1254.0] },
	{ text: "A->B", code_points: [65, 45, 62, 66], glyphs: [2, 1829, 65], clusters: [0, 1, 3], advances: [1413.0, 1954.0, 1340.0] },
	{ text: "x --> y", code_points: [120, 32, 45, 45, 62, 32, 121], glyphs: [993, 1777, 1806, 1777, 998], clusters: [0, 1, 2, 5, 6], advances: [1118.0, 576.0, 2746.0, 576.0, 1151.0] },
	{ text: "<->", code_points: [60, 45, 62], glyphs: [1814], clusters: [0], advances: [2746.0] },
	{ text: "->>", code_points: [45, 62, 62], glyphs: [1805, 1517], clusters: [0, 2], advances: [1954.0, 1355.0] },
	{ text: "<-", code_points: [60, 45], glyphs: [1800], clusters: [0], advances: [1954.0] },
	{ text: "=>", code_points: [61, 62], glyphs: [1808], clusters: [0], advances: [1954.0] },
	{ text: "<=", code_points: [60, 61], glyphs: [1516, 1520], clusters: [0, 1], advances: [1355.0, 1355.0] },
	{ text: "!=", code_points: [33, 61], glyphs: [1427, 1533], clusters: [0, 1], advances: [589.0, 1355.0] },
	{ text: "==", code_points: [61, 61], glyphs: [1520, 1520], clusters: [0, 1], advances: [1355.0, 1355.0] },
	{ text: "...", code_points: [46, 46, 46], glyphs: [1502, 1502, 1502], clusters: [0, 1, 2], advances: [590.0, 590.0, 590.0] },
	{ text: "--", code_points: [45, 45], glyphs: [1459, 1459], clusters: [0, 1], advances: [942.0, 942.0] },
	{ text: "---", code_points: [45, 45, 45], glyphs: [1459, 1459, 1459], clusters: [0, 1, 2], advances: [942.0, 942.0, 942.0] },
	{ text: "A*", code_points: [65, 42], glyphs: [2, 1548], clusters: [0, 1], advances: [1344.0, 1321.0] },
	{ text: "1*", code_points: [49, 42], glyphs: [1342, 1548], clusters: [0, 1], advances: [833.0, 1321.0] },
	{ text: "a*", code_points: [97, 42], glyphs: [507, 1547], clusters: [0, 1], advances: [1150.0, 1026.0] },
	{ text: "A*B", code_points: [65, 42, 66], glyphs: [2, 1548, 65], clusters: [0, 1, 2], advances: [1344.0, 1321.0, 1340.0] },
	{ text: "(a+b)*c", code_points: [40, 97, 43, 98, 41, 42, 99], glyphs: [1437, 507, 1522, 578, 1438, 1547, 586], clusters: [0, 1, 2, 3, 4, 5, 6], advances: [747.0, 1150.0, 1355.0, 1231.0, 747.0, 1026.0, 1170.0] },
	{ text: "12:30", code_points: [49, 50, 58, 51, 48], glyphs: [1342, 1343, 1506, 1345, 1341], clusters: [0, 1, 2, 3, 4], advances: [833.0, 1249.0, 590.0, 1265.0, 1292.0] },
	{ text: "A:B", code_points: [65, 58, 66], glyphs: [2, 1506, 65], clusters: [0, 1, 2], advances: [1413.0, 590.0, 1340.0] },
	{ text: "AVATAR", code_points: [65, 86, 65, 84, 65, 82], glyphs: [2, 456, 2, 411, 2, 384], clusters: [0, 1, 2, 3, 4, 5], advances: [1273.0, 1273.0, 1239.0, 1148.0, 1413.0, 1318.0] },
	{ text: "Tomorrow", code_points: [84, 111, 109, 111, 114, 114, 111, 119], glyphs: [411, 790, 766, 790, 852, 852, 790, 984], clusters: [0, 1, 2, 3, 4, 5, 6, 7], advances: [1162.0, 1228.0, 1794.0, 1228.0, 803.0, 737.0, 1191.0, 1676.0] },
	{ text: "WAVE", code_points: [87, 65, 86, 69], glyphs: [459, 2, 456, 95], clusters: [0, 1, 2, 3], advances: [1902.0, 1273.0, 1413.0, 1231.0] },
	{ text: "Typography", code_points: [84, 121, 112, 111, 103, 114, 97, 112, 104, 121], glyphs: [411, 998, 843, 790, 658, 852, 507, 843, 670, 998], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], advances: [1194.0, 1151.0, 1254.0, 1228.0, 1256.0, 771.0, 1150.0, 1254.0, 1181.0, 1151.0] },
	{ text: "LT", code_points: [76, 84], glyphs: [281, 411], clusters: [0, 1], advances: [961.0, 1322.0] },
	{ text: "Yo", code_points: [89, 111], glyphs: [472, 790], clusters: [0, 1], advances: [1233.0, 1228.0] },
	{ text: "P.", code_points: [80, 46], glyphs: [375, 1502], clusters: [0, 1], advances: [1239.0, 590.0] },
	{ text: "r,", code_points: [114, 44], glyphs: [852, 1501], clusters: [0, 1], advances: [643.0, 590.0] },
	{ text: "\"quoted\"", code_points: [34, 113, 117, 111, 116, 101, 100, 34], glyphs: [1485, 849, 915, 790, 889, 614, 597, 1485], clusters: [0, 1, 2, 3, 4, 5, 6, 7], advances: [924.0, 1254.0, 1211.0, 1228.0, 650.0, 1194.0, 1254.0, 954.0] },
	{ text: "[box]", code_points: [91, 98, 111, 120, 93], glyphs: [1439, 578, 790, 993, 1441], clusters: [0, 1, 2, 3, 4], advances: [747.0, 1254.0, 1182.0, 1118.0, 747.0] },
	{ text: "{curly}", code_points: [123, 99, 117, 114, 108, 121, 125], glyphs: [1443, 586, 915, 852, 736, 998, 1444], clusters: [0, 1, 2, 3, 4, 5, 6], advances: [850.0, 1170.0, 1211.0, 803.0, 506.0, 1151.0, 873.0] },
	{ text: "A/B", code_points: [65, 47, 66], glyphs: [2, 1455, 65], clusters: [0, 1, 2], advances: [1453.0, 738.0, 1340.0] },
	{ text: "50%", code_points: [53, 48, 37], glyphs: [1347, 1341, 1744], clusters: [0, 1, 2], advances: [1215.0, 1292.0, 2011.0] },
	{ text: "office fi fl", code_points: [111, 102, 102, 105, 99, 101, 32, 102, 105, 32, 102, 108], glyphs: [790, 647, 647, 689, 586, 614, 1777, 647, 689, 1777, 647, 736], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], advances: [1228.0, 678.0, 758.0, 496.0, 1170.0, 1194.0, 576.0, 758.0, 496.0, 576.0, 758.0, 496.0] },
	{ text: "Façade", code_points: [70, 97, 231, 97, 100, 101], glyphs: [137, 507, 589, 507, 597, 614], clusters: [0, 1, 2, 3, 4, 5], advances: [1159.0, 1150.0, 1190.0, 1150.0, 1254.0, 1194.0] },
	{ text: "Ünïcödé", code_points: [220, 110, 239, 99, 246, 100, 233], glyphs: [429, 773, 692, 586, 791, 597, 618], clusters: [0, 1, 2, 3, 4, 5, 6], advances: [1524.0, 1210.0, 496.0, 1170.0, 1228.0, 1254.0, 1194.0] },
	{ text: "€100 → £5", code_points: [8364, 49, 48, 48, 32, 8594, 32, 163, 53], glyphs: [1316, 1342, 1341, 1341, 1777, 1829, 1777, 1312, 1347], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8], advances: [1365.0, 833.0, 1292.0, 1292.0, 576.0, 1954.0, 576.0, 1251.0, 1215.0] },
	{ text: "x×y", code_points: [120, 215, 121], glyphs: [993, 1524, 998], clusters: [0, 1, 2], advances: [1118.0, 1355.0, 1151.0] },
	{ text: "αβγ", code_points: [945, 946, 947], glyphs: [1110, 1136, 1137], clusters: [0, 1, 2], advances: [1360.0, 1220.0, 1151.0] },
	{ text: "Привет", code_points: [1055, 1088, 1080, 1074, 1077, 1090], glyphs: [2434, 848, 1262, 1254, 641, 1280], clusters: [0, 1, 2, 3, 4, 5], advances: [1522.0, 1254.0, 1211.0, 1157.0, 1194.0, 954.0] },
	{ text: "Is it ready?", code_points: [73, 115, 32, 105, 116, 32, 114, 101, 97, 100, 121, 63], glyphs: [197, 871, 1777, 689, 889, 1777, 852, 614, 507, 597, 998, 1431], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], advances: [550.0, 1081.0, 576.0, 496.0, 670.0, 576.0, 737.0, 1214.0, 1150.0, 1264.0, 1151.0, 1047.0] },
	{ text: "Start", code_points: [83, 116, 97, 114, 116], glyphs: [397, 889, 507, 852, 889], clusters: [0, 1, 2, 3, 4], advances: [1314.0, 680.0, 1150.0, 803.0, 670.0] },
	{ text: "End", code_points: [69, 110, 100], glyphs: [95, 773, 597], clusters: [0, 1, 2], advances: [1231.0, 1210.0, 1254.0] },
	{ text: "Process data", code_points: [80, 114, 111, 99, 101, 115, 115, 32, 100, 97, 116, 97], glyphs: [375, 852, 790, 586, 614, 871, 871, 1777, 597, 507, 889, 507], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], advances: [1308.0, 737.0, 1228.0, 1170.0, 1194.0, 1081.0, 1081.0, 576.0, 1254.0, 1150.0, 680.0, 1150.0] },
	{ text: "#1", code_points: [35, 49], glyphs: [1453, 1342], clusters: [0, 1], advances: [1297.0, 833.0] },
	{ text: "@at ~tilde ^caret _under_", code_points: [64, 97, 116, 32, 126, 116, 105, 108, 100, 101, 32, 94, 99, 97, 114, 101, 116, 32, 95, 117, 110, 100, 101, 114, 95], glyphs: [1445, 507, 889, 1777, 1528, 889, 689, 736, 597, 614, 1777, 1546, 586, 507, 852, 614, 889, 1777, 1543, 915, 773, 597, 614, 852, 1543], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24], advances: [1978.0, 1150.0, 670.0, 576.0, 1355.0, 670.0, 496.0, 496.0, 1254.0, 1194.0, 576.0, 965.0, 1190.0, 1150.0, 737.0, 1194.0, 670.0, 576.0, 934.0, 1211.0, 1210.0, 1254.0, 1194.0, 771.0, 934.0] },
	{ text: "1/2", code_points: [49, 47, 50], glyphs: [1342, 1455, 1343], clusters: [0, 1, 2], advances: [833.0, 738.0, 1249.0] },
	{ text: "+-", code_points: [43, 45], glyphs: [1522, 1459], clusters: [0, 1], advances: [1355.0, 942.0] },
	{ text: ":-)", code_points: [58, 45, 41], glyphs: [1506, 1471, 1447], clusters: [0, 1, 2], advances: [590.0, 942.0, 747.0] },
]

inter_shaped : { text : Str, code_points : List(U32), glyphs : List(U64), clusters : List(U64), advances : List(F64) } -> Bool
inter_shaped = |case| {
	font = inter
	items = case.code_points.map_with_index(|cp, i| { glyph: Font.glyph(font, cp) ?? 0, cluster: i })
	shaped = Font.substitute(font, items)
	glyphs = shaped.map(|item| item.glyph)
	advances = glyphs.map2(Font.kerning(font, glyphs), |g, k| Font.advance(font, g) + k)
	glyphs == case.glyphs and shaped.map(|item| item.cluster) == case.clusters and advances == case.advances
}

expect inter_cases.len() > 40 and inter_cases.keep_if(|case| !inter_shaped(case)).map(|case| case.text) == []
