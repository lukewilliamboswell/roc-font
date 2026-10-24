import font.Font
import build.FontBuild
import "../../tests/fonts/Inter-Regular-metrics.ttf" as inter_file : List(U8)
import "../../tests/fonts/variable/var-mapped.ttf" as mapped_file : List(U8)
import "../../tests/fonts/variable/var-implicit.ttf" as implicit_file : List(U8)
import "../../tests/fonts/variable/var-format1.ttf" as format1_file : List(U8)
import "../../tests/fonts/name-post/mac-roman-v1.ttf" as mac_file : List(U8)
import "../../tests/fonts/name-post/ranking-v2.ttf" as ranking_file : List(U8)
import "../../tests/fonts/name-post/japanese-v3.ttf" as japanese_file : List(U8)

## The tests of reading options, problems, collections, limits, lenient and
## strict reading, metrics, listings, names and variations, through the
## public `Font` API. Values said to be HarfBuzz's come from HarfBuzz 14.6.0
## (uharfbuzz 0.56.3), printed by `tests/api/oracle.py`. Run with
## `roc test tests/api/main.roc`.
ReadTests :: {}.{}

# ------------------------------------------------------------ helpers

lenient : List(U8) -> Try(Font, List(Font.Problem))
lenient = |bytes| Font.from_bytes(bytes, Font.ReadOptions.{})

strict : List(U8) -> Try(Font, List(Font.Problem))
strict = |bytes| Font.from_bytes(bytes, Font.ReadOptions.{ strict: True })

read_or_crash : List(U8) -> Font
read_or_crash = |bytes|
	match lenient(bytes) {
		Ok(font) => font
		Err(_) => crash "a test font could not be read"
	}

# The offset of a table in a file built by `FontBuild.file`.
table_offset : List(U8), Str -> U64
table_offset = |bytes, tag| {
	be = |at, len| bytes.sublist({ start: at, len }).fold(0, |acc, b| acc * 256 + b.to_u64())
	want = tag.to_utf8().fold(0, |acc, b| acc * 256 + b.to_u64())
	count = be(4, 2)
	var $found = 0
	for i in 0..<count {
		if be(12 + 16 * i, 4) == want {
			$found = be(12 + 16 * i + 8, 4)
		}
	}
	$found
}

bad : Str, U64 -> Font.Problem
bad = |table, offset| BadTable({ table, offset: offset.to_u32_wrap() })

# The problems that rejected a font, or that lenient reading dropped.
problems_any : Try(Font, List(Font.Problem)) -> List(Font.Problem)
problems_any = |result|
	match result {
		Ok(font) => Font.dropped(font)
		Err(problems) => problems
	}

# Rejected, with exactly these problems.
rejects : Try(Font, List(Font.Problem)), List(Font.Problem) -> Bool
rejects = |result, expected|
	match result {
		Ok(_) => False
		Err(problems) => problems == expected
	}

# Rejected, rather than read with tables dropped.
rejected : Try(Font, List(Font.Problem)) -> Bool
rejected = |result| result.is_err()

counting : U64, U64 -> List(U32)
counting = |start, end| {
	var $out = []
	var $k = start
	while $k < end {
		$out = $out.append($k.to_u32_wrap())
		$k = $k + 1
	}
	$out
}

tables_of : List(Font.Problem) -> List(Str)
tables_of = |problems|
	problems.map(
		|p|
			match p {
				BadTable(b) => b.table
				MissingTable(t) => "missing ${t}"
				OverLimit(which) => "over ${which}"
				_ => "other"
			},
	)

basic_with : Str, List(U8) -> List({ tag : Str, data : List(U8) })
basic_with = |tag, data| FontBuild.replace(FontBuild.basic, tag, data)

# ------------------------------------------------------------ collections

second_face : List({ tag : Str, data : List(U8) })
second_face = basic_with("hmtx", FontBuild.hmtx([501, 601, 701, 801]))

two_faces : List(U8)
two_faces = FontBuild.collection([FontBuild.basic, second_face])

expect Font.face_count(FontBuild.file(FontBuild.basic)) == Ok(1)
expect Font.face_count(two_faces) == Ok(2)
expect Font.face_count([]) == Err(NotAFont)
expect Font.face_count(List.repeat(0, 40)) == Err(NotAFont)
# A collection whose offset array runs past the file.
expect Font.face_count(two_faces.take_first(14)) == Err(NotAFont)

# Each face of a collection reads by its index, with its own tables.
expect {
	match (lenient(two_faces), Font.from_bytes(two_faces, Font.ReadOptions.{ face: 1 })) {
		(Ok(first), Ok(second)) => Font.advance(first, 1) == 600 and Font.advance(second, 1) == 601 and Font.glyph(second, 'C') == Ok(3)
		_ => False
	}
}
expect rejects(Font.from_bytes(two_faces, Font.ReadOptions.{ face: 2 }), [NoSuchFace({ face: 2, count: 2 })])
expect rejects(Font.from_bytes(FontBuild.file(FontBuild.basic), Font.ReadOptions.{ face: 1 }), [NoSuchFace({ face: 1, count: 1 })])

# A face whose offset points outside the file is not a font.
expect {
	broken = FontBuild.patch(two_faces, 16, FontBuild.u32(1000000))
	rejects(Font.from_bytes(broken, Font.ReadOptions.{ face: 1 }), [NotAFont]) and lenient(broken).is_ok()
}

# ------------------------------------------------------------ limits

expect rejects(Font.from_bytes(FontBuild.file(FontBuild.basic), Font.ReadOptions.{ limits: Font.Limits.{ max_bytes: 100 } }), [OverLimit("max_bytes")])
expect rejects(Font.from_bytes(two_faces, Font.ReadOptions.{ limits: Font.Limits.{ max_faces: 1 } }), [OverLimit("max_faces")])
expect Font.from_bytes(two_faces, Font.ReadOptions.{ limits: Font.Limits.{ max_faces: 2 } }).is_ok()

# A layout table listing more lookups than the limit is dropped, or
# rejects the font when reading is strict.
expect {
	lookups = List.repeat({ kind: 1, subtables: [FontBuild.single1([1, 2, 3], 1)] }, 3)
	bytes = FontBuild.file(basic_with("GSUB", FontBuild.layout("latn", [{ tag: "liga", lookups: [0, 1, 2] }], lookups)))
	small = Font.Limits.{ max_lookups: 2 }
	lenient_ok = match Font.from_bytes(bytes, Font.ReadOptions.{ limits: small }) {
		Ok(font) => Font.dropped(font) == [OverLimit("max_lookups")] and Font.shape(font, "A", Font.ShapeOptions.{}).glyphs == [1]
		Err(_) => False
	}
	default_ok = match lenient(bytes) {
		Ok(font) => Font.dropped(font) == [] and Font.shape(font, "A", Font.ShapeOptions.{}).glyphs == [4]
		Err(_) => False
	}
	lenient_ok and default_ok and rejects(Font.from_bytes(bytes, Font.ReadOptions.{ strict: True, limits: small }), [OverLimit("max_lookups")])
}

# ------------------------------------------------------------ problems name the table and offset

# A field that is wrong: its offset in the file.
expect {
	bytes = FontBuild.file(basic_with("hhea", FontBuild.hhea(800, -200, 0)))
	rejects(lenient(bytes), [bad("hhea", table_offset(bytes, "hhea") + 34)])
}
expect {
	bytes = FontBuild.file(basic_with("maxp", FontBuild.maxp(0)))
	rejects(lenient(bytes), [bad("maxp", table_offset(bytes, "maxp") + 4)])
}

# A table too short for its fields, or past the end of the file: the
# table's offset.
expect {
	bytes = FontBuild.file(basic_with("head", FontBuild.head(1000, False).drop_last(1)))
	rejects(lenient(bytes), [bad("head", table_offset(bytes, "head"))])
}

# A bad character map subtable: its offset.
expect {
	subtable = FontBuild.cmap12([{ first: 0x50, last: 0x55, glyph: 1 }, { first: 0x41, last: 0x42, glyph: 1 }])
	bytes = FontBuild.file(basic_with("cmap", FontBuild.cmap([{ system: 3, encoding: 10, subtable }])))
	# One encoding record: the subtable follows the 4-byte header and the
	# 8-byte record.
	rejects(lenient(bytes), [bad("cmap", table_offset(bytes, "cmap") + 12)])
}

# A `loca` entry past `glyf`: the offset of the first bad entry.
expect {
	glyphs = [[], FontBuild.outline(10, 490), [], FontBuild.outline(-5, 700)]
	boxes = FontBuild.outlines(glyphs, False)
	tables = basic_with("loca", FontBuild.patch(boxes.loca, 4, FontBuild.u16(500))).append({ tag: "glyf", data: boxes.glyf })
	bytes = FontBuild.file(tables)
	rejects(lenient(bytes), [bad("loca", table_offset(bytes, "loca") + 4)])
}

# Every independent problem at once, required tables first, then the
# optional tables that would have been dropped.
expect {
	tables = FontBuild.basic
		.map(|t| if (t.tag == "maxp") { tag: t.tag, data: FontBuild.maxp(0) } else t)
		.concat([{ tag: "OS/2", data: [0] }, { tag: "GSUB", data: [0, 1] }])
		.map(|t| if (t.tag == "head") { tag: t.tag, data: FontBuild.head(5, False) } else t)
	bytes = FontBuild.file(tables)
	rejects(lenient(bytes), [BadUnitsPerEm, bad("maxp", table_offset(bytes, "maxp") + 4), bad("OS/2", table_offset(bytes, "OS/2"))])
}

# A table whose record runs past the end of the file rejects the font,
# even an optional table, as OTS (and so browsers) reject it.
expect {
	bytes = FontBuild.file(FontBuild.basic.append({ tag: "GSUB", data: FontBuild.layout("latn", [], []) }))
	# GSUB is the last record: its length is at 12 + 16 * 5 + 12.
	broken = FontBuild.patch(bytes, 12 + 16 * 5 + 12, FontBuild.u32(100000))
	tables_of(problems_any(lenient(broken))) == ["GSUB"] and rejected(lenient(broken))
}

# ------------------------------------------------------------ lenient and strict reading

# A broken `OS/2`, `post`, `name`, `GSUB`, `GPOS` or `GDEF` rejects the font
# in both modes, naming the table, as OTS (and so a browser) rejects it.
expect {
	broken = [
		{ tag: "OS/2", data: List.repeat(0, 20) },
		{ tag: "post", data: List.repeat(0, 10) },
		{ tag: "name", data: [0, 0] },
		{ tag: "GSUB", data: List.repeat(0xFF, 12) },
		{ tag: "GPOS", data: List.repeat(0xFF, 12) },
		{ tag: "GDEF", data: List.repeat(0xFF, 12) },
	]
	broken.all(
		|t| {
			bytes = FontBuild.file(FontBuild.basic.append(t))
			when_lenient = match lenient(bytes) {
				Ok(_) => False
				Err(problems) => tables_of(problems) == [t.tag]
			}
			when_lenient and strict(bytes).is_err()
		},
	)
}

# A broken `fvar` drops the font's variations, which leaves a static font;
# strict reading rejects the font for it.
expect {
	bytes = FontBuild.file(FontBuild.basic.append({ tag: "fvar", data: List.repeat(0, 10) }))
	read_ok = match lenient(bytes) {
		Ok(font) =>
			tables_of(Font.dropped(font)) == ["fvar"]
				and Font.shape(font, "ABC", Font.ShapeOptions.{}).glyphs == [1, 2, 3]
				and Font.axes(font) == []
		Err(_) => False
	}
	strict_ok = match strict(bytes) {
		Ok(_) => False
		Err(problems) => tables_of(problems) == ["fvar"]
	}
	read_ok and strict_ok
}

# A `GDEF` table OTS accepts reads: version 1.2 with a glyph class
# definition and an empty mark glyph set list.
expect {
	classes = FontBuild.pack([U16(2), U16(1), U16(1), U16(3), U16(1)])
	gdef = FontBuild.pack([U16(1), U16(2), U16(14), U16(0), U16(0), U16(0), U16(14 + 10)]).concat(classes).concat(FontBuild.pack([U16(1), U16(0)]))
	match lenient(FontBuild.file(FontBuild.basic.append({ tag: "GDEF", data: gdef }))) {
		Ok(font) => Font.dropped(font) == []
		Err(_) => False
	}
}

# Glyph classes above 4, a class array starting past the font, and
# version 1.1 are what
# OTS rejects a `GDEF` for.
expect {
	header = |minor| FontBuild.pack([U16(1), U16(minor), U16(12), U16(0), U16(0), U16(0)])
	tables = [
		header(0).concat(FontBuild.pack([U16(2), U16(1), U16(1), U16(3), U16(5)])),
		header(0).concat(FontBuild.pack([U16(1), U16(4), U16(1), U16(1)])),
		header(1).concat(FontBuild.pack([U16(2), U16(1), U16(1), U16(3), U16(1)])),
	]
	tables.all(|gdef| rejected(lenient(FontBuild.file(FontBuild.basic.append({ tag: "GDEF", data: gdef })))))
}

# A font with nothing wrong reads the same either way.
expect {
	bytes = FontBuild.file(FontBuild.basic)
	match (lenient(bytes), strict(bytes)) {
		(Ok(a), Ok(b)) => Font.dropped(a) == [] and Font.dropped(b) == []
		_ => False
	}
}

# A broken required table rejects the font in both modes.
expect lenient(FontBuild.file(basic_with("hmtx", [0, 1]))).is_err() and strict(FontBuild.file(basic_with("hmtx", [0, 1]))).is_err()

# A `kern` table whose pairs are out of order is dropped (OTS drops it),
# and one whose pairs do not fit rejects the font (OTS rejects it).
expect {
	unsorted = FontBuild.kern([{ coverage: 1, pairs: [{ left: 2, right: 3, value: -10 }, { left: 1, right: 2, value: -20 }] }])
	bytes = FontBuild.file(basic_with("kern", unsorted))
	match lenient(bytes) {
		# The second pair is the one out of order: 4 + 14 + 6 bytes in.
		Ok(font) => Font.dropped(font) == [bad("kern", table_offset(bytes, "kern") + 24)]
		Err(_) => False
	}
}
expect {
	short = FontBuild.kern([{ coverage: 1, pairs: [{ left: 1, right: 2, value: -50 }] }]).drop_last(1)
	result = lenient(FontBuild.file(basic_with("kern", short)))
	tables_of(problems_any(result)) == ["kern"] and rejected(result)
}

# When `GPOS` is left out (over the lookup limit), a `kern` table kerns
# instead, as when the font has no `GPOS`.
expect {
	kern = FontBuild.kern([{ coverage: 1, pairs: [{ left: 1, right: 2, value: -50 }] }])
	gpos = FontBuild.layout("latn", [], [{ kind: 1, subtables: [] }])
	bytes = FontBuild.file(basic_with("kern", kern).append({ tag: "GPOS", data: gpos }))
	match Font.from_bytes(bytes, Font.ReadOptions.{ limits: Font.Limits.{ max_lookups: 0 } }) {
		Ok(font) => Font.dropped(font) == [OverLimit("max_lookups")] and Font.width(font, "AB") == 600 + 700 - 50
		Err(_) => False
	}
}

# ------------------------------------------------------------ metrics

# Without `OS/2` and `post`: ascent and descent from `hhea`, HarfBuzz's
# estimates for the heights (half and two thirds of the em with no `x` or
# `O`) and the strikeout (half the ascent, an eighteenth of the em), and
# no underline.
expect {
	font = read_or_crash(FontBuild.file(FontBuild.basic))
	Font.metrics(font) == { ascent: 800, descent: 200, line_gap: 0, cap_height: 666, x_height: 500, underline: { position: 0, thickness: 0 }, strikeout: { position: 400, thickness: 55 } }
}

# `OS/2` version 2 stores the heights; the strikeout comes from `OS/2` and
# the line gap with the typographic metrics.
os2_v2 : List(U8)
os2_v2 = {
	base = FontBuild.os2({ use_typo: True, typo_ascent: 900, typo_descent: -300, win_ascent: 1000, win_descent: 400 }).concat(List.repeat(0, 18))
	[(0, 2), (72, 90), (86, 456), (88, 678), (26, 50), (28, 300)].fold(base, |bytes, (at, value)| FontBuild.patch(bytes, at, FontBuild.u16(value)))
}

expect {
	font = read_or_crash(FontBuild.file(basic_with("OS/2", os2_v2)))
	Font.metrics(font) == { ascent: 900, descent: 300, line_gap: 90, cap_height: 678, x_height: 456, underline: { position: 0, thickness: 0 }, strikeout: { position: 300, thickness: 50 } }
}

# The `x` and `O` estimates: the top of `x`, the top plus the bottom of `O`.
expect {
	glyphs = [[], FontBuild.pack([I16(1), I16(0), I16(-10), I16(100), I16(510)]), FontBuild.pack([I16(1), I16(0), I16(-12), I16(100), I16(712)]), []]
	boxes = FontBuild.outlines(glyphs, False)
	cmap = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 'O', last: 'O', delta: 65536 + 2 - 'O', glyphs: [] }, { first: 'x', last: 'x', delta: 65536 + 1 - 'x', glyphs: [] }]) }])
	font = read_or_crash(FontBuild.file(basic_with("cmap", cmap).concat([{ tag: "loca", data: boxes.loca }, { tag: "glyf", data: boxes.glyf }])))
	m = Font.metrics(font)
	m.x_height == 510 and m.cap_height == 700
}

# Inter, as HarfBuzz gives its metrics (it has no `post` table, so no
# underline).
expect Font.metrics(read_or_crash(inter_file)) == { ascent: 1984, descent: 494, line_gap: 0, cap_height: 1490, x_height: 1118, underline: { position: 0, thickness: 0 }, strikeout: { position: 671, thickness: 140 } }

# The underline from `post`.
expect Font.metrics(read_or_crash(mac_file)).underline == { position: -150, thickness: 60 }
expect Font.metrics(read_or_crash(japanese_file)).underline == { position: -75, thickness: 25 }

# ------------------------------------------------------------ names

expect Font.family_name(read_or_crash(mac_file)) == Ok("Caf\u(e9)\u(2122) Mac")
expect Font.family_name(read_or_crash(ranking_file)) == Ok("Emoji \u(1F600) Sans")
expect Font.family_name(read_or_crash(inter_file)) == Err(Missing)
expect Font.family_name(read_or_crash(FontBuild.file(FontBuild.basic))) == Err(Missing)

expect [0, 3, 5].map(|g| Font.glyph_name(read_or_crash(mac_file), g)) == [Ok(".notdef"), Ok("space"), Ok("quotedbl")]
expect [2, 4, 5].map(|g| Font.glyph_name(read_or_crash(ranking_file), g)) == [Ok("A"), Ok("caf\u(e9)"), Ok("uni1F600")]
expect Font.glyph_name(read_or_crash(japanese_file), 1) == Err(Missing)
expect Font.glyph_name(read_or_crash(mac_file), 100000) == Err(Missing)
expect Font.glyph_name(read_or_crash(FontBuild.file(FontBuild.basic)), 0) == Err(Missing)

# ------------------------------------------------------------ code points

expect Font.code_points(read_or_crash(FontBuild.file(FontBuild.basic))) == [0x41, 0x42, 0x43]

# The sample font's preferred map (format 12): A to Z and U+1F600.
expect Font.code_points(read_or_crash(FontBuild.sample)) == counting(0x41, 0x5B).append(0x1F600)

# Code points whose glyphs the font does not have, and code points mapped
# to glyph 0, are not listed; a format 13 group lists every code point.
expect {
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 0x41, last: 0x43, glyph: 0 }, { first: 0x50, last: 0x55, glyph: 2 }]) }])
	Font.code_points(read_or_crash(FontBuild.file(basic_with("cmap", cmap)))) == [0x42, 0x43, 0x50, 0x51]
}
expect {
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap13([{ first: 0x10000, last: 0x10003, glyph: 3 }, { first: 0x20000, last: 0x20001, glyph: 4 }]) }])
	Font.code_points(read_or_crash(FontBuild.file(basic_with("cmap", cmap)))) == [0x10000, 0x10001, 0x10002, 0x10003]
}

# Inter maps 2852 code points (as fontTools counts them); the listing is
# ascending and agrees with lookups.
expect {
	font = read_or_crash(inter_file)
	all = Font.code_points(font)
	all.len() == 2852
		and Font.code_points(font).take_first(5) == [0, 32, 33, 34, 35]
		and all.take_last(3) == [127339, 129104, 129106]
		and all.all(|cp| Font.glyph(font, cp).is_ok())
}

# ------------------------------------------------------------ extents

expect {
	glyphs = [[], FontBuild.outline(10, 490), [], FontBuild.outline(-5, 700)]
	boxes = FontBuild.outlines(glyphs, False)
	font = read_or_crash(FontBuild.file(FontBuild.basic.concat([{ tag: "loca", data: boxes.loca }, { tag: "glyf", data: boxes.glyf }])))
	# The left edge is the side bearing in `hmtx` (0 here), as in HarfBuzz.
	[0, 1, 3, 4, 0xFFFFFFFF].map(|g| Font.extents(font, g)) == [Empty, Extents({ x_min: 0, y_min: 0, x_max: 480, y_max: 100 }), Extents({ x_min: 0, y_min: 0, x_max: 705, y_max: 100 }), Empty, Empty]
}

# ------------------------------------------------------------ variations

advances_of : Font, U32 -> List(I32)
advances_of = |font, count| counting(0, count.to_u64()).map(|g| Font.advance(font, g))

mapped : Font
mapped = read_or_crash(mapped_file)

expect Font.axes(mapped) == [{ tag: "wght", min: 100, default: 400, max: 900 }, { tag: "wdth", min: 75, default: 100, max: 125 }]
expect Font.axes(read_or_crash(inter_file)) == []

# Advances (HVAR) and metrics (MVAR) at several locations, as HarfBuzz
# gives them. Without `at`, a font measures at Regular.
expect advances_of(mapped, 7) == [500, 600, 610, 620, 630, 640, 650] and Font.metrics(mapped).x_height == 500
expect {
	bold = Font.at(mapped, Font.Variation.{ weight: Bold })
	advances_of(bold, 7) == [500, 801, 461, 628, 2503, 644, 654] and Font.metrics(bold).x_height == 514 and Font.metrics(bold).underline.position == -10
}
expect advances_of(Font.at(mapped, Font.Variation.{ weight: Thin }), 7) == [500, 500, 711, 620, 630, 639, 649]

# Values outside an axis clamp to it.
expect {
	heavy = Font.at(mapped, Font.Variation.{ weight: Weight(1000) })
	advances_of(heavy, 7) == [500, 900, 277, 635, 33397, 641, 651] and Font.metrics(heavy).x_height == 520 and Font.metrics(heavy).underline.position == -15
}

# Named widths, and fractional values on any axis.
expect {
	narrow = Font.at(mapped, Font.Variation.{ weight: Weight(550), width: SemiCondensed })
	advances_of(narrow, 7) == [500, 729, 574, 9624, 0, 645, 655] and Font.metrics(narrow).x_height == 511 and Font.metrics(narrow).underline.position == -7
}
expect {
	between = Font.at(mapped, Font.Variation.{ axes: [{ tag: "wght", value: 456.7 }] })
	advances_of(between, 7) == [500, 649, 597, 622, 0, 642, 652] and Font.metrics(between).x_height == 503 and Font.metrics(between).underline.position == -3
}

# Axis settings override the named fields; a later one for a tag wins;
# unknown tags and tags that are not four bytes are ignored.
expect advances_of(Font.at(mapped, Font.Variation.{ weight: Bold, axes: [{ tag: "wght", value: 700 }, { tag: "wght", value: 100 }] }), 7) == advances_of(Font.at(mapped, Font.Variation.{ weight: Thin }), 7)
expect advances_of(Font.at(mapped, Font.Variation.{ axes: [{ tag: "GRAD", value: 50 }, { tag: "wg", value: 900 }, { tag: "wghtx", value: 900 }] }), 7) == advances_of(mapped, 7)

# `at` starts from the font's tables, not from an earlier location.
expect advances_of(Font.at(Font.at(mapped, Font.Variation.{ weight: Black }), Font.Variation.{}), 7) == advances_of(mapped, 7)

# A font whose default instance is not Regular (`wght` 300 to 700, default
# 300) measures at Regular unless told otherwise.
expect {
	implicit = read_or_crash(implicit_file)
	default_instance = Font.at(implicit, Font.Variation.{ axes: [{ tag: "wght", value: 300 }] })
	advances_of(implicit, 4) == [500, 616, 691, 813] and advances_of(default_instance, 4) == [500, 600, 700, 800] and advances_of(Font.at(implicit, Font.Variation.{ weight: Bold }), 4) == [500, 700, 650, 807]
}

# The optical size goes to `opsz`.
expect advances_of(Font.at(read_or_crash(format1_file), Font.Variation.{ optical_size: Size(48) }), 5) == [500, 10, 521, 530, 0]

# A static font ignores variations. A variable font without `gvar` keeps
# its glyph boxes everywhere; `VariationTests` covers boxes that vary.
expect {
	inter = read_or_crash(inter_file)
	bold = Font.at(inter, Font.Variation.{ weight: Bold })
	advances_of(bold, 3) == advances_of(inter, 3) and Font.extents(bold, 2) == Font.extents(inter, 2)
}
expect Font.extents(Font.at(mapped, Font.Variation.{ weight: Bold }), 1) == Font.extents(mapped, 1)
