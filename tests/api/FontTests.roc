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
inter = match Font.from_bytes(inter_file, Font.ReadOptions.{}) {
	Ok(font) => font
	Err(_) => crash "the Inter test font could not be read"
}

expect
	match Font.from_bytes(inter_file, Font.ReadOptions.{}) {
		Ok(font) => Font.glyph_count(font) == 2937 and Font.units_per_em(font) == 2048
		Err(_) => False
	}

expect
	match Font.from_bytes([], Font.ReadOptions.{}) {
		Err(problems) => problems == [NotAFont]
		Ok(_) => False
	}

expect
	match Font.from_bytes([0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], Font.ReadOptions.{}) {
		Err(problems) => kinds(problems) == ["MissingTable(head)", "MissingTable(hhea)", "MissingTable(maxp)", "MissingTable(cmap)"]
		Ok(_) => False
	}

# Inter's default substitutions: `->` becomes one arrow glyph, and an
# asterisk after a capital is raised.
expect {
	run = Font.shape(inter, "->", Font.ShapeOptions.{})
	run.glyphs == [1805] and run.clusters == [0]
}
expect {
	run = Font.shape(inter, "F*", Font.ShapeOptions.{})
	run.glyphs == [137, 1548] and run.clusters == [0, 1]
}
expect Font.shape(inter, "x", Font.ShapeOptions.{}).glyphs == [993]

# A truncated file: its tables run past the end.
expect
	match Font.from_bytes(inter_file.take_first(4096), Font.ReadOptions.{}) {
		Err(problems) => !problems.is_empty() and problems.all(|p| p != NotAFont)
		Ok(_) => False
	}

# Every byte of a font corrupted in turn never crashes reading.
expect {
	var $read = 0
	for k in 0..<16 {
		at = (k * 9973 + 12) % inter_file.len()
		match Font.from_bytes(inter_file.set(at, 0xFF) ?? inter_file, Font.ReadOptions.{}) {
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
read_tables = |tables| Font.from_bytes(FontBuild.file(tables), Font.ReadOptions.{})

problems_of : List({ tag : Str, data : List(U8) }) -> List(Font.Problem)
problems_of = |tables|
	match read_tables(tables) {
		Ok(font) => Font.dropped(font)
		Err(found) => found
	}

kinds_of : List({ tag : Str, data : List(U8) }) -> List(Str)
kinds_of = |tables| kinds(problems_of(tables))

# `basic` with one table replaced or added.
basic_with : Str, List(U8) -> List({ tag : Str, data : List(U8) })
basic_with = |tag, data| FontBuild.replace(FontBuild.basic, tag, data)

# The glyph of each code point, 9999 where the font has none.
glyphs_for : List({ tag : Str, data : List(U8) }), List(U32) -> List(U32)
glyphs_for = |tables, code_points|
	match read_tables(tables) {
		Ok(font) => code_points.map(|cp| Font.glyph(font, cp) ?? 9999)
		Err(_) => []
	}

# A font whose only character map is the given subtable.
cmap_only : U64, U64, List(U8) -> List({ tag : Str, data : List(U8) })
cmap_only = |system, encoding, subtable| basic_with("cmap", FontBuild.cmap([{ system, encoding, subtable }]))

# A font whose character map holds the given subtable and an empty format 4
# map for platform 0, encoding 0, which every other map outranks: OTS
# refuses a font without a map it passes on, so a map OTS does not pass on
# (formats 6 and 10, a Macintosh map) needs it beside.
cmap_beside : U64, U64, List(U8) -> List({ tag : Str, data : List(U8) })
cmap_beside = |system, encoding, subtable| basic_with("cmap", FontBuild.cmap([{ system: 0, encoding: 0, subtable: FontBuild.cmap4([]) }, { system, encoding, subtable }]))

# A valid format 14 subtable: one variation selector (U+FE00) whose
# default table holds U+0041.
variations : List(U8)
variations = FontBuild.pack([U16(14), U32(29), U32(1), Raw([0x00, 0xFE, 0x00]), U32(21), U32(0), U32(1), Raw([0x00, 0x00, 0x41, 0x00])])

# The problems of a font as short names: those that rejected it, or those
# lenient reading dropped. `BadTable` loses its offset here; tests of
# offsets compare problems whole.
kinds : List(Font.Problem) -> List(Str)
kinds = |problems|
	problems.map(
		|p|
			match p {
				NotAFont => "NotAFont"
				NoSuchFace(_) => "NoSuchFace"
				OverLimit(which) => "OverLimit(${which})"
				MissingTable(tag) => "MissingTable(${tag})"
				BadTable(b) => "BadTable(${b.table})"
				BadUnitsPerEm => "BadUnitsPerEm"
				NoUnicodeMapping => "NoUnicodeMapping"
			},
	)

# The text the basic fonts draw with glyphs 0 to 3: `@` (unmapped), `A`,
# `B` and `C`.
letters : List(U64) -> Str
letters = |glyphs| Str.from_utf8(glyphs.map(|g| if (g == 0) '@' else (0x40 + g).to_u8_wrap())) ?? ""

# The change kerning makes to each glyph's advance, for text drawn with
# these glyphs and no substitutions.
kerning : Font, List(U64), Str -> List(I32)
kerning = |font, glyphs, text| {
	run = Font.shape(font, text, Font.ShapeOptions.{ features: [Font.Feature.{ tag: "liga", value: 0 }, Font.Feature.{ tag: "calt", value: 0 }] })
	if run.glyphs.map(|g| g.to_u64()) != glyphs {
		[9999]
	} else {
		run.glyphs.map2(run.advances, |g, a| a.x - Font.advance(font, g))
	}
}

kerning_of : List({ tag : Str, data : List(U8) }), List(U64) -> List(I32)
kerning_of = |tables, glyphs|
	match read_tables(tables) {
		Ok(font) => kerning(font, glyphs, letters(glyphs))
		Err(_) => [9999]
	}

# Each glyph's offset after kerning.
offsets_of : List({ tag : Str, data : List(U8) }), List(U64) -> List({ x : I32, y : I32 })
offsets_of = |tables, glyphs|
	match read_tables(tables) {
		Ok(font) => Font.shape(font, letters(glyphs), Font.ShapeOptions.{}).offsets
		Err(_) => []
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
# vertical metrics come from `hhea`; without `loca`/`glyf` no glyph's box
# can be measured, so each is `Unknown`.
expect {
	match read_tables(FontBuild.basic) {
		Ok(font) =>
			Font.glyph_count(font) == 4
				and Font.units_per_em(font) == 1000
				and Font.metrics(font).ascent == 800
				and Font.metrics(font).descent == 200
				and [0, 1, 2, 3, 4, 1000000].map(|g| Font.advance(font, g)) == [500, 600, 700, 800, 0, 0]
				and [0, 1, 3].all(|g| Font.extents(font, g) == Unknown)
				and Font.extents(font, 4) == Empty
				and kerning(font, [1, 2, 3], "ABC") == [0, 0, 0]
				and Font.shape(font, "A", Font.ShapeOptions.{}).glyphs == [1]
				and Font.dropped(font) == []
		Err(_) => False
	}
}

# Reading is deterministic.
expect FontBuild.file(FontBuild.basic) == FontBuild.file(FontBuild.basic)
expect {
	bytes = FontBuild.file(FontBuild.basic)
	match (Font.from_bytes(bytes, Font.ReadOptions.{}), Font.from_bytes(bytes, Font.ReadOptions.{})) {
		(Ok(a), Ok(b)) => {
			glyphs = [0, 1, 2, 3, 4]
			glyphs.map(|g| Font.advance(a, g)) == glyphs.map(|g| Font.advance(b, g))
				and [0x40, 0x41, 0x43].map(|c| Font.glyph(a, c)) == [0x40, 0x41, 0x43].map(|c| Font.glyph(b, c))
				and glyphs.map(|g| Font.extents(a, g)) == glyphs.map(|g| Font.extents(b, g))
				and Font.metrics(a).ascent == Font.metrics(b).ascent
				and Font.metrics(a).descent == Font.metrics(b).descent
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

# A delta segment whose glyphs wrap past 65535 to 0 mid-segment names
# glyphs 65534 and 65535, which the font does not have: a bad table, as OTS
# refuses it (no font has glyph 65535, so a wrapping segment is always
# refused). Glyph 0 at the start of a segment is unmapped.
expect kinds_of(cmap_only(3, 1, FontBuild.cmap4([{ first: 0x41, last: 0x45, delta: 65536 - 0x43, glyphs: [] }]))) == ["BadTable(cmap)"]
expect glyphs_for(cmap_only(3, 1, FontBuild.cmap4([{ first: 0x41, last: 0x43, delta: 65536 - 0x41, glyphs: [] }, { first: 0x44, last: 0x44, delta: 65536 + 3 - 0x44, glyphs: [] }])), [0x41, 0x42, 0x43, 0x44]) == [9999, 1, 2, 3]

# A glyph array segment that ends at U+FFFF needs no entry for it.
expect {
	cmap = FontBuild.cmap4([{ first: 0xFFFD, last: 0xFFFE, delta: 0, glyphs: [2, 3] }])
	glyphs_for(cmap_only(3, 1, cmap), [0xFFFC, 0xFFFD, 0xFFFE, 0xFFFF]) == [9999, 2, 3, 9999]
}

# Platform 0 (Unicode) is a Unicode mapping too.
expect glyphs_for(cmap_only(0, 3, FontBuild.cmap4([{ first: 0x41, last: 0x41, delta: 65536 - 0x40, glyphs: [] }])), [0x41]) == [1]

# A character mapped to a glyph the font does not have is a bad table, as
# OTS refuses it, by a delta or through the glyph array.
expect {
	cmap = FontBuild.cmap4([{ first: 0x44, last: 0x44, delta: 65536 + 9 - 0x44, glyphs: [] }])
	kinds_of(cmap_only(3, 1, cmap)) == ["BadTable(cmap)"]
}
expect kinds_of(cmap_only(3, 1, FontBuild.cmap4([{ first: 0x45, last: 0x46, delta: 0, glyphs: [2, 4] }]))) == ["BadTable(cmap)"]

# Segments out of order are a bad table.
expect {
	cmap = FontBuild.cmap4([{ first: 0x50, last: 0x51, delta: 0, glyphs: [] }, { first: 0x41, last: 0x42, delta: 0, glyphs: [] }])
	kinds_of(cmap_only(3, 1, cmap)) == ["BadTable(cmap)"]
}

expect {
	cmap = FontBuild.cmap4([{ first: 0x41, last: 0x45, delta: 0, glyphs: [] }, { first: 0x45, last: 0x46, delta: 0, glyphs: [] }])
	kinds_of(cmap_only(3, 1, cmap)) == ["BadTable(cmap)"]
}

# A glyph array that runs past the end of the table.
expect {
	table = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 0x41, last: 0x43, delta: 0, glyphs: [1, 2, 3] }]) }])
	kinds_of(basic_with("cmap", table.drop_last(2))) == ["BadTable(cmap)"]
}

# A segment count larger than the table.
expect {
	table = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.u16(4).concat(FontBuild.u16(14)).concat(FontBuild.u16(0)).concat(FontBuild.u16(0xFFFE)).concat(List.repeat(0, 6)) }])
	kinds_of(basic_with("cmap", table)) == ["BadTable(cmap)"]
}

# ------------------------------------------------------------ cmap format 12

expect {
	cmap = FontBuild.cmap12([{ first: 0x41, last: 0x43, glyph: 1 }, { first: 0x1F600, last: 0x1F601, glyph: 2 }])
	glyphs_for(cmap_only(3, 10, cmap), [0x40, 0x41, 0x43, 0x44, 0x1F5FF, 0x1F600, 0x1F601, 0x1F602, 0x10FFFF]) == [9999, 1, 3, 9999, 9999, 2, 3, 9999, 9999]
}

# A group whose glyphs run past the last glyph is a bad table, as OTS
# refuses it.
expect kinds_of(cmap_only(3, 10, FontBuild.cmap12([{ first: 0x50, last: 0x55, glyph: 2 }]))) == ["BadTable(cmap)"]
expect kinds_of(cmap_only(3, 10, FontBuild.cmap12([{ first: 0x60, last: 0x60, glyph: 4 }]))) == ["BadTable(cmap)"]

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

expect kinds_of(cmap_only(3, 10, FontBuild.cmap12([{ first: 0x50, last: 0x55, glyph: 1 }, { first: 0x41, last: 0x42, glyph: 1 }]))) == ["BadTable(cmap)"]
expect kinds_of(cmap_only(3, 10, FontBuild.cmap12([{ first: 0x50, last: 0x55, glyph: 1 }, { first: 0x55, last: 0x56, glyph: 1 }]))) == ["BadTable(cmap)"]
expect kinds_of(cmap_only(3, 10, FontBuild.cmap12([{ first: 0x50, last: 0x4F, glyph: 1 }]))) == ["BadTable(cmap)"]
expect kinds_of(cmap_only(3, 10, FontBuild.cmap12([{ first: 0x10FFFF, last: 0x110000, glyph: 1 }]))) == ["BadTable(cmap)"]

# A huge group count is checked against the table before anything is
# allocated.
expect {
	subtable = FontBuild.u16(12).concat(FontBuild.u16(0)).concat(FontBuild.u32(16)).concat(FontBuild.u32(0)).concat(FontBuild.u32(0xFFFFFFFF))
	kinds_of(cmap_only(3, 10, subtable)) == ["BadTable(cmap)"]
}

# ------------------------------------------------------------ cmap format 0

# Character codes up to 255 index a byte array; glyph 0 and glyphs the font
# does not have leave a code unmapped (OTS does not check this format's
# glyph ids outside the Macintosh Roman map).
expect {
	glyphs = List.repeat(0, 0x41).concat([1, 0, 3, 9])
	glyphs_for(cmap_beside(0, 3, FontBuild.cmap0(glyphs)), [0x40, 0x41, 0x42, 0x43, 0x44, 0xFF, 0x100, 0x141]) == [9999, 1, 9999, 3, 9999, 9999, 9999, 9999]
}

# A truncated byte array is a bad table.
expect kinds_of(cmap_only(3, 1, FontBuild.cmap0([1, 2, 3]).drop_last(1))) == ["BadTable(cmap)"]

# ------------------------------------------------------------ cmap formats 6 and 10

# A trimmed array maps consecutive codes from its first; codes before or
# after it are unmapped. OTS does not check these formats, so their glyph
# ids may name glyphs the font does not have; those are unmapped.
expect glyphs_for(cmap_beside(3, 1, FontBuild.cmap6(0x41, [1, 0, 3, 7])), [0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x10041]) == [9999, 1, 9999, 3, 9999, 9999, 9999]
expect glyphs_for(cmap_beside(3, 10, FontBuild.cmap10(0x1F600, [2, 3])), [0x1F5FF, 0x1F600, 0x1F601, 0x1F602, 0xF600]) == [9999, 2, 3, 9999, 9999]

# An empty array maps nothing.
expect glyphs_for(cmap_beside(3, 1, FontBuild.cmap6(0x41, [])), [0x41]) == [9999]

# An array past the end of the table, or a count larger than the table
# (checked before anything is read), is a bad table when the map is
# chosen. (OTS does not check these formats, so this is stricter than OTS;
# no font of the corpus has such a map.)
expect kinds_of(cmap_beside(3, 1, FontBuild.cmap6(0x41, [1, 2]).drop_last(1))) == ["BadTable(cmap)"]
expect kinds_of(cmap_beside(3, 1, FontBuild.cmap6(0x41, []).take_first(8))) == ["BadTable(cmap)"]
expect kinds_of(cmap_beside(3, 10, FontBuild.cmap10(0x41, [1, 2]).drop_last(1))) == ["BadTable(cmap)"]
expect kinds_of(cmap_beside(3, 10, FontBuild.patch(FontBuild.cmap10(0x41, [1]), 16, FontBuild.u32(0xFFFFFFFF)))) == ["BadTable(cmap)"]

# A map of a format OTS does not pass on (here 6), with no map it does, is
# no map to use, as OTS refuses the font.
expect kinds_of(cmap_only(3, 1, FontBuild.cmap6(0x41, [1]))) == ["NoUnicodeMapping"]

# ------------------------------------------------------------ cmap format 13

# Every character of a group maps to the group's one glyph.
expect {
	cmap = FontBuild.cmap13([{ first: 0x41, last: 0x5A, glyph: 2 }, { first: 0x10000, last: 0x10FFFF, glyph: 3 }])
	glyphs_for(cmap_only(3, 10, cmap), [0x40, 0x41, 0x50, 0x5A, 0x5B, 0xFFFF, 0x10000, 0x10FFFF]) == [9999, 2, 2, 2, 9999, 9999, 3, 3]
}

# A group whose glyph the font does not have maps nothing, in a format 13
# map OTS does not check (platform 0, encoding 6); for platform 3,
# encoding 10 OTS refuses it.
expect kinds_of(cmap_only(3, 10, FontBuild.cmap13([{ first: 0x41, last: 0x43, glyph: 4 }]))) == ["BadTable(cmap)"]
expect glyphs_for(cmap_beside(0, 6, FontBuild.cmap13([{ first: 0x41, last: 0x43, glyph: 4 }])), [0x41, 0x43]) == [9999, 9999]

# Groups out of order, overlapping or past Unicode, and a truncated table,
# are bad tables.
expect kinds_of(cmap_only(3, 10, FontBuild.cmap13([{ first: 0x50, last: 0x55, glyph: 1 }, { first: 0x41, last: 0x42, glyph: 1 }]))) == ["BadTable(cmap)"]
expect kinds_of(cmap_only(3, 10, FontBuild.cmap13([{ first: 0x50, last: 0x55, glyph: 1 }, { first: 0x55, last: 0x56, glyph: 1 }]))) == ["BadTable(cmap)"]
expect kinds_of(cmap_only(3, 10, FontBuild.cmap13([{ first: 0x41, last: 0x110000, glyph: 1 }]))) == ["BadTable(cmap)"]
expect kinds_of(cmap_only(3, 10, FontBuild.cmap13([{ first: 0x41, last: 0x42, glyph: 1 }]).drop_last(1))) == ["BadTable(cmap)"]

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
expect glyphs_for(cmap_beside(3, 0, FontBuild.cmap12([{ first: 0xF041, last: 0xF042, glyph: 1 }])), [0x41, 0x42, 0x43]) == [1, 2, 9999]

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

# A Macintosh map alone is no map to use: OTS refuses a font without a
# Unicode or Windows map it can pass on, and every such map outranks a
# Macintosh one.
expect {
	glyphs = List.repeat(0, 0x41).concat([1])
	kinds_of(cmap_only(1, 0, FontBuild.cmap0(glyphs))) == ["NoUnicodeMapping"]
		and kinds_of(cmap_only(1, 1, FontBuild.cmap0(glyphs))) == ["NoUnicodeMapping"]
}

# The order of preference, whatever the record order: full Unicode maps
# (3, 10), (0, 6), (0, 4), then (3, 1), (0, 3) to (0, 0), then Macintosh.
expect {
	a_to = |g| FontBuild.cmap4([{ first: 0x41, last: 0x41, delta: 65536 + g - 0x41, glyphs: [] }])
	pick = |records| glyphs_for(basic_with("cmap", FontBuild.cmap(records.map(|r| { system: r.system, encoding: r.encoding, subtable: a_to(r.glyph) }))), [0x41])
	pick([{ system: 1, encoding: 0, glyph: 3 }, { system: 0, encoding: 0, glyph: 2 }]) == [2]
		and pick([{ system: 0, encoding: 3, glyph: 2 }, { system: 3, encoding: 1, glyph: 1 }]) == [1]
		and pick([{ system: 3, encoding: 1, glyph: 1 }, { system: 0, encoding: 4, glyph: 3 }]) == [3]
		and pick([{ system: 0, encoding: 4, glyph: 3 }, { system: 3, encoding: 10, glyph: 2 }, { system: 3, encoding: 1, glyph: 1 }]) == [2]
		and pick([{ system: 0, encoding: 1, glyph: 3 }, { system: 0, encoding: 2, glyph: 1 }]) == [1]
}

# A subtable in a format that is not read (here 8, and 14, which holds
# variation sequences) is passed over for the next preferred one.
expect {
	table = FontBuild.cmap([
		{ system: 0, encoding: 3, subtable: FontBuild.cmap4([{ first: 0x41, last: 0x41, delta: 65536 + 2 - 0x41, glyphs: [] }]) },
		{ system: 0, encoding: 5, subtable: variations },
		{ system: 3, encoding: 1, subtable: FontBuild.u16(8).concat(List.repeat(0, 30)) },
	])
	glyphs_for(basic_with("cmap", table), [0x41]) == [2]
}

# No map to use: an unknown platform or encoding, only formats that are not
# read, or no subtables at all.
expect kinds_of(cmap_only(2, 1, FontBuild.cmap4([{ first: 0x41, last: 0x41, delta: 0, glyphs: [] }]))) == ["NoUnicodeMapping"]
expect kinds_of(cmap_only(3, 2, FontBuild.cmap12([{ first: 0x41, last: 0x41, glyph: 1 }]))) == ["NoUnicodeMapping"]
expect kinds_of(cmap_only(0, 5, variations)) == ["NoUnicodeMapping"]
expect kinds_of(cmap_only(3, 1, FontBuild.u16(2).concat(List.repeat(0, 8)))) == ["NoUnicodeMapping"]
expect kinds_of(basic_with("cmap", FontBuild.u16(0).concat(FontBuild.u16(0)))) == ["NoUnicodeMapping"]

# The chosen record's offset past the end of the table is a bad table, not
# a missing map.
expect kinds_of(basic_with("cmap", FontBuild.u16(0).concat(FontBuild.u16(1)).concat(FontBuild.u16(3)).concat(FontBuild.u16(1)).concat(FontBuild.u32(5000)))) == ["BadTable(cmap)"]

# A broken map is a bad table even when it is not chosen: OTS checks every
# map it passes on.
expect {
	table = FontBuild.cmap([
		{ system: 1, encoding: 0, subtable: FontBuild.cmap0([]).take_first(10) },
		{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 0x41, last: 0x41, delta: 65536 + 1 - 0x41, glyphs: [] }]) },
	])
	kinds_of(basic_with("cmap", table)) == ["BadTable(cmap)"]
}

# A bad character map is reported with the other tables' problems.
expect {
	tables = basic_with("cmap", FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap13([{ first: 0x50, last: 0x55, glyph: 1 }, { first: 0x41, last: 0x42, glyph: 1 }]) }]))
		.map(|t| if (t.tag == "maxp") { tag: t.tag, data: FontBuild.maxp(0) } else t)
	kinds_of(tables) == ["BadTable(maxp)", "BadTable(cmap)"]
}

# More encoding records than the table holds.
expect kinds_of(basic_with("cmap", FontBuild.u16(0).concat(FontBuild.u16(3)).concat(List.repeat(0, 8)))) == ["BadTable(cmap)"]

# ------------------------------------------------------------ hmtx

# Glyphs past the long metrics take the last advance.
expect {
	match read_tables(FontBuild.basic.map(|t| if (t.tag == "hhea") { tag: t.tag, data: FontBuild.hhea(800, -200, 2) } else if (t.tag == "hmtx") { tag: t.tag, data: FontBuild.hmtx([500, 600]).concat([0, 0, 0, 0]) } else t)) {
		Ok(font) => [0, 1, 2, 3, 4].map(|g| Font.advance(font, g)) == [500, 600, 600, 600, 0]
		Err(_) => False
	}
}

# One long metric covers every glyph.
expect {
	match read_tables(FontBuild.basic.map(|t| if (t.tag == "hhea") { tag: t.tag, data: FontBuild.hhea(800, -200, 1) } else if (t.tag == "hmtx") { tag: t.tag, data: FontBuild.hmtx([432]).concat(List.repeat(0, 6)) } else t)) {
		Ok(font) => [0, 1, 2, 3].map(|g| Font.advance(font, g)) == [432, 432, 432, 432]
		Err(_) => False
	}
}

# More long metrics than glyphs: only the glyphs' metrics are needed.
expect {
	match read_tables(basic_with("hhea", FontBuild.hhea(800, -200, 60000))) {
		Ok(font) => Font.advance(font, 3) == 800
		Err(_) => False
	}
}

# The largest advance a font can hold.
expect {
	match read_tables(basic_with("hmtx", FontBuild.hmtx([65535, 0, 1, 2]))) {
		Ok(font) => Font.advance(font, 0) == 65535
		Err(_) => False
	}
}

expect kinds_of(basic_with("hmtx", FontBuild.hmtx([500, 600, 700]))) == ["BadTable(hmtx)"]
expect kinds_of(FontBuild.without(FontBuild.basic, "hmtx")) == ["MissingTable(hmtx)"]

# ------------------------------------------------------------ loca and glyf

outline_glyphs : List(List(U8))
outline_glyphs = [[], FontBuild.outline(10, 490), [], FontBuild.outline(-5, 700)]

with_outlines : Bool, { loca : List(U8), glyf : List(U8) } -> List({ tag : Str, data : List(U8) })
with_outlines = |long, tables|
	basic_with("head", FontBuild.head(1000, long))
		.append({ tag: "loca", data: tables.loca })
		.append({ tag: "glyf", data: tables.glyf })

inks_of : List({ tag : Str, data : List(U8) }) -> List([Extents({ x_min : I32, y_min : I32, x_max : I32, y_max : I32 }), Empty, Unknown])
inks_of = |tables|
	match read_tables(tables) {
		Ok(font) => [0, 1, 2, 3, 4].map(|g| Font.extents(font, g))
		Err(_) => []
	}

# Glyph extents from short and from long offsets; glyphs without an
# outline, and glyph indices past the last glyph, have no ink. As in
# HarfBuzz, the box is the glyph header's, with its left edge at the left
# side bearing in `hmtx` (0 in these fonts) rather than at `xMin`.
expect inks_of(with_outlines(False, FontBuild.outlines(outline_glyphs, False))) == [Empty, Extents({ x_min: 0, y_min: 0, x_max: 480, y_max: 100 }), Empty, Extents({ x_min: 0, y_min: 0, x_max: 705, y_max: 100 }), Empty]
expect inks_of(with_outlines(True, FontBuild.outlines(outline_glyphs, True))) == [Empty, Extents({ x_min: 0, y_min: 0, x_max: 480, y_max: 100 }), Empty, Extents({ x_min: 0, y_min: 0, x_max: 705, y_max: 100 }), Empty]

# The side bearing places the box: glyph 1 has a bearing of 25, glyph 3
# one of -40.
expect {
	tables = with_outlines(False, FontBuild.outlines(outline_glyphs, False)).map(|t| if (t.tag == "hmtx") { tag: t.tag, data: FontBuild.pack([U16(500), I16(0), U16(600), I16(25), U16(700), I16(0), U16(800), I16(-40)]) } else t)
	inks_of(tables) == [Empty, Extents({ x_min: 25, y_min: 0, x_max: 505, y_max: 100 }), Empty, Extents({ x_min: -40, y_min: 0, x_max: 665, y_max: 100 }), Empty]
}

# A glyph shorter than its header rejects the font, as OTS rejects it; one
# whose header box is inverted is measured from its smaller to its larger
# edge, as HarfBuzz measures it.
expect kinds_of(with_outlines(False, FontBuild.outlines([[], [1, 2, 3, 4], FontBuild.outline(5, 4), []], False))) == ["BadTable(glyf)"]
expect inks_of(with_outlines(False, FontBuild.outlines([[], [], FontBuild.outline(5, 4), []], False))) == [Empty, Empty, Extents({ x_min: 0, y_min: 0, x_max: 1, y_max: 100 }), Empty, Empty]

# The `loca` format must match `head`: short offsets read as long ones
# run past the end of `loca`.
expect kinds_of(with_outlines(True, FontBuild.outlines(outline_glyphs, False))) == ["BadTable(loca)"]

# Too few offsets, an offset past `glyf`, and offsets that go backwards.
expect kinds_of(with_outlines(False, { loca: FontBuild.outlines(outline_glyphs, False).loca.drop_last(2), glyf: FontBuild.outlines(outline_glyphs, False).glyf })) == ["BadTable(loca)"]
expect kinds_of(with_outlines(False, { loca: [0, 0, 0, 10, 0, 10, 0, 20, 0, 25], glyf: FontBuild.outlines(outline_glyphs, False).glyf })) == ["BadTable(loca)"]
expect kinds_of(with_outlines(False, { loca: [0, 0, 0, 5, 0, 5, 0, 2, 0, 10], glyf: FontBuild.outlines(outline_glyphs, False).glyf })) == ["BadTable(loca)"]

# `loca` without `glyf` (or the reverse) is no outlines: every glyph of the
# font is `Unknown`, and an id past the font `Empty`.
expect inks_of(basic_with("loca", FontBuild.outlines(outline_glyphs, False).loca)) == [Unknown, Unknown, Unknown, Unknown, Empty]

# ------------------------------------------------------------ vertical metrics

vertical_of : List({ tag : Str, data : List(U8) }) -> { ascent : I32, descent : I32 }
vertical_of = |tables|
	match read_tables(tables) {
		Ok(font) => { ascent: Font.metrics(font).ascent, descent: Font.metrics(font).descent }
		Err(_) => { ascent: -1, descent: -1 }
	}

expect vertical_of(basic_with("OS/2", FontBuild.os2({ use_typo: True, typo_ascent: 900, typo_descent: -300, win_ascent: 1000, win_descent: 400 }))) == { ascent: 900, descent: 300 }
expect vertical_of(basic_with("OS/2", FontBuild.os2({ use_typo: False, typo_ascent: 900, typo_descent: -300, win_ascent: 1000, win_descent: 400 }))) == { ascent: 800, descent: 200 }
expect vertical_of(FontBuild.replace(basic_with("hhea", FontBuild.hhea(0, 0, 4)), "OS/2", FontBuild.os2({ use_typo: False, typo_ascent: 900, typo_descent: -300, win_ascent: 1000, win_descent: 400 }))) == { ascent: 900, descent: 300 }
expect vertical_of(FontBuild.replace(basic_with("hhea", FontBuild.hhea(0, 0, 4)), "OS/2", FontBuild.os2({ use_typo: False, typo_ascent: 0, typo_descent: 0, win_ascent: 1000, win_descent: 400 }))) == { ascent: 1000, descent: 400 }
expect vertical_of(basic_with("hhea", FontBuild.hhea(0, 0, 4))) == { ascent: 0, descent: 0 }

# ------------------------------------------------------------ problems

expect Font.from_bytes(List.repeat(0, 11), Font.ReadOptions.{}).is_err()
expect kinds_of([]) == ["MissingTable(head)", "MissingTable(hhea)", "MissingTable(maxp)", "MissingTable(cmap)"]

# Signatures: TrueType, `true` and `OTTO` are fonts; a collection is not.
expect {
	match Font.from_bytes(FontBuild.u32(0x74727565).concat(FontBuild.file(FontBuild.basic).drop_first(4)), Font.ReadOptions.{}) {
		Ok(_) => True
		Err(_) => False
	}
}
expect {
	match Font.from_bytes(FontBuild.u32(0x4F54544F).concat(FontBuild.file(FontBuild.basic).drop_first(4)), Font.ReadOptions.{}) {
		Ok(_) => True
		Err(_) => False
	}
}
expect {
	# A collection signature on a font's header reads as a collection of no
	# faces.
	match Font.from_bytes(FontBuild.u32(0x74746366).concat(FontBuild.file(FontBuild.basic).drop_first(4)), Font.ReadOptions.{}) {
		Err(found) => found == [NoSuchFace({ face: 0, count: 0 })]
		Ok(_) => False
	}
}

# A table directory longer than the file.
expect {
	match Font.from_bytes(FontBuild.patch(FontBuild.file(FontBuild.basic), 4, FontBuild.u16(200)), Font.ReadOptions.{}) {
		Err(found) => found == [NotAFont]
		Ok(_) => False
	}
}

# Each required table missing on its own.
expect ["head", "hhea", "maxp", "cmap"].all(|tag| kinds_of(FontBuild.without(FontBuild.basic, tag)) == ["MissingTable(${tag})"])

# Without `head`, `hhea` or `maxp` the tables that depend on them are not
# read, so only the missing table is reported.
expect kinds_of(FontBuild.without(FontBuild.basic.append({ tag: "GPOS", data: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] }), "maxp")) == ["MissingTable(maxp)"]

# Tables too short for their fields, and empty counts.
expect kinds_of(basic_with("head", FontBuild.head(1000, False).drop_last(1))) == ["BadTable(head)"]
expect kinds_of(basic_with("hhea", FontBuild.hhea(800, -200, 4).drop_last(1))) == ["BadTable(hhea)"]
expect kinds_of(basic_with("hhea", FontBuild.hhea(800, -200, 0))) == ["BadTable(hhea)"]
expect kinds_of(basic_with("maxp", FontBuild.maxp(0))) == ["BadTable(maxp)"]
expect kinds_of(basic_with("maxp", [0, 0, 0, 0, 0])) == ["BadTable(maxp)"]
expect kinds_of(basic_with("OS/2", FontBuild.os2({ use_typo: False, typo_ascent: 0, typo_descent: 0, win_ascent: 0, win_descent: 0 }).take_first(77))) == ["BadTable(OS/2)"]
expect kinds_of(basic_with("cmap", [0, 0, 0])) == ["BadTable(cmap)"]

# A table whose length runs past the end of the file.
expect {
	bytes = FontBuild.file(FontBuild.basic)
	# The first record is `head`; its length is at byte 12 + 12.
	match Font.from_bytes(FontBuild.patch(bytes, 24, FontBuild.u32(100000)), Font.ReadOptions.{}) {
		Err(found) => kinds(found) == ["BadTable(head)"]
		Ok(_) => False
	}
}
expect {
	bytes = FontBuild.file(FontBuild.basic)
	match Font.from_bytes(FontBuild.patch(bytes, 20, FontBuild.u32(0xFFFFFFFF)), Font.ReadOptions.{}) {
		Err(found) => kinds(found) == ["BadTable(head)"]
		Ok(_) => False
	}
}

# Units per em must lie in 16 to 16384.
expect kinds_of(basic_with("head", FontBuild.head(15, False))) == ["BadUnitsPerEm"]
expect kinds_of(basic_with("head", FontBuild.head(16385, False))) == ["BadUnitsPerEm"]
expect kinds_of(basic_with("head", FontBuild.head(0, False))) == ["BadUnitsPerEm"]
expect kinds_of(basic_with("head", FontBuild.head(16, False))) == []
expect kinds_of(basic_with("head", FontBuild.head(16384, False))) == []

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
	kinds_of(tables) == ["BadUnitsPerEm", "BadTable(hhea)", "NoUnicodeMapping", "BadTable(OS/2)"]
}

expect {
	tables = FontBuild.basic
		.map(|t| if (t.tag == "hmtx") { tag: t.tag, data: [0, 1] } else t)
		.concat([{ tag: "GSUB", data: List.repeat(0xFF, 12) }, { tag: "GPOS", data: List.repeat(0xFF, 12) }, { tag: "loca", data: [0] }, { tag: "glyf", data: [0, 0, 0, 0] }])
	kinds_of(tables) == ["BadTable(hmtx)", "BadTable(loca)", "BadTable(GSUB)", "BadTable(GPOS)"]
}

# An empty table rejects the font, as OTS rejects it, whichever table it is.
expect {
	tables = FontBuild.basic.append({ tag: "zzzz", data: [] })
	kinds_of(tables) == ["BadTable(zzzz)"]
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
	match Font.from_bytes(full_font, Font.ReadOptions.{}) {
		Ok(font) =>
			kerning(font, [1, 2], "AB") == [-50, 0]
				and Font.shape(font, "AB", Font.ShapeOptions.{}).glyphs == [3]
				and Font.metrics(font).ascent == 900
		Err(_) => False
	}
}

expect {
	var $outcomes = 0
	for n in 0..<full_font.len() {
		match Font.from_bytes(full_font.take_first(n), Font.ReadOptions.{}) {
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
			match Font.from_bytes(full_font.set(at, value) ?? [], Font.ReadOptions.{}) {
				Ok(font) => {
					# Queries on whatever was read are total.
					_ = Font.shape(font, "@ABCAB", Font.ShapeOptions.{})
					_ = Font.metrics(font)
					$outcomes = $outcomes + (if (Font.units_per_em(font) >= 16) 1 else 1000000)
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
	match Font.from_bytes(FontBuild.sample, Font.ReadOptions.{}) {
		Ok(font) =>
			Font.glyph_count(font) == 40
				and Font.units_per_em(font) == 2048
				and Font.metrics(font).ascent == 1800
				and Font.metrics(font).descent == 400
				and [0x41, 0x5A, 0x61, 0x1F600].map(|cp| Font.glyph(font, cp) ?? 9999) == [1, 26, 9999, 30]
				and [0, 3, 39].map(|g| Font.advance(font, g)) == [1000, 1300, 1300]
				and [0, 1, 2].map(|g| Font.extents(font, g)) == [Empty, Extents({ x_min: 0, y_min: 0, x_max: 14, y_max: 100 }), Extents({ x_min: 0, y_min: 0, x_max: 23, y_max: 100 })]
				and kerning(font, [1, 2], "AB") == [-61, 2]
				and Font.shape(font, "GABC", Font.ShapeOptions.{}).glyphs == [7, 11, 2, 3]
		Err(_) => False
	}
}

# The fonts the scaling fuzz target builds read, at every size.
expect {
	[[0, 1, 2, 3, 4, 5], [1, 2, 3, 4, 5, 0], [2, 4], [3, 3, 3], [5], []].all(
		|choices|
			[1, 2, 16].all(
				|copies|
					match Font.from_bytes(FontBuild.scaled(choices, copies), Font.ReadOptions.{}) {
						Ok(font) => Font.glyph_count(font).to_u64() == 16 + 4 * choices.len() * copies
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
expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [simple_pairs] }])), [1, 2, 3, 1]) == [-50, 0, 0, 0]
expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [simple_pairs] }])), [2, 1, 3]) == [20, -30, 0]
expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [simple_pairs] }])), []) == []
expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [simple_pairs] }])), [1]) == [0]
expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [simple_pairs] }])), [1, 0, 2]) == [0, 0, 0]

# The x advance is found after an x placement in the value record; other
# fields are ignored.
expect {
	subtable = FontBuild.pair1(0x05 + 0x0A, 0, [{ glyph: 1, pairs: [{ second: 2, values: [7, 8, -40, 9] }] }])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2]) == [-40, 0]
}

# A record without an x advance adjusts nothing.
expect {
	subtable = FontBuild.pair1(0x01, 0, [{ glyph: 1, pairs: [{ second: 2, values: [7] }] }])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2]) == [0, 0]
}

# With a value for the second glyph, the second glyph is adjusted and the
# pair after it is skipped.
expect {
	subtable = FontBuild.pair1(4, 4, [{ glyph: 1, pairs: [{ second: 2, values: [-10, 5] }] }, { glyph: 2, pairs: [{ second: 3, values: [-7, 0] }] }])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 3, 1, 2]) == [-10, 5, 0, -10, 5]
}
expect {
	subtable = FontBuild.pair1(4, 0, [{ glyph: 1, pairs: [{ second: 2, values: [-10] }] }, { glyph: 2, pairs: [{ second: 3, values: [-7] }] }])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 3]) == [-10, -7, 0]
}

# Format 2: classes. Glyph 1 is first class 0, glyphs 2 and 3 first class
# 1; glyphs 2 and 3 are second class 1, others second class 0.
class_pairs : List(U8)
class_pairs = FontBuild.pair2(4, 0, FontBuild.coverage1([1, 2, 3]), FontBuild.classes1(1, [0, 1, 1]), FontBuild.classes2([{ first: 2, last: 3, class: 1 }]), 2, 2, [0, -11, -22, -33])

expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [class_pairs] }])), [1, 2, 3, 1, 0, 1]) == [-11, -33, -22, 0, 0, 0]

# A first glyph outside the coverage is not adjusted, even when its class
# has values.
expect {
	subtable = FontBuild.pair2(4, 0, FontBuild.coverage1([2]), FontBuild.classes1(1, [1, 1, 1]), FontBuild.classes2([]), 2, 1, [0, -5])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 3]) == [0, -5, 0]
}

# A class past the class counts is not adjusted.
expect {
	subtable = FontBuild.pair2(4, 0, FontBuild.coverage1([1, 2]), FontBuild.classes1(1, [0, 5]), FontBuild.classes1(1, [7, 0, 0]), 1, 1, [-5])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 2, 1, 1]) == [-5, 0, 0, 0, 0]
}

# Format 2 with a second value record skips the pair after it.
expect {
	subtable = FontBuild.pair2(4, 4, FontBuild.coverage1([1, 2, 3]), FontBuild.classes1(1, [0, 0, 0]), FontBuild.classes1(1, [0, 0, 0]), 1, 1, [-3, 2])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 3]) == [-3, 2, 0]
}

# In a lookup, the first subtable that has the pair decides it; later
# lookups add to it.
expect {
	first = FontBuild.pair1(4, 0, [{ glyph: 1, pairs: [{ second: 3, values: [-1] }] }])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [first, simple_pairs] }])), [1, 2, 1, 3]) == [-50, 20, -1, 0]
}
expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [simple_pairs] }, { kind: 2, subtables: [class_pairs] }])), [1, 2]) == [-61, 0]

# Extension lookups (type 9) hold their subtables behind a 32-bit offset.
expect kerning_of(basic_with("GPOS", gpos([{ kind: 9, subtables: [FontBuild.extension(2, simple_pairs), FontBuild.extension(2, class_pairs)] }])), [1, 2, 3]) == [-50, -33, 0]

# Lookups of other types and extensions of other types are not pair
# positioning. Pair lookups of any default feature apply, as in HarfBuzz
# (here `mark`); those of other features do not (here `cpsp`, capital
# spacing, which is off by default).
# Every implemented positioning kind is validated. Pair bytes mislabeled as
# single or mark positioning are malformed, not unsupported no-ops.
expect kinds_of(basic_with("GPOS", gpos([{ kind: 1, subtables: [simple_pairs] }, { kind: 9, subtables: [FontBuild.extension(4, simple_pairs)] }]))) == ["BadTable(GPOS)"]
expect kerning_of(basic_with("GPOS", FontBuild.layout("DFLT", [{ tag: "mark", lookups: [0] }], [{ kind: 2, subtables: [simple_pairs] }])), [1, 2]) == [-50, 0]
expect kerning_of(basic_with("GPOS", FontBuild.layout("DFLT", [{ tag: "cpsp", lookups: [0] }], [{ kind: 2, subtables: [simple_pairs] }])), [1, 2]) == [0, 0]

# Pair formats 1 and 2 with a coverage of format 2.
expect {
	subtable = FontBuild.pack([U16(1), Ref(FontBuild.coverage2([{ first: 1, last: 2, index: 0 }])), U16(4), U16(0), U16(2), Ref(FontBuild.pack([U16(1), U16(3), I16(-9)])), Ref(FontBuild.pack([U16(1), U16(3), I16(-8)]))])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 3, 2, 3]) == [-9, 0, -8, 0]
}

# A GPOS table takes precedence over a `kern` table.
expect kerning_of(basic_with("GPOS", gpos([])).append({ tag: "kern", data: FontBuild.kern([{ coverage: 1, pairs: [{ left: 1, right: 2, value: -5 }] }]) }), [1, 2]) == [0, 0]

# Broken GPOS tables: a lookup index past the lookups, an unknown pair
# format, a coverage past the table, a truncated table, and pair sets that
# do not fit.
expect {
	# A feature's lookup index past the lookup list is passed over, as
	# HarfBuzz passes over it.
	tables = basic_with("GPOS", FontBuild.layout("DFLT", [{ tag: "kern", lookups: [3, 0] }], [{ kind: 2, subtables: [simple_pairs] }]))
	kinds_of(tables) == [] and kerning_of(tables, [1, 2]) == [-50, 0]
}
expect kinds_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [FontBuild.patch(simple_pairs, 0, FontBuild.u16(3))] }]))) == ["BadTable(GPOS)"]
expect kinds_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [FontBuild.patch(simple_pairs, 2, FontBuild.u16(60000))] }]))) == ["BadTable(GPOS)"]
expect kinds_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [simple_pairs] }]).drop_last(3))) == ["BadTable(GPOS)"]
expect kinds_of(basic_with("GPOS", [0, 1, 0, 0, 0, 10, 0, 10, 0, 10, 0, 0])) == []
expect kinds_of(basic_with("GPOS", [0, 1, 0, 0, 0, 10, 0, 10, 0, 10])) == ["BadTable(GPOS)"]
expect kinds_of(basic_with("GPOS", [0, 1, 0, 0, 0, 10, 0])) == ["BadTable(GPOS)"]

# A class grid larger than the table.
expect kinds_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [FontBuild.pair2(4, 0, FontBuild.coverage1([1]), FontBuild.classes1(1, [0]), FontBuild.classes1(1, [0]), 100, 100, [])] }]))) == ["BadTable(GPOS)"]

## fuzz regression: a class grid whose value records are empty takes no
## bytes however many classes it has; it must not take time or memory in
## proportion to the 65535 x 65535 cells.
expect kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [FontBuild.pair2(0, 0, FontBuild.coverage1([1]), FontBuild.classes1(1, [0]), FontBuild.classes1(1, [0]), 65535, 65535, [])] }])), [1, 2]) == [0, 0]

# Coverage ranges that overlap are read as browsers read them, and are
# not expanded glyph by glyph: a few bytes of them could list billions of
# glyphs. A range that goes backwards covers nothing.
expect {
	ranges = List.repeat({ first: 0, last: 65535, index: 0 }, 20).append({ first: 9, last: 2, index: 0 })
	subtable = FontBuild.pack([U16(1), Ref(FontBuild.coverage2(ranges)), U16(4), U16(0), U16(0)])
	tables = basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }]))
	kinds_of(tables) == [] and kerning_of(tables, [1, 2]) == [0, 0]
}
expect {
	set = FontBuild.pack([U16(1), U16(2), I16(-9)])
	subtable = FontBuild.pack([U16(1), Ref(FontBuild.coverage2([{ first: 3, last: 1, index: 0 }, { first: 1, last: 1, index: 0 }])), U16(4), U16(0), U16(1), Ref(set)])
	kerning_of(basic_with("GPOS", gpos([{ kind: 2, subtables: [subtable] }])), [1, 2, 3, 2]) == [-9, 0, 0, 0]
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
		.map(|t| if (t.tag == "maxp") { tag: t.tag, data: FontBuild.maxp(n) } else if (t.tag == "hmtx") { tag: t.tag, data: t.data.concat(List.repeat(0, 2 * (n - 4))) } else t)
		.append({ tag: "GPOS", data: gpos([{ kind: 2, subtables: [subtable] }]) })
	# Glyph g is drawn by U+10000 + g.
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 0x10001, last: 0x10000 + n - 1, glyph: 1 }]) }])
	match read_tables(FontBuild.replace(tables, "cmap", cmap)) {
		Ok(font) => kerning(font, [5, 7, 299, 0], "\u(10005)\u(10007)\u(1012B)\u(10000)") == [-1, -1, -1, 0]
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
	kinds_of(basic_with("GPOS", patched)) == ["BadTable(GPOS)"]
}

# ------------------------------------------------------------ legacy kern

# HarfBuzz splits a `kern` table's value across the pair: half (rounded
# down) on the first glyph's advance, the rest on the second glyph's
# advance and as its offset, so the width is the same.
expect kerning_of(basic_with("kern", FontBuild.kern([{ coverage: 1, pairs: [{ left: 1, right: 2, value: -50 }, { left: 2, right: 3, value: -30 }] }])), [1, 2, 3, 1]) == [-25, -40, -15, 0]
expect offsets_of(basic_with("kern", FontBuild.kern([{ coverage: 1, pairs: [{ left: 1, right: 2, value: -50 }, { left: 2, right: 3, value: -31 }] }])), [1, 2, 3, 1]) == [{ x: 0, y: 0 }, { x: -25, y: 0 }, { x: -15, y: 0 }, { x: 0, y: 0 }]

# Each horizontal subtable is applied in turn and the adjustments add up;
# a cross-stream subtable (coverage 5) is kept but does not kern.
expect {
	kern = FontBuild.kern([
		{ coverage: 1, pairs: [{ left: 1, right: 2, value: -50 }] },
		{ coverage: 5, pairs: [{ left: 1, right: 2, value: -2000 }] },
		{ coverage: 1, pairs: [{ left: 1, right: 2, value: 7 }] },
	])
	kerning_of(basic_with("kern", kern), [1, 2]) == [-22, -21]
}

expect kinds_of(basic_with("kern", FontBuild.kern([{ coverage: 1, pairs: [{ left: 1, right: 2, value: -50 }] }]).drop_last(1))) == ["BadTable(kern)"]
expect kinds_of(basic_with("kern", FontBuild.patch(FontBuild.kern([]), 2, FontBuild.u16(3)))) == ["BadTable(kern)"]

# Reserved coverage bits are malformed. Valid vertical-only and empty
# tables remain usable font data; neither changes a horizontal run.
# A wrong binary search field (`entrySelector`) rejects the font.
expect {
	tables = [
		FontBuild.kern([{ coverage: 0x11, pairs: [{ left: 1, right: 2, value: -50 }] }]),
	]
	tables.all(|kern| kinds_of(basic_with("kern", kern)) == ["BadTable(kern)"] and kerning_of(basic_with("kern", kern), [1, 2]) == [0, 0])
}
expect {
	tables = [FontBuild.kern([{ coverage: 0, pairs: [{ left: 1, right: 2, value: -50 }] }]), FontBuild.kern([{ coverage: 1, pairs: [] }])]
	tables.all(|kern| kinds_of(basic_with("kern", kern)).is_empty() and kerning_of(basic_with("kern", kern), [1, 2]) == [0, 0])
}
expect {
	kern = FontBuild.patch(FontBuild.kern([{ coverage: 1, pairs: [{ left: 1, right: 2, value: -50 }, { left: 2, right: 3, value: -5 }] }]), 4 + 10, FontBuild.u16(0))
	read_tables(basic_with("kern", kern)).is_err()
}

# Apple's version 1.0 kerning is supported directly, including fonts
# whose tables OTS would drop. Cached Apple oracle cases cover this path.
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
	kern = apple_kern([{ coverage: 0, format: 0, pairs: [{ left: 1, right: 2, value: -50 }] }])
	kinds_of(basic_with("kern", kern)).is_empty() and kerning_of(basic_with("kern", kern), [1, 2]) == [-25, -25]
}

# ------------------------------------------------------------ Inter

# Known values, checked against fontTools and HarfBuzz reading the same
# file.
expect {
	font = inter
	Font.metrics(font).ascent == 1984 and Font.metrics(font).descent == 494 and Font.glyph_count(font) == 2937
}
expect {
	font = inter
	cps = [0x41, 0x56, 0x54, 0x6F, 0x2D, 0x3E, 0x20, 0x2A, 0x31, 0xE9, 0x20AC, 0x2192, 0x1F852, 0x378, 0x10FFFF]
	cps.map(|cp| Font.glyph(font, cp) ?? 9999) == [2, 456, 411, 790, 1459, 1517, 1777, 1547, 1342, 618, 1316, 1805, 1807, 9999, 9999]
}
expect {
	font = inter
	[2, 456, 411, 790, 1459, 1517, 1777, 1547, 1342, 618, 1316, 1805, 2936].map(|g| Font.advance(font, g)) == [1413, 1413, 1322, 1228, 942, 1355, 576, 1026, 833, 1194, 1365, 1954, 434]
}
# The metrics subset keeps each glyph's header box but no contours (a
# contour count of 0), so every glyph is empty, as HarfBuzz reports it
# (zero extents).
expect {
	font = inter
	[0, 2, 1547, 1548, 1777, 1805, 2936].all(|g| Font.extents(font, g) == Empty)
}

# Kerning pairs A V, T o, V A, A A, W a, y period, T y, L T, and A with the
# raised asterisk.
expect {
	font = inter
	pairs = [("AV", [2, 456]), ("To", [411, 790]), ("VA", [456, 2]), ("AA", [2, 2]), ("Wa", [459, 507]), ("y.", [998, 1502]), ("Ty", [411, 998]), ("LT", [281, 411]), ("A*", [2, 1548])]
	# Default features: the raised asterisk is a contextual alternate.
	pairs.map(
		|(text, glyphs)| {
			run = Font.shape(font, text, Font.ShapeOptions.{})
			if (run.glyphs == glyphs) run.glyphs.map2(run.advances, |g, adv| adv.x - Font.advance(font, g)) else [9999]
		},
	) == [[-140, 0], [-160, 0], [-140, 0], [30, 0], [-104, 0], [-90, 0], [-128, 0], [-197, 0], [-69, 0]]
}

# Inter shaped by HarfBuzz 15.0 (through uharfbuzz 0.57.0) with its default
# features: the glyphs, the first character each draws, and each glyph's
# advance including kerning, in font units.
inter_cases : List({ text : Str, code_points : List(U32), glyphs : List(U32), clusters : List(U64), advances : List(I32) })
inter_cases = [
	{ text: "Hello World", code_points: [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100], glyphs: [161, 614, 736, 736, 790, 1777, 459, 790, 852, 736, 597], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], advances: [1522, 1194, 496, 496, 1228, 576, 1914, 1228, 803, 496, 1254] },
	{ text: "A->B", code_points: [65, 45, 62, 66], glyphs: [2, 1829, 65], clusters: [0, 1, 3], advances: [1413, 1954, 1340] },
	{ text: "x --> y", code_points: [120, 32, 45, 45, 62, 32, 121], glyphs: [993, 1777, 1806, 1777, 998], clusters: [0, 1, 2, 5, 6], advances: [1118, 576, 2746, 576, 1151] },
	{ text: "<->", code_points: [60, 45, 62], glyphs: [1814], clusters: [0], advances: [2746] },
	{ text: "->>", code_points: [45, 62, 62], glyphs: [1805, 1517], clusters: [0, 2], advances: [1954, 1355] },
	{ text: "<-", code_points: [60, 45], glyphs: [1800], clusters: [0], advances: [1954] },
	{ text: "=>", code_points: [61, 62], glyphs: [1808], clusters: [0], advances: [1954] },
	{ text: "<=", code_points: [60, 61], glyphs: [1516, 1520], clusters: [0, 1], advances: [1355, 1355] },
	{ text: "!=", code_points: [33, 61], glyphs: [1427, 1533], clusters: [0, 1], advances: [589, 1355] },
	{ text: "==", code_points: [61, 61], glyphs: [1520, 1520], clusters: [0, 1], advances: [1355, 1355] },
	{ text: "...", code_points: [46, 46, 46], glyphs: [1502, 1502, 1502], clusters: [0, 1, 2], advances: [590, 590, 590] },
	{ text: "--", code_points: [45, 45], glyphs: [1459, 1459], clusters: [0, 1], advances: [942, 942] },
	{ text: "---", code_points: [45, 45, 45], glyphs: [1459, 1459, 1459], clusters: [0, 1, 2], advances: [942, 942, 942] },
	{ text: "A*", code_points: [65, 42], glyphs: [2, 1548], clusters: [0, 1], advances: [1344, 1321] },
	{ text: "1*", code_points: [49, 42], glyphs: [1342, 1548], clusters: [0, 1], advances: [833, 1321] },
	{ text: "a*", code_points: [97, 42], glyphs: [507, 1547], clusters: [0, 1], advances: [1150, 1026] },
	{ text: "A*B", code_points: [65, 42, 66], glyphs: [2, 1548, 65], clusters: [0, 1, 2], advances: [1344, 1321, 1340] },
	{ text: "(a+b)*c", code_points: [40, 97, 43, 98, 41, 42, 99], glyphs: [1437, 507, 1522, 578, 1438, 1547, 586], clusters: [0, 1, 2, 3, 4, 5, 6], advances: [747, 1150, 1355, 1231, 747, 1026, 1170] },
	{ text: "12:30", code_points: [49, 50, 58, 51, 48], glyphs: [1342, 1343, 1506, 1345, 1341], clusters: [0, 1, 2, 3, 4], advances: [833, 1249, 590, 1265, 1292] },
	{ text: "A:B", code_points: [65, 58, 66], glyphs: [2, 1506, 65], clusters: [0, 1, 2], advances: [1413, 590, 1340] },
	{ text: "AVATAR", code_points: [65, 86, 65, 84, 65, 82], glyphs: [2, 456, 2, 411, 2, 384], clusters: [0, 1, 2, 3, 4, 5], advances: [1273, 1273, 1239, 1148, 1413, 1318] },
	{ text: "Tomorrow", code_points: [84, 111, 109, 111, 114, 114, 111, 119], glyphs: [411, 790, 766, 790, 852, 852, 790, 984], clusters: [0, 1, 2, 3, 4, 5, 6, 7], advances: [1162, 1228, 1794, 1228, 803, 737, 1191, 1676] },
	{ text: "WAVE", code_points: [87, 65, 86, 69], glyphs: [459, 2, 456, 95], clusters: [0, 1, 2, 3], advances: [1902, 1273, 1413, 1231] },
	{ text: "Typography", code_points: [84, 121, 112, 111, 103, 114, 97, 112, 104, 121], glyphs: [411, 998, 843, 790, 658, 852, 507, 843, 670, 998], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], advances: [1194, 1151, 1254, 1228, 1256, 771, 1150, 1254, 1181, 1151] },
	{ text: "LT", code_points: [76, 84], glyphs: [281, 411], clusters: [0, 1], advances: [961, 1322] },
	{ text: "Yo", code_points: [89, 111], glyphs: [472, 790], clusters: [0, 1], advances: [1233, 1228] },
	{ text: "P.", code_points: [80, 46], glyphs: [375, 1502], clusters: [0, 1], advances: [1239, 590] },
	{ text: "r,", code_points: [114, 44], glyphs: [852, 1501], clusters: [0, 1], advances: [643, 590] },
	{ text: "\"quoted\"", code_points: [34, 113, 117, 111, 116, 101, 100, 34], glyphs: [1485, 849, 915, 790, 889, 614, 597, 1485], clusters: [0, 1, 2, 3, 4, 5, 6, 7], advances: [924, 1254, 1211, 1228, 650, 1194, 1254, 954] },
	{ text: "[box]", code_points: [91, 98, 111, 120, 93], glyphs: [1439, 578, 790, 993, 1441], clusters: [0, 1, 2, 3, 4], advances: [747, 1254, 1182, 1118, 747] },
	{ text: "{curly}", code_points: [123, 99, 117, 114, 108, 121, 125], glyphs: [1443, 586, 915, 852, 736, 998, 1444], clusters: [0, 1, 2, 3, 4, 5, 6], advances: [850, 1170, 1211, 803, 506, 1151, 873] },
	{ text: "A/B", code_points: [65, 47, 66], glyphs: [2, 1455, 65], clusters: [0, 1, 2], advances: [1453, 738, 1340] },
	{ text: "50%", code_points: [53, 48, 37], glyphs: [1347, 1341, 1744], clusters: [0, 1, 2], advances: [1215, 1292, 2011] },
	{ text: "office fi fl", code_points: [111, 102, 102, 105, 99, 101, 32, 102, 105, 32, 102, 108], glyphs: [790, 647, 647, 689, 586, 614, 1777, 647, 689, 1777, 647, 736], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], advances: [1228, 678, 758, 496, 1170, 1194, 576, 758, 496, 576, 758, 496] },
	{ text: "Façade", code_points: [70, 97, 231, 97, 100, 101], glyphs: [137, 507, 589, 507, 597, 614], clusters: [0, 1, 2, 3, 4, 5], advances: [1159, 1150, 1190, 1150, 1254, 1194] },
	{ text: "Ünïcödé", code_points: [220, 110, 239, 99, 246, 100, 233], glyphs: [429, 773, 692, 586, 791, 597, 618], clusters: [0, 1, 2, 3, 4, 5, 6], advances: [1524, 1210, 496, 1170, 1228, 1254, 1194] },
	{ text: "€100 → £5", code_points: [8364, 49, 48, 48, 32, 8594, 32, 163, 53], glyphs: [1316, 1342, 1341, 1341, 1777, 1829, 1777, 1312, 1347], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8], advances: [1365, 833, 1292, 1292, 576, 1954, 576, 1251, 1215] },
	{ text: "x×y", code_points: [120, 215, 121], glyphs: [993, 1524, 998], clusters: [0, 1, 2], advances: [1118, 1355, 1151] },
	{ text: "αβγ", code_points: [945, 946, 947], glyphs: [1110, 1136, 1137], clusters: [0, 1, 2], advances: [1360, 1220, 1151] },
	{ text: "Привет", code_points: [1055, 1088, 1080, 1074, 1077, 1090], glyphs: [2434, 848, 1262, 1254, 641, 1280], clusters: [0, 1, 2, 3, 4, 5], advances: [1522, 1254, 1211, 1157, 1194, 954] },
	{ text: "Is it ready?", code_points: [73, 115, 32, 105, 116, 32, 114, 101, 97, 100, 121, 63], glyphs: [197, 871, 1777, 689, 889, 1777, 852, 614, 507, 597, 998, 1431], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], advances: [550, 1081, 576, 496, 670, 576, 737, 1214, 1150, 1264, 1151, 1047] },
	{ text: "Start", code_points: [83, 116, 97, 114, 116], glyphs: [397, 889, 507, 852, 889], clusters: [0, 1, 2, 3, 4], advances: [1314, 680, 1150, 803, 670] },
	{ text: "End", code_points: [69, 110, 100], glyphs: [95, 773, 597], clusters: [0, 1, 2], advances: [1231, 1210, 1254] },
	{ text: "Process data", code_points: [80, 114, 111, 99, 101, 115, 115, 32, 100, 97, 116, 97], glyphs: [375, 852, 790, 586, 614, 871, 871, 1777, 597, 507, 889, 507], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], advances: [1308, 737, 1228, 1170, 1194, 1081, 1081, 576, 1254, 1150, 680, 1150] },
	{ text: "#1", code_points: [35, 49], glyphs: [1453, 1342], clusters: [0, 1], advances: [1297, 833] },
	{ text: "@at ~tilde ^caret _under_", code_points: [64, 97, 116, 32, 126, 116, 105, 108, 100, 101, 32, 94, 99, 97, 114, 101, 116, 32, 95, 117, 110, 100, 101, 114, 95], glyphs: [1445, 507, 889, 1777, 1528, 889, 689, 736, 597, 614, 1777, 1546, 586, 507, 852, 614, 889, 1777, 1543, 915, 773, 597, 614, 852, 1543], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24], advances: [1978, 1150, 670, 576, 1355, 670, 496, 496, 1254, 1194, 576, 965, 1190, 1150, 737, 1194, 670, 576, 934, 1211, 1210, 1254, 1194, 771, 934] },
	{ text: "1/2", code_points: [49, 47, 50], glyphs: [1342, 1455, 1343], clusters: [0, 1, 2], advances: [833, 738, 1249] },
	{ text: "+-", code_points: [43, 45], glyphs: [1522, 1459], clusters: [0, 1], advances: [1355, 942] },
	{ text: ":-)", code_points: [58, 45, 41], glyphs: [1506, 1471, 1447], clusters: [0, 1, 2], advances: [590, 942, 747] },
]

# Clusters in the cases are indices of code points; the run gives UTF-8
# byte offsets.
inter_shaped : { text : Str, code_points : List(U32), glyphs : List(U32), clusters : List(U64), advances : List(I32) } -> Bool
inter_shaped = |case| {
	run = Font.shape(inter, case.text, Font.ShapeOptions.{})
	var $offsets = []
	var $at = 0
	for cp in case.code_points {
		$offsets = $offsets.append($at)
		$at = $at + (if (cp < 0x80) 1 else if (cp < 0x800) 2 else if (cp < 0x10000) 3 else 4)
	}
	clusters = case.clusters.map(|c| $offsets.get(c) ?? 9999)
	run.glyphs == case.glyphs and run.clusters == clusters and run.advances.map(|a| a.x) == case.advances and run.advances.all(|a| a.y == 0)
}

expect inter_cases.len() > 40 and inter_cases.keep_if(|case| !inter_shaped(case)).map(|case| case.text) == []
