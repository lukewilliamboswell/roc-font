import font.Font
import build.FontBuild
import "../../tests/fonts/Inter-Regular-metrics.ttf" as inter_file : List(U8)

## The tests of reading a font and querying it, through the public `Font`
## API exactly as the package ships it. Run with `roc test tests/api/main.roc`.
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
# Synthetic fonts are built from `FontBuild.basic`: four glyphs (0 missing,
# 1 `A`, 2 `B`, 3 `C`) with advances 500 to 800 and 1000 units per em.

read_tables : List({ tag : Str, data : List(U8) }) -> Try(Font, List(Font.Problem))
read_tables = |tables| Font.from_bytes(FontBuild.file(tables))

problems_of : List({ tag : Str, data : List(U8) }) -> List(Font.Problem)
problems_of = |tables|
	match read_tables(tables) {
		Ok(_) => []
		Err(found) => found
	}

# `basic` with one table replaced or added.
basic_with : Str, List(U8) -> List({ tag : Str, data : List(U8) })
basic_with = |tag, data| FontBuild.replace(FontBuild.basic, tag, data)

# The glyph of each code point, 9999 where the font has none.
glyphs_for : List({ tag : Str, data : List(U8) }), List(U32) -> List(U64)
glyphs_for = |tables, code_points|
	match read_tables(tables) {
		Ok(font) => code_points.map(|cp| Font.glyph(font, cp) ?? 9999)
		Err(_) => []
	}

# A font whose only character map is the given subtable.
cmap_only : U64, U64, List(U8) -> List({ tag : Str, data : List(U8) })
cmap_only = |system, encoding, subtable| basic_with("cmap", FontBuild.cmap([{ system, encoding, subtable }]))

kerning_of : List({ tag : Str, data : List(U8) }), List(U64) -> List(F64)
kerning_of = |tables, glyphs|
	match read_tables(tables) {
		Ok(font) => Font.kerning(font, glyphs)
		Err(_) => [9999.0]
	}

# A `GPOS` table whose `kern` feature uses every lookup given.
gpos : List({ kind : U64, subtables : List(List(U8)) }) -> List(U8)
gpos = |lookups| FontBuild.layout("DFLT", [{ tag: "kern", lookups: FontBuild.counting(lookups.len()) }], lookups)

# Pairs (1, 2) -50 and (1, 3) -30, and (2, 1) +20, x advance of the first
# glyph only.
simple_pairs : List(U8)
simple_pairs = FontBuild.pair1(4, 0, [{ glyph: 1, pairs: [{ second: 2, values: [-50] }, { second: 3, values: [-30] }] }, { glyph: 2, pairs: [{ second: 1, values: [20] }] }])

# ------------------------------------------------------------ reading a font

# The minimal font: metrics, glyph count and advances. Without `OS/2` the
# vertical metrics come from `hhea`; without `loca`/`glyf` nothing has ink.
expect {
	match read_tables(FontBuild.basic) {
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
expect FontBuild.file(FontBuild.basic) == FontBuild.file(FontBuild.basic)
expect {
	bytes = FontBuild.file(FontBuild.basic)
	match (Font.from_bytes(bytes), Font.from_bytes(bytes)) {
		(Ok(a), Ok(b)) => {
			glyphs = [0, 1, 2, 3, 4]
			glyphs.map(|g| Font.advance(a, g)) == glyphs.map(|g| Font.advance(b, g))
				and [0x40, 0x41, 0x43].map(|c| Font.glyph(a, c)) == [0x40, 0x41, 0x43].map(|c| Font.glyph(b, c))
				and glyphs.map(|g| Font.ink(a, g)) == glyphs.map(|g| Font.ink(b, g))
				and Font.ascent(a) == Font.ascent(b)
				and Font.descent(a) == Font.descent(b)
		}
		_ => False
	}
}

# ------------------------------------------------------------ cmap format 4

# Delta segments: the first and last character of each segment map, the
# characters just outside do not.
expect {
	cmap = FontBuild.cmap4([{ first: 0x20, last: 0x22, delta: 65536 - 0x1F, glyphs: [] }, { first: 0x30, last: 0x30, delta: 65536 - 0x2D, glyphs: [] }])
	glyphs_for(cmap_only(3, 1, cmap), [0x1F, 0x20, 0x21, 0x22, 0x23, 0x2F, 0x30, 0x31]) == [9999, 1, 2, 3, 9999, 9999, 3, 9999]
}

# Segments that map through a glyph array (idRangeOffset), with and without
# a delta, beside a delta segment; a zero entry leaves its character
# unmapped.
expect {
	cmap = FontBuild.cmap4([
		{ first: 0x41, last: 0x42, delta: 1, glyphs: [1, 2] },
		{ first: 0x50, last: 0x50, delta: 65536 - 0x4F, glyphs: [] },
		{ first: 0x61, last: 0x63, delta: 0, glyphs: [3, 0, 2] },
	])
	glyphs_for(cmap_only(3, 1, cmap), [0x40, 0x41, 0x42, 0x43, 0x50, 0x61, 0x62, 0x63, 0x64]) == [9999, 2, 3, 9999, 1, 3, 9999, 2, 9999]
}

# The delta wraps modulo 65536 at the top of the range; U+FFFF and code
# points beyond the Basic Multilingual Plane are never mapped by format 4.
expect {
	cmap = FontBuild.cmap4([{ first: 0xFFFE, last: 0xFFFE, delta: 4, glyphs: [] }])
	glyphs_for(cmap_only(3, 1, cmap), [0xFFFD, 0xFFFE, 0xFFFF, 0x10000, 0x10FFFF]) == [9999, 2, 9999, 9999, 9999]
}

# A delta segment whose glyphs wrap past 65535 to 0 mid-segment: the
# character drawn by glyph 0 is unmapped and the next ones continue from
# glyph 1. Glyph 0 at the start of a segment is unmapped too.
expect glyphs_for(cmap_only(3, 1, FontBuild.cmap4([{ first: 0x41, last: 0x45, delta: 65536 - 0x43, glyphs: [] }])), [0x41, 0x42, 0x43, 0x44, 0x45, 0x46]) == [9999, 9999, 9999, 1, 2, 9999]
expect glyphs_for(cmap_only(3, 1, FontBuild.cmap4([{ first: 0x41, last: 0x43, delta: 65536 - 0x41, glyphs: [] }, { first: 0x44, last: 0x44, delta: 65536 + 3 - 0x44, glyphs: [] }])), [0x41, 0x42, 0x43, 0x44]) == [9999, 1, 2, 3]

# A glyph array segment that ends at U+FFFF needs no entry for it.
expect {
	cmap = FontBuild.cmap4([{ first: 0xFFFD, last: 0xFFFE, delta: 0, glyphs: [2, 3] }])
	glyphs_for(cmap_only(3, 1, cmap), [0xFFFC, 0xFFFD, 0xFFFE, 0xFFFF]) == [9999, 2, 3, 9999]
}

# Platform 0 (Unicode) is a Unicode mapping too.
expect glyphs_for(cmap_only(0, 3, FontBuild.cmap4([{ first: 0x41, last: 0x41, delta: 65536 - 0x40, glyphs: [] }])), [0x41]) == [1]

# A character mapped to a glyph the font does not have is unmapped, and a
# run that only partly fits keeps the characters whose glyphs exist.
expect {
	cmap = FontBuild.cmap4([{ first: 0x44, last: 0x44, delta: 65536 + 9 - 0x44, glyphs: [] }, { first: 0x45, last: 0x48, delta: 65536 + 2 - 0x45, glyphs: [] }])
	glyphs_for(cmap_only(3, 1, cmap), [0x44, 0x45, 0x46, 0x47, 0x48]) == [9999, 2, 3, 9999, 9999]
}

# Segments out of order are a bad table.
expect {
	cmap = FontBuild.cmap4([{ first: 0x50, last: 0x51, delta: 0, glyphs: [] }, { first: 0x41, last: 0x42, delta: 0, glyphs: [] }])
	problems_of(cmap_only(3, 1, cmap)) == [BadTable("cmap")]
}

expect {
	cmap = FontBuild.cmap4([{ first: 0x41, last: 0x45, delta: 0, glyphs: [] }, { first: 0x45, last: 0x46, delta: 0, glyphs: [] }])
	problems_of(cmap_only(3, 1, cmap)) == [BadTable("cmap")]
}

# A glyph array that runs past the end of the table.
expect {
	table = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 0x41, last: 0x43, delta: 0, glyphs: [1, 2, 3] }]) }])
	problems_of(basic_with("cmap", table.drop_last(2))) == [BadTable("cmap")]
}

# A segment count larger than the table.
expect {
	table = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.u16(4).concat(FontBuild.u16(14)).concat(FontBuild.u16(0)).concat(FontBuild.u16(0xFFFE)).concat(List.repeat(0, 6)) }])
	problems_of(basic_with("cmap", table)) == [BadTable("cmap")]
}

# ------------------------------------------------------------ cmap format 12

expect {
	cmap = FontBuild.cmap12([{ first: 0x41, last: 0x43, glyph: 1 }, { first: 0x1F600, last: 0x1F601, glyph: 2 }])
	glyphs_for(cmap_only(3, 10, cmap), [0x40, 0x41, 0x43, 0x44, 0x1F5FF, 0x1F600, 0x1F601, 0x1F602, 0x10FFFF]) == [9999, 1, 3, 9999, 9999, 2, 3, 9999, 9999]
}

# Groups whose glyphs run past the last glyph keep the glyphs that exist.
expect {
	cmap = FontBuild.cmap12([{ first: 0x50, last: 0x55, glyph: 2 }, { first: 0x60, last: 0x60, glyph: 4 }])
	glyphs_for(cmap_only(3, 10, cmap), [0x50, 0x51, 0x52, 0x55, 0x60]) == [2, 3, 9999, 9999, 9999]
}

# A group starting at glyph 0 maps its first character to nothing and the
# rest from glyph 1.
expect glyphs_for(cmap_only(3, 10, FontBuild.cmap12([{ first: 0x41, last: 0x43, glyph: 0 }])), [0x41, 0x42, 0x43]) == [9999, 1, 2]

# The highest code point Unicode allows.
expect glyphs_for(cmap_only(0, 4, FontBuild.cmap12([{ first: 0x10FFFF, last: 0x10FFFF, glyph: 3 }])), [0x10FFFF]) == [3]

# Format 12 is preferred to format 4, whatever the record order.
expect {
	table = FontBuild.cmap([
		{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 0x41, last: 0x41, delta: 65536 - 0x40, glyphs: [] }]) },
		{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 0x41, last: 0x41, glyph: 2 }]) },
	])
	glyphs_for(basic_with("cmap", table), [0x41]) == [2]
}

expect problems_of(cmap_only(3, 10, FontBuild.cmap12([{ first: 0x50, last: 0x55, glyph: 1 }, { first: 0x41, last: 0x42, glyph: 1 }]))) == [BadTable("cmap")]
expect problems_of(cmap_only(3, 10, FontBuild.cmap12([{ first: 0x50, last: 0x55, glyph: 1 }, { first: 0x55, last: 0x56, glyph: 1 }]))) == [BadTable("cmap")]
expect problems_of(cmap_only(3, 10, FontBuild.cmap12([{ first: 0x50, last: 0x4F, glyph: 1 }]))) == [BadTable("cmap")]
expect problems_of(cmap_only(3, 10, FontBuild.cmap12([{ first: 0x10FFFF, last: 0x110000, glyph: 1 }]))) == [BadTable("cmap")]

# A huge group count is checked against the table before anything is
# allocated.
expect {
	subtable = FontBuild.u16(12).concat(FontBuild.u16(0)).concat(FontBuild.u32(16)).concat(FontBuild.u32(0)).concat(FontBuild.u32(0xFFFFFFFF))
	problems_of(cmap_only(3, 10, subtable)) == [BadTable("cmap")]
}

# ------------------------------------------------------------ cmap format 0

# Character codes up to 255 index a byte array; glyph 0 and glyphs the font
# does not have leave a code unmapped.
expect {
	glyphs = List.repeat(0, 0x41).concat([1, 0, 3, 9])
	glyphs_for(cmap_only(0, 3, FontBuild.cmap0(glyphs)), [0x40, 0x41, 0x42, 0x43, 0x44, 0xFF, 0x100, 0x141]) == [9999, 1, 9999, 3, 9999, 9999, 9999, 9999]
}

# A truncated byte array is a bad table.
expect problems_of(cmap_only(3, 1, FontBuild.cmap0([1, 2, 3]).drop_last(1))) == [BadTable("cmap")]

# ------------------------------------------------------------ cmap formats 6 and 10

# A trimmed array maps consecutive codes from its first; codes before or
# after it are unmapped.
expect glyphs_for(cmap_only(3, 1, FontBuild.cmap6(0x41, [1, 0, 3, 7])), [0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x10041]) == [9999, 1, 9999, 3, 9999, 9999, 9999]
expect glyphs_for(cmap_only(3, 10, FontBuild.cmap10(0x1F600, [2, 3])), [0x1F5FF, 0x1F600, 0x1F601, 0x1F602, 0xF600]) == [9999, 2, 3, 9999, 9999]

# An empty array maps nothing.
expect glyphs_for(cmap_only(3, 1, FontBuild.cmap6(0x41, [])), [0x41]) == [9999]

# An array past the end of the table, or a count larger than the table
# (checked before anything is read), is a bad table.
expect problems_of(cmap_only(3, 1, FontBuild.cmap6(0x41, [1, 2]).drop_last(1))) == [BadTable("cmap")]
expect problems_of(cmap_only(3, 1, FontBuild.cmap6(0x41, []).take_first(8))) == [BadTable("cmap")]
expect problems_of(cmap_only(3, 10, FontBuild.cmap10(0x41, [1, 2]).drop_last(1))) == [BadTable("cmap")]
expect problems_of(cmap_only(3, 10, FontBuild.patch(FontBuild.cmap10(0x41, [1]), 16, FontBuild.u32(0xFFFFFFFF)))) == [BadTable("cmap")]

# ------------------------------------------------------------ cmap format 13

# Every character of a group maps to the group's one glyph.
expect {
	cmap = FontBuild.cmap13([{ first: 0x41, last: 0x5A, glyph: 2 }, { first: 0x10000, last: 0x10FFFF, glyph: 3 }])
	glyphs_for(cmap_only(3, 10, cmap), [0x40, 0x41, 0x50, 0x5A, 0x5B, 0xFFFF, 0x10000, 0x10FFFF]) == [9999, 2, 2, 2, 9999, 9999, 3, 3]
}

# A group whose glyph the font does not have maps nothing.
expect glyphs_for(cmap_only(0, 6, FontBuild.cmap13([{ first: 0x41, last: 0x43, glyph: 4 }])), [0x41, 0x43]) == [9999, 9999]

# Groups out of order, overlapping or past Unicode, and a truncated table,
# are bad tables.
expect problems_of(cmap_only(3, 10, FontBuild.cmap13([{ first: 0x50, last: 0x55, glyph: 1 }, { first: 0x41, last: 0x42, glyph: 1 }]))) == [BadTable("cmap")]
expect problems_of(cmap_only(3, 10, FontBuild.cmap13([{ first: 0x50, last: 0x55, glyph: 1 }, { first: 0x55, last: 0x56, glyph: 1 }]))) == [BadTable("cmap")]
expect problems_of(cmap_only(3, 10, FontBuild.cmap13([{ first: 0x41, last: 0x110000, glyph: 1 }]))) == [BadTable("cmap")]
expect problems_of(cmap_only(3, 10, FontBuild.cmap13([{ first: 0x41, last: 0x42, glyph: 1 }]).drop_last(1))) == [BadTable("cmap")]

# ------------------------------------------------------------ cmap selection

# A Windows symbol map (3, 0) is preferred to every other map. A code point
# up to U+00FF that it does not have is looked up again at U+F000 and up;
# others are not.
expect {
	table = FontBuild.cmap([
		{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 0x41, last: 0x41, delta: 65536 + 3 - 0x41, glyphs: [] }]) },
		{ system: 3, encoding: 0, subtable: FontBuild.cmap4([{ first: 0x42, last: 0x42, delta: 65536 + 3 - 0x42, glyphs: [] }, { first: 0xF041, last: 0xF041, delta: 65536 + 1 - 0xF041, glyphs: [] }, { first: 0xF141, last: 0xF141, delta: 65536 + 2 - 0xF141, glyphs: [] }]) },
	])
	glyphs_for(basic_with("cmap", table), [0x41, 0x42, 0xF041, 0x141, 0xF042]) == [1, 3, 1, 9999, 9999]
}

# A symbol map in any format works the same way.
expect glyphs_for(cmap_only(3, 0, FontBuild.cmap12([{ first: 0xF041, last: 0xF042, glyph: 1 }])), [0x41, 0x42, 0x43]) == [1, 2, 9999]

# A symbol font in a Windows 3.1 Arabic font page holds Arabic in the
# private use area: U+0020 is at U+F120 in the simplified page and U+F220
# in the traditional one. Another font page is plain Unicode.
expect {
	cmap = FontBuild.cmap([{ system: 3, encoding: 0, subtable: FontBuild.cmap4([{ first: 0xF120, last: 0xF120, delta: 65536 + 1 - 0xF120, glyphs: [] }, { first: 0xF220, last: 0xF220, delta: 65536 + 2 - 0xF220, glyphs: [] }]) }])
	with_page = |page| basic_with("cmap", cmap).append({ tag: "OS/2", data: FontBuild.os2_page(page) })
	glyphs_for(with_page(0xB200), [0x20, 0xF120]) == [1, 1]
		and glyphs_for(with_page(0xB300), [0x20, 0xF220]) == [2, 2]
		and glyphs_for(with_page(0xB100), [0x20, 0xF120]) == [9999, 1]
		and glyphs_for(with_page(0), [0x20, 0xF020]) == [9999, 9999]
}

# The font page counts only in a version 0 `OS/2` table.
expect {
	cmap = FontBuild.cmap([{ system: 3, encoding: 0, subtable: FontBuild.cmap4([{ first: 0xF220, last: 0xF220, delta: 65536 + 2 - 0xF220, glyphs: [] }]) }])
	os2 = FontBuild.patch(FontBuild.os2_page(0xB300), 0, FontBuild.u16(1))
	glyphs_for(basic_with("cmap", cmap).append({ tag: "OS/2", data: os2 }), [0x20]) == [9999]
}

# A Macintosh Roman map is read directly for ASCII and through Mac Roman
# for the rest: U+00C4 is 0x80 there and U+00A0 is 0xCA; U+0080 is not in
# Mac Roman. Another Macintosh encoding maps ASCII only.
expect {
	glyphs = List.repeat(0, 0x41).concat([1]).concat(List.repeat(0, 0x80 - 0x42)).concat([2]).concat(List.repeat(0, 0xCA - 0x81)).concat([3])
	glyphs_for(cmap_only(1, 0, FontBuild.cmap0(glyphs)), [0x41, 0xC4, 0xA0, 0x80, 0xCA]) == [1, 2, 3, 9999, 9999]
		and glyphs_for(cmap_only(1, 1, FontBuild.cmap0(glyphs)), [0x41, 0xC4, 0x80]) == [1, 9999, 9999]
}

# The order of preference, whatever the record order: full Unicode maps
# (3, 10), (0, 6), (0, 4), then (3, 1), (0, 3) to (0, 0), then Macintosh.
expect {
	a_to = |g| FontBuild.cmap4([{ first: 0x41, last: 0x41, delta: 65536 + g - 0x41, glyphs: [] }])
	pick = |records| glyphs_for(basic_with("cmap", FontBuild.cmap(records.map(|r| { system: r.system, encoding: r.encoding, subtable: a_to(r.glyph) }))), [0x41])
	pick([{ system: 1, encoding: 0, glyph: 3 }, { system: 0, encoding: 0, glyph: 2 }]) == [2]
		and pick([{ system: 0, encoding: 3, glyph: 2 }, { system: 3, encoding: 1, glyph: 1 }]) == [1]
		and pick([{ system: 3, encoding: 1, glyph: 1 }, { system: 0, encoding: 4, glyph: 3 }]) == [3]
		and pick([{ system: 0, encoding: 4, glyph: 3 }, { system: 3, encoding: 10, glyph: 2 }]) == [2]
		and pick([{ system: 0, encoding: 1, glyph: 3 }, { system: 0, encoding: 2, glyph: 1 }]) == [1]
}

# A subtable in a format that is not read (here 8, and 14, which holds
# variation sequences) is passed over for the next preferred one.
expect {
	table = FontBuild.cmap([
		{ system: 3, encoding: 1, subtable: FontBuild.u16(8).concat(List.repeat(0, 30)) },
		{ system: 0, encoding: 5, subtable: FontBuild.u16(14).concat(List.repeat(0, 8)) },
		{ system: 1, encoding: 0, subtable: FontBuild.cmap0(List.repeat(0, 0x41).append(2)) },
	])
	glyphs_for(basic_with("cmap", table), [0x41]) == [2]
}

# No map to use: an unknown platform or encoding, only formats that are not
# read, or no subtables at all.
expect problems_of(cmap_only(2, 1, FontBuild.cmap4([{ first: 0x41, last: 0x41, delta: 0, glyphs: [] }]))) == [NoUnicodeMapping]
expect problems_of(cmap_only(3, 2, FontBuild.cmap12([{ first: 0x41, last: 0x41, glyph: 1 }]))) == [NoUnicodeMapping]
expect problems_of(cmap_only(0, 5, FontBuild.u16(14).concat(List.repeat(0, 8)))) == [NoUnicodeMapping]
expect problems_of(cmap_only(3, 1, FontBuild.u16(2).concat(List.repeat(0, 8)))) == [NoUnicodeMapping]
expect problems_of(basic_with("cmap", FontBuild.u16(0).concat(FontBuild.u16(0)))) == [NoUnicodeMapping]

# The chosen record's offset past the end of the table is a bad table, not
# a missing map.
expect problems_of(basic_with("cmap", FontBuild.u16(0).concat(FontBuild.u16(1)).concat(FontBuild.u16(3)).concat(FontBuild.u16(1)).concat(FontBuild.u32(5000)))) == [BadTable("cmap")]

# A broken map that is not chosen is not read.
expect {
	table = FontBuild.cmap([
		{ system: 1, encoding: 0, subtable: FontBuild.cmap0([]).take_first(10) },
		{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 0x41, last: 0x41, delta: 65536 + 1 - 0x41, glyphs: [] }]) },
	])
	glyphs_for(basic_with("cmap", table), [0x41]) == [1]
}

# A bad character map is reported with the other tables' problems.
expect {
	tables = basic_with("cmap", FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap13([{ first: 0x50, last: 0x41, glyph: 1 }]) }]))
		.map(|t| if (t.tag == "maxp") { tag: t.tag, data: FontBuild.maxp(0) } else t)
	problems_of(tables) == [BadTable("maxp"), BadTable("cmap")]
}

# More encoding records than the table holds.
expect problems_of(basic_with("cmap", FontBuild.u16(0).concat(FontBuild.u16(3)).concat(List.repeat(0, 8)))) == [BadTable("cmap")]

# ------------------------------------------------------------ hmtx

# Glyphs past the long metrics take the last advance.
expect {
	match read_tables(FontBuild.basic.map(|t| if (t.tag == "hhea") { tag: t.tag, data: FontBuild.hhea(800, -200, 2) } else if (t.tag == "hmtx") { tag: t.tag, data: FontBuild.hmtx([500, 600]).concat([0, 0, 0, 0]) } else t)) {
		Ok(font) => [0, 1, 2, 3, 4].map(|g| Font.advance(font, g)) == [500.0, 600.0, 600.0, 600.0, 0.0]
		Err(_) => False
	}
}

# One long metric covers every glyph.
expect {
	match read_tables(FontBuild.basic.map(|t| if (t.tag == "hhea") { tag: t.tag, data: FontBuild.hhea(800, -200, 1) } else if (t.tag == "hmtx") { tag: t.tag, data: FontBuild.hmtx([432]) } else t)) {
		Ok(font) => [0, 1, 2, 3].map(|g| Font.advance(font, g)) == [432.0, 432.0, 432.0, 432.0]
		Err(_) => False
	}
}

# More long metrics than glyphs: only the glyphs' metrics are needed.
expect {
	match read_tables(basic_with("hhea", FontBuild.hhea(800, -200, 60000))) {
		Ok(font) => Font.advance(font, 3) == 800.0
		Err(_) => False
	}
}

# The largest advance a font can hold.
expect {
	match read_tables(basic_with("hmtx", FontBuild.hmtx([65535, 0, 1, 2]))) {
		Ok(font) => Font.advance(font, 0) == 65535.0
		Err(_) => False
	}
}

expect problems_of(basic_with("hmtx", FontBuild.hmtx([500, 600, 700]))) == [BadTable("hmtx")]
expect problems_of(FontBuild.without(FontBuild.basic, "hmtx")) == [MissingTable("hmtx")]

# ------------------------------------------------------------ loca and glyf

outline_glyphs : List(List(U8))
outline_glyphs = [[], FontBuild.outline(10, 490), [], FontBuild.outline(-5, 700)]

with_outlines : Bool, { loca : List(U8), glyf : List(U8) } -> List({ tag : Str, data : List(U8) })
with_outlines = |long, tables|
	basic_with("head", FontBuild.head(1000, long))
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
expect inks_of(with_outlines(False, FontBuild.outlines(outline_glyphs, False))) == [NoInk, Ink({ left: 10.0, right: 490.0 }), NoInk, Ink({ left: -5.0, right: 700.0 }), NoInk]
expect inks_of(with_outlines(True, FontBuild.outlines(outline_glyphs, True))) == [NoInk, Ink({ left: 10.0, right: 490.0 }), NoInk, Ink({ left: -5.0, right: 700.0 }), NoInk]

# A glyph shorter than its header, and one whose extent is inverted.
expect inks_of(with_outlines(False, FontBuild.outlines([[], [1, 2, 3, 4], FontBuild.outline(5, 4), []], False))) == [NoInk, NoInk, NoInk, NoInk, NoInk]

# The `loca` format must match `head`: short offsets read as long ones
# run past the end of `loca`.
expect problems_of(with_outlines(True, FontBuild.outlines(outline_glyphs, False))) == [BadTable("loca")]

# Too few offsets, an offset past `glyf`, and offsets that go backwards.
expect problems_of(with_outlines(False, { loca: FontBuild.outlines(outline_glyphs, False).loca.drop_last(2), glyf: FontBuild.outlines(outline_glyphs, False).glyf })) == [BadTable("loca")]
expect problems_of(with_outlines(False, { loca: [0, 0, 0, 5, 0, 5, 0, 10, 0, 11], glyf: FontBuild.outlines(outline_glyphs, False).glyf })) == [BadTable("loca")]
expect problems_of(with_outlines(False, { loca: [0, 0, 0, 5, 0, 5, 0, 2, 0, 10], glyf: FontBuild.outlines(outline_glyphs, False).glyf })) == [BadTable("loca")]

# `loca` without `glyf` (or the reverse) gives no extents.
expect inks_of(basic_with("loca", FontBuild.outlines(outline_glyphs, False).loca)) == [NoInk, NoInk, NoInk, NoInk, NoInk]

# ------------------------------------------------------------ vertical metrics

vertical_of : List({ tag : Str, data : List(U8) }) -> { ascent : F64, descent : F64 }
vertical_of = |tables|
	match read_tables(tables) {
		Ok(font) => { ascent: Font.ascent(font), descent: Font.descent(font) }
		Err(_) => { ascent: -1.0, descent: -1.0 }
	}

expect vertical_of(basic_with("OS/2", FontBuild.os2({ use_typo: True, typo_ascent: 900, typo_descent: -300, win_ascent: 1000, win_descent: 400 }))) == { ascent: 900.0, descent: 300.0 }
expect vertical_of(basic_with("OS/2", FontBuild.os2({ use_typo: False, typo_ascent: 900, typo_descent: -300, win_ascent: 1000, win_descent: 400 }))) == { ascent: 800.0, descent: 200.0 }
expect vertical_of(FontBuild.replace(basic_with("hhea", FontBuild.hhea(0, 0, 4)), "OS/2", FontBuild.os2({ use_typo: False, typo_ascent: 900, typo_descent: -300, win_ascent: 1000, win_descent: 400 }))) == { ascent: 900.0, descent: 300.0 }
expect vertical_of(FontBuild.replace(basic_with("hhea", FontBuild.hhea(0, 0, 4)), "OS/2", FontBuild.os2({ use_typo: False, typo_ascent: 0, typo_descent: 0, win_ascent: 1000, win_descent: 400 }))) == { ascent: 1000.0, descent: 400.0 }
expect vertical_of(basic_with("hhea", FontBuild.hhea(0, 0, 4))) == { ascent: 0.0, descent: 0.0 }

# ------------------------------------------------------------ problems

expect Font.from_bytes(List.repeat(0, 11)).is_err()
expect problems_of([]) == [MissingTable("head"), MissingTable("hhea"), MissingTable("maxp"), MissingTable("cmap")]

# Signatures: TrueType, `true` and `OTTO` are fonts; a collection is not.
expect {
	match Font.from_bytes(FontBuild.u32(0x74727565).concat(FontBuild.file(FontBuild.basic).drop_first(4))) {
		Ok(_) => True
		Err(_) => False
	}
}
expect {
	match Font.from_bytes(FontBuild.u32(0x4F54544F).concat(FontBuild.file(FontBuild.basic).drop_first(4))) {
		Ok(_) => True
		Err(_) => False
	}
}
expect {
	match Font.from_bytes(FontBuild.u32(0x74746366).concat(FontBuild.file(FontBuild.basic).drop_first(4))) {
		Err(found) => found == [NotAFont]
		Ok(_) => False
	}
}

# A table directory longer than the file.
expect {
	match Font.from_bytes(FontBuild.patch(FontBuild.file(FontBuild.basic), 4, FontBuild.u16(200))) {
		Err(found) => found == [NotAFont]
		Ok(_) => False
	}
}

# Each required table missing on its own.
expect ["head", "hhea", "maxp", "cmap"].all(|tag| problems_of(FontBuild.without(FontBuild.basic, tag)) == [MissingTable(tag)])

# Without `head`, `hhea` or `maxp` the tables that depend on them are not
# read, so only the missing table is reported.
expect problems_of(FontBuild.without(FontBuild.basic.append({ tag: "GPOS", data: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] }), "maxp")) == [MissingTable("maxp")]

# Tables too short for their fields, and empty counts.
expect problems_of(basic_with("head", FontBuild.head(1000, False).drop_last(1))) == [BadTable("head")]
expect problems_of(basic_with("hhea", FontBuild.hhea(800, -200, 4).drop_last(1))) == [BadTable("hhea")]
expect problems_of(basic_with("hhea", FontBuild.hhea(800, -200, 0))) == [BadTable("hhea")]
expect problems_of(basic_with("maxp", FontBuild.maxp(0))) == [BadTable("maxp")]
expect problems_of(basic_with("maxp", [0, 0, 0, 0, 0])) == [BadTable("maxp")]
expect problems_of(basic_with("OS/2", FontBuild.os2({ use_typo: False, typo_ascent: 0, typo_descent: 0, win_ascent: 0, win_descent: 0 }).take_first(77))) == [BadTable("OS/2")]
expect problems_of(basic_with("cmap", [0, 0, 0])) == [BadTable("cmap")]

# A table whose length runs past the end of the file.
expect {
	bytes = FontBuild.file(FontBuild.basic)
	# The first record is `head`; its length is at byte 12 + 12.
	match Font.from_bytes(FontBuild.patch(bytes, 24, FontBuild.u32(100000))) {
		Err(found) => found == [BadTable("head")]
		Ok(_) => False
	}
}
expect {
	bytes = FontBuild.file(FontBuild.basic)
	match Font.from_bytes(FontBuild.patch(bytes, 20, FontBuild.u32(0xFFFFFFFF))) {
		Err(found) => found == [BadTable("head")]
		Ok(_) => False
	}
}

# Units per em must lie in 16 to 16384.
expect problems_of(basic_with("head", FontBuild.head(15, False))) == [BadUnitsPerEm]
expect problems_of(basic_with("head", FontBuild.head(16385, False))) == [BadUnitsPerEm]
expect problems_of(basic_with("head", FontBuild.head(0, False))) == [BadUnitsPerEm]
expect problems_of(basic_with("head", FontBuild.head(16, False))) == []
expect problems_of(basic_with("head", FontBuild.head(16384, False))) == []

# Independent problems are reported together, in table order.
expect {
	tables = FontBuild.basic
		.map(
			|t|
				if t.tag == "head" {
					{ tag: t.tag, data: FontBuild.head(1, False) }
				} else if t.tag == "hhea" {
					{ tag: t.tag, data: FontBuild.hhea(1, 1, 0) }
				} else if t.tag == "cmap" {
					{ tag: t.tag, data: FontBuild.cmap([{ system: 2, encoding: 0, subtable: FontBuild.cmap4([]) }]) }
				} else {
					t
				},
		)
		.append({ tag: "OS/2", data: [0] })
	problems_of(tables) == [BadUnitsPerEm, BadTable("hhea"), NoUnicodeMapping, BadTable("OS/2")]
}

expect {
	tables = FontBuild.basic
		.map(|t| if (t.tag == "hmtx") { tag: t.tag, data: [0, 1] } else t)
		.concat([{ tag: "GSUB", data: List.repeat(0xFF, 12) }, { tag: "GPOS", data: List.repeat(0xFF, 12) }, { tag: "loca", data: [0] }, { tag: "glyf", data: [] }])
	problems_of(tables) == [BadTable("GSUB"), BadTable("hmtx"), BadTable("loca"), BadTable("GPOS")]
}

# Every prefix of a font, and every byte of it set to 0 or 0xFF, is read or
# rejected with problems; nothing crashes.
full_font : List(U8)
full_font = {
	outlines = FontBuild.outlines(outline_glyphs, False)
	FontBuild.file(
		FontBuild.basic.concat([
			{ tag: "OS/2", data: FontBuild.os2({ use_typo: True, typo_ascent: 900, typo_descent: -300, win_ascent: 1000, win_descent: 400 }) },
			{ tag: "loca", data: outlines.loca },
			{ tag: "glyf", data: outlines.glyf },
			{ tag: "GPOS", data: gpos([{ kind: 2, subtables: [simple_pairs] }]) },
			{ tag: "GSUB", data: FontBuild.layout("latn", [{ tag: "liga", lookups: [0] }], [{ kind: 4, subtables: [FontBuild.pack([U16(1), Ref(FontBuild.coverage1([1])), U16(1), Ref(FontBuild.pack([U16(1), Ref(FontBuild.pack([U16(3), U16(2), U16(2)]))]))])] }]) },
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
	match Font.from_bytes(FontBuild.sample) {
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
					match Font.from_bytes(FontBuild.scaled(choices, copies)) {
						Ok(font) => Font.glyph_total(font) == 16 + 4 * choices.len() * copies
						Err(_) => False
					},
			),
	)
}

# Patching bytes wraps positions to the length.
expect FontBuild.mutate([1, 2, 3], [0, 0, 4, 9, 0, 0, 0, 7, 0, 0]) == [7, 9, 3]
expect FontBuild.mutate([], [0, 0, 4, 9]) == []

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
	subtable = FontBuild.pair1(0x05 + 0x0A, 0, [{ glyph: 1, pairs: [{ second: 2, values: [7, 8, -40, 9] }] }])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2]) == [-40.0, 0.0]
}

# A record without an x advance adjusts nothing.
expect {
	subtable = FontBuild.pair1(0x01, 0, [{ glyph: 1, pairs: [{ second: 2, values: [7] }] }])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2]) == [0.0, 0.0]
}

# With a value for the second glyph, the second glyph is adjusted and the
# pair after it is skipped.
expect {
	subtable = FontBuild.pair1(4, 4, [{ glyph: 1, pairs: [{ second: 2, values: [-10, 5] }] }, { glyph: 2, pairs: [{ second: 3, values: [-7, 0] }] }])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 3, 1, 2]) == [-10.0, 5.0, 0.0, -10.0, 5.0]
}
expect {
	subtable = FontBuild.pair1(4, 0, [{ glyph: 1, pairs: [{ second: 2, values: [-10] }] }, { glyph: 2, pairs: [{ second: 3, values: [-7] }] }])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 3]) == [-10.0, -7.0, 0.0]
}

# Format 2: classes. Glyph 1 is first class 0, glyphs 2 and 3 first class
# 1; glyphs 2 and 3 are second class 1, others second class 0.
class_pairs : List(U8)
class_pairs = FontBuild.pair2(4, 0, FontBuild.coverage1([1, 2, 3]), FontBuild.classes1(1, [0, 1, 1]), FontBuild.classes2([{ first: 2, last: 3, class: 1 }]), 2, 2, [0, -11, -22, -33])

expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [class_pairs] }])), [1, 2, 3, 1, 0, 1]) == [-11.0, -33.0, -22.0, 0.0, 0.0, 0.0]

# A first glyph outside the coverage is not adjusted, even when its class
# has values.
expect {
	subtable = FontBuild.pair2(4, 0, FontBuild.coverage1([2]), FontBuild.classes1(1, [1, 1, 1]), FontBuild.classes2([]), 2, 1, [0, -5])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 3]) == [0.0, -5.0, 0.0]
}

# A class past the class counts is not adjusted.
expect {
	subtable = FontBuild.pair2(4, 0, FontBuild.coverage1([1, 2]), FontBuild.classes1(1, [0, 5]), FontBuild.classes1(1, [7, 0, 0]), 1, 1, [-5])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 2, 1, 1]) == [-5.0, 0.0, 0.0, 0.0, 0.0]
}

# Format 2 with a second value record skips the pair after it.
expect {
	subtable = FontBuild.pair2(4, 4, FontBuild.coverage1([1, 2, 3]), FontBuild.classes1(1, [0, 0, 0]), FontBuild.classes1(1, [0, 0, 0]), 1, 1, [-3, 2])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 3]) == [-3.0, 2.0, 0.0]
}

# In a lookup, the first subtable that has the pair decides it; later
# lookups add to it.
expect {
	first = FontBuild.pair1(4, 0, [{ glyph: 1, pairs: [{ second: 3, values: [-1] }] }])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [first, simple_pairs] }])), [1, 2, 1, 3]) == [-50.0, 20.0, -1.0, 0.0]
}
expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [simple_pairs] }, { kind: 2, subtables: [class_pairs] }])), [1, 2]) == [-61.0, 0.0]

# Extension lookups (type 9) hold their subtables behind a 32-bit offset.
expect kerning_of(basic_with("GPOS", gpos([{ kind: 9, subtables: [FontBuild.extension(2, simple_pairs), FontBuild.extension(2, class_pairs)] }])), [1, 2, 3]) == [-50.0, -33.0, 0.0]

# Lookups of other types, extensions of other types, and lookups of other
# features are not kerning.
expect kerning_of(basic_with("GPOS", gpos([{ kind: 1, subtables: [simple_pairs] }, { kind: 9, subtables: [FontBuild.extension(4, simple_pairs)] }])), [1, 2]) == [0.0, 0.0]
expect kerning_of(basic_with("GPOS", FontBuild.layout("DFLT", [{ tag: "mark", lookups: [0] }], [{ kind: 2, subtables: [simple_pairs] }])), [1, 2]) == [0.0, 0.0]

# Pair formats 1 and 2 with a coverage of format 2.
expect {
	subtable = FontBuild.pack([U16(1), Ref(FontBuild.coverage2([{ first: 1, last: 2, index: 0 }])), U16(4), U16(0), U16(2), Ref(FontBuild.pack([U16(1), U16(3), I16(-9)])), Ref(FontBuild.pack([U16(1), U16(3), I16(-8)]))])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 3, 2, 3]) == [-9.0, 0.0, -8.0, 0.0]
}

# A GPOS table takes precedence over a `kern` table.
expect kerning_of(basic_with("GPOS", gpos([])).append({ tag: "kern", data: FontBuild.kern([{ coverage: 1, pairs: [{ left: 1, right: 2, value: -5 }] }]) }), [1, 2]) == [0.0, 0.0]

# Broken GPOS tables: a lookup index past the lookups, an unknown pair
# format, a coverage past the table, a truncated table, and pair sets that
# do not fit.
expect problems_of(basic_with("GPOS", FontBuild.layout("DFLT", [{ tag: "kern", lookups: [3] }], [{ kind: 2, subtables: [simple_pairs] }]))) == [BadTable("GPOS")]
expect problems_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [FontBuild.patch(simple_pairs, 0, FontBuild.u16(3))] }]))) == [BadTable("GPOS")]
expect problems_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [FontBuild.patch(simple_pairs, 2, FontBuild.u16(60000))] }]))) == [BadTable("GPOS")]
expect problems_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [simple_pairs] }]).drop_last(3))) == [BadTable("GPOS")]
expect problems_of(basic_with("GPOS", [0, 1, 0, 0, 0, 10, 0, 10, 0, 10, 0, 0])) == []
expect problems_of(basic_with("GPOS", [0, 1, 0, 0, 0, 10, 0, 10, 0, 10])) == [BadTable("GPOS")]
expect problems_of(basic_with("GPOS", [0, 1, 0, 0, 0, 10, 0])) == [BadTable("GPOS")]

# A class grid larger than the table.
expect problems_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [FontBuild.pair2(4, 0, FontBuild.coverage1([1]), FontBuild.classes1(1, [0]), FontBuild.classes1(1, [0]), 100, 100, [])] }]))) == [BadTable("GPOS")]

## fuzz regression: a class grid whose value records are empty takes no
## bytes however many classes it has; it must not take time or memory in
## proportion to the 65535 x 65535 cells.
expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [FontBuild.pair2(0, 0, FontBuild.coverage1([1]), FontBuild.classes1(1, [0]), FontBuild.classes1(1, [0]), 65535, 65535, [])] }])), [1, 2]) == [0.0, 0.0]

# Coverage ranges that overlap are read as browsers read them, and are
# not expanded glyph by glyph: a few bytes of them could list billions of
# glyphs. A range that goes backwards covers nothing.
expect {
	ranges = List.repeat({ first: 0, last: 65535, index: 0 }, 20).append({ first: 9, last: 2, index: 0 })
	subtable = FontBuild.pack([U16(1), Ref(FontBuild.coverage2(ranges)), U16(4), U16(0), U16(0)])
	tables = basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }]))
	problems_of(tables) == [] and kerning_of(tables, [1, 2]) == [0.0, 0.0]
}
expect {
	set = FontBuild.pack([U16(1), U16(2), I16(-9)])
	subtable = FontBuild.pack([U16(1), Ref(FontBuild.coverage2([{ first: 3, last: 1, index: 0 }, { first: 1, last: 1, index: 0 }])), U16(4), U16(0), U16(1), Ref(set)])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 3, 2]) == [-9.0, 0.0, 0.0, 0.0]
}

# A pair set shared by many first glyphs kerns every glyph that shares it.
# (That reading keeps one subtable, read in place, is checked inside the
# package: `package/LayoutKerningTests.roc`.)
expect {
	n = 300
	set = FontBuild.pack([U16(n)].concat(FontBuild.counting(n).join_map(|g| [U16(g), I16(-1)])))
	# Every set offset points at the one set, after the coverage.
	subtable = FontBuild.pack([U16(1), U16(10 + 2 * n), U16(4), U16(0), U16(n)].concat(List.repeat(U16(20 + 2 * n), n)).append(Raw(FontBuild.coverage2([{ first: 0, last: n - 1, index: 0 }]))).append(Raw(set)))
	tables = FontBuild.basic
		.map(|t| if (t.tag == "maxp") { tag: t.tag, data: FontBuild.maxp(n) } else t)
		.append({ tag: "GPOS", data: gpos([{ kind: 2, subtables: [subtable] }]) })
	match read_tables(tables) {
		Ok(font) => Font.kerning(font, [5, 7, 299, 0]) == [-1.0, -1.0, -1.0, 0.0]
		Err(_) => False
	}
}

# Many lookups that all point at one lookup with many subtables, all the
# same: more work than the table could describe without sharing, so the
# table is refused.
expect {
	lookups = 300
	header = [U32(0x00010000), U16(10), U16(12), U16(0)]
	features = [U16(0), U16(1), Tag("kern"), U16(8), U16(0), U16(lookups)].concat(FontBuild.counting(lookups).map(|i| U16(i)))
	# The lookup list: every offset points at one lookup after the list.
	lookup_at = 2 + 2 * lookups
	list = [U16(lookups)].concat(List.repeat(U16(lookup_at), lookups))
	lookup = [U16(2), U16(0), U16(lookups)].concat(List.repeat(U16(6 + 2 * lookups), lookups))
	table = FontBuild.pack(header).concat(FontBuild.pack(features)).concat(FontBuild.pack(list)).concat(FontBuild.pack(lookup)).concat(simple_pairs)
	patched = FontBuild.patch(table, 8, FontBuild.u16(24 + 2 * lookups))
	problems_of(basic_with("GPOS", patched)) == [BadTable("GPOS")]
}

# ------------------------------------------------------------ legacy kern

expect kerning_of(basic_with("kern", FontBuild.kern([{ coverage: 1, pairs: [{ left: 1, right: 2, value: -50 }, { left: 2, right: 3, value: -30 }] }])), [1, 2, 3, 1]) == [-50.0, -30.0, 0.0, 0.0]

# Each horizontal subtable is applied in turn and the adjustments add up;
# vertical and cross-stream subtables are ignored.
expect {
	kern = FontBuild.kern([
		{ coverage: 1, pairs: [{ left: 1, right: 2, value: -50 }] },
		{ coverage: 0, pairs: [{ left: 1, right: 2, value: -1000 }] },
		{ coverage: 5, pairs: [{ left: 1, right: 2, value: -2000 }] },
		{ coverage: 1, pairs: [{ left: 1, right: 2, value: 7 }] },
	])
	kerning_of(basic_with("kern", kern), [1, 2]) == [-43.0, 0.0]
}

expect problems_of(basic_with("kern", FontBuild.kern([{ coverage: 1, pairs: [{ left: 1, right: 2, value: -50 }] }]).drop_last(1))) == [BadTable("kern")]
expect problems_of(basic_with("kern", FontBuild.patch(FontBuild.kern([]), 2, FontBuild.u16(3)))) == [BadTable("kern")]

# A `kern` table in Apple's layout (version 1.0), as browsers read it:
# horizontal format 0 subtables kern; vertical, cross-stream and variation
# subtables and other formats do not.
apple_kern : List({ coverage : U64, format : U64, pairs : List({ left : U64, right : U64, value : I64 }) }) -> List(U8)
apple_kern = |subtables| {
	body = subtables.join_map(
		|t| {
			n = t.pairs.len()
			FontBuild.u32(16 + 6 * n)
				.concat([t.coverage.to_u8_wrap(), t.format.to_u8_wrap(), 0, 0])
				.concat(FontBuild.pack([U16(n), U16(0), U16(0), U16(0)].concat(t.pairs.join_map(|p| [U16(p.left), U16(p.right), I16(p.value)]))))
		},
	)
	FontBuild.u32(0x00010000).concat(FontBuild.u32(subtables.len())).concat(body)
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
expect problems_of(basic_with("kern", FontBuild.patch(apple_kern([]), 4, FontBuild.u32(0xFFFFFFFF)))) == [BadTable("kern")]
expect problems_of(basic_with("kern", FontBuild.patch(apple_kern([{ coverage: 0, format: 0, pairs: [] }]), 8, FontBuild.u32(8)))) == [BadTable("kern")]
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
