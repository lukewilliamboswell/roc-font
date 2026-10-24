import font.Font
import build.FontBuild

## The tests of reading as OTS 9.3.0 reads: the checks of the font header
## (`head`), the character map (`cmap`), glyph substitution (`GSUB`), the
## PostScript table (`post`) and the naming table (`name`) that OTS applies
## (`ots/src/head.cc`, `cmap.cc`, `layout.cc`, `gsub.cc`, `post.cc` and
## `name.cc`), each as a font OTS refuses and roc-font refuses with a
## problem naming the table and the offset, and the warnings OTS accepts
## as fonts that read. Run with `roc test tests/api/main.roc`.
ReadOtsTests :: {}.{}

# ------------------------------------------------------------ helpers

lenient : List(U8) -> Try(Font, List(Font.Problem))
lenient = |bytes| Font.from_bytes(bytes, Font.ReadOptions.{})

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

# The basic font (four glyphs) with a table replaced.
font_with : Str, List(U8) -> List(U8)
font_with = |tag, data| FontBuild.file(FontBuild.replace(FontBuild.basic, tag, data))

# The one problem of a font, as the table and its offset in that table.
problem_at : List(U8), Str -> Try(U64, [Read, Other])
problem_at = |bytes, tag|
	match lenient(bytes) {
		Ok(_) => Err(Read)
		Err([BadTable({ table, offset })]) if table == tag => Ok(offset.to_u64() - table_offset(bytes, tag))
		Err(_) => Err(Other)
	}

# The problems that refused a font (none when it reads).
problems_of : List(U8) -> List(Font.Problem)
problems_of = |bytes|
	match lenient(bytes) {
		Ok(_) => []
		Err(problems) => problems
	}

reads : List(U8) -> Bool
reads = |bytes|
	match lenient(bytes) {
		Ok(font) => Font.dropped(font).is_empty()
		Err(_) => False
	}

# The glyph of a code point in a font that reads, 9999 when it has none.
glyph_of : List(U8), U32 -> U32
glyph_of = |bytes, code_point|
	match lenient(bytes) {
		Ok(font) => Font.glyph(font, code_point) ?? 9999
		Err(_) => 0
	}

# ------------------------------------------------------------ head

# head.cc 23-25, 32-35, 66-73, 91-103: the major version, the magic
# number, the bounding box, the `loca` format and the glyph data format,
# each at its offset.
expect problem_at(font_with("head", FontBuild.patch(FontBuild.head(1000, False), 0, FontBuild.u16(2))), "head") == Ok(0)
expect problem_at(font_with("head", FontBuild.patch(FontBuild.head(1000, False), 12, FontBuild.u32(0x5F0F3CF4))), "head") == Ok(12)
expect problem_at(font_with("head", FontBuild.patch(FontBuild.head(1000, False), 36, FontBuild.i16(10))), "head") == Ok(36)
expect problem_at(font_with("head", FontBuild.patch(FontBuild.head(1000, False), 38, FontBuild.i16(1))), "head") == Ok(38)
expect problem_at(font_with("head", FontBuild.patch(FontBuild.head(1000, False), 50, FontBuild.u16(2))), "head") == Ok(50)
expect problem_at(font_with("head", FontBuild.patch(FontBuild.head(1000, False), 50, FontBuild.u16(0xFFFF))), "head") == Ok(50)
expect problem_at(font_with("head", FontBuild.patch(FontBuild.head(1000, False), 52, FontBuild.u16(1))), "head") == Ok(52)

# A minor version, flags and style bits OTS masks, and an empty bounding
# box (minimum equal to maximum) read.
expect reads(font_with("head", FontBuild.patch(FontBuild.head(1000, False), 2, FontBuild.u16(5))))
expect reads(font_with("head", FontBuild.patch(FontBuild.patch(FontBuild.head(1000, False), 16, FontBuild.u16(0xFFFF)), 44, FontBuild.u16(0xFFFF))))
expect reads(font_with("head", FontBuild.patch(FontBuild.head(1000, False), 36, FontBuild.i16(-5).concat(FontBuild.i16(-5)).concat(FontBuild.i16(-5)).concat(FontBuild.i16(-5)))))

# ------------------------------------------------------------ cmap header

one_map : List(U8)
one_map = FontBuild.cmap4([{ first: 0x41, last: 0x43, delta: 65536 - 64, glyphs: [] }])

# A table with one record for platform 3, encoding 1: the subtable is at
# offset 12 of the table.
cmap31 : List(U8) -> List(U8)
cmap31 = |subtable| font_with("cmap", FontBuild.cmap([{ system: 3, encoding: 1, subtable }]))

# cmap.cc 577-579: version 0.
expect problem_at(font_with("cmap", FontBuild.patch(FontBuild.cmap([{ system: 3, encoding: 1, subtable: one_map }]), 0, FontBuild.u16(1))), "cmap") == Ok(0)

# cmap.cc 603-611: a subtable offset inside the encoding records names the
# record.
expect problem_at(font_with("cmap", FontBuild.patch(FontBuild.cmap([{ system: 3, encoding: 1, subtable: one_map }]), 8, FontBuild.u32(4))), "cmap") == Ok(4)

# cmap.cc 679-691: a stated length past the end of the table.
expect problem_at(cmap31(FontBuild.patch(one_map, 2, FontBuild.u16(one_map.len() + 2))), "cmap") == Ok(12)

# cmap.cc 694-719: two subtables that share bytes but not all of them; the
# second is named. Subtables sharing exactly the same bytes are allowed.
expect {
	inner = FontBuild.cmap12([{ first: 0x41, last: 0x43, glyph: 1 }])
	outer = FontBuild.patch(one_map, 2, FontBuild.u16(one_map.len() + inner.len())).concat(inner)
	table = FontBuild.pack([U16(0), U16(2), U16(3), U16(1), U32(20), U16(3), U16(10), U32(20 + one_map.len())]).concat(outer)
	problem_at(font_with("cmap", table), "cmap") == Ok(20 + one_map.len())
}
expect {
	table = FontBuild.pack([U16(0), U16(2), U16(0), U16(3), U32(20), U16(3), U16(1), U32(20)]).concat(one_map)
	glyph_of(font_with("cmap", table), 0x42) == 2
}

# ------------------------------------------------------------ cmap format 4

# cmap.cc 83-124: the language, an even segment count and search range,
# and the binary search fields exactly as the segment count gives them.
expect problem_at(cmap31(FontBuild.patch(one_map, 4, FontBuild.u16(1))), "cmap") == Ok(12)
expect problem_at(cmap31(FontBuild.patch(one_map, 6, FontBuild.u16(5))), "cmap") == Ok(12)
expect problem_at(cmap31(FontBuild.patch(one_map, 8, FontBuild.u16(2))), "cmap") == Ok(12)
expect problem_at(cmap31(FontBuild.patch(one_map, 8, FontBuild.u16(3))), "cmap") == Ok(12)
expect problem_at(cmap31(FontBuild.patch(one_map, 10, FontBuild.u16(0))), "cmap") == Ok(12)
expect problem_at(cmap31(FontBuild.patch(one_map, 12, FontBuild.u16(2))), "cmap") == Ok(12)

# The fields of the corpus's AOTS fonts: a search range of 2 for two
# segments (OTS wants 4).
expect problem_at(cmap31(FontBuild.patch(FontBuild.patch(one_map, 8, FontBuild.u16(2)), 10, FontBuild.u16(0))), "cmap") == Ok(12)

# Three and five segments: the largest power of two not above the count.
expect {
	three = FontBuild.cmap4([{ first: 0x41, last: 0x41, delta: 65536 + 1 - 0x41, glyphs: [] }, { first: 0x42, last: 0x42, delta: 65536 + 2 - 0x42, glyphs: [] }])
	five = FontBuild.cmap4([0x41, 0x43, 0x45, 0x47].map(|c| { first: c, last: c, delta: 65536 + 1 - c, glyphs: [] }))
	three.sublist({ start: 6, len: 8 }) == FontBuild.u16(6).concat(FontBuild.u16(4)).concat(FontBuild.u16(1)).concat(FontBuild.u16(2))
		and reads(cmap31(three))
		and reads(cmap31(five))
		and problem_at(cmap31(FontBuild.patch(five, 12, FontBuild.u16(4))), "cmap") == Ok(12)
}

# cmap.cc 134-140: the pad after the end codes is zero.
expect problem_at(cmap31(FontBuild.patch(one_map, 18, FontBuild.u16(1))), "cmap") == Ok(12)

# A format 4 subtable built by hand: end codes, start codes, deltas and
# range offsets, with the binary search fields worked out.
format4 : List({ first : U64, last : U64, delta : U64, offset : U64 }), List(U64) -> List(U8)
format4 = |segments, array| {
	n = segments.len()
	var $log = 0
	while (2.U64).shl_wrap($log.to_u8_wrap()) <= n {
		$log = $log + 1
	}
	search = (2.U64).shl_wrap($log.to_u8_wrap())
	body = [U16(2 * n), U16(search), U16($log), U16(2 * n - search)]
		.concat(segments.map(|s| U16(s.last)))
		.concat([U16(0)])
		.concat(segments.map(|s| U16(s.first)))
		.concat(segments.map(|s| U16(s.delta)))
		.concat(segments.map(|s| U16(s.offset)))
		.concat(array.map(|g| U16(g)))
	packed = FontBuild.pack(body)
	FontBuild.u16(4).concat(FontBuild.u16(packed.len() + 6)).concat(FontBuild.u16(0)).concat(packed)
}

terminator : { first : U64, last : U64, delta : U64, offset : U64 }
terminator = { first: 0xFFFF, last: 0xFFFF, delta: 1, offset: 0 }

a_to_c : { first : U64, last : U64, delta : U64, offset : U64 }
a_to_c = { first: 0x41, last: 0x43, delta: 65536 - 64, offset: 0 }

# cmap.cc 158-170: an odd range offset is refused, except on the last
# segment, which OTS takes as 0 (and a 0xFFFF segment maps nothing).
expect problem_at(cmap31(format4([{ ..a_to_c, offset: 1 }, terminator], [])), "cmap") == Ok(12)
expect reads(cmap31(format4([a_to_c, { ..terminator, offset: 0xFFFF }], [])))

# cmap.cc 173-194: end codes increasing, each start past the previous end;
# two final 0xFFFF segments are allowed, and a segment whose start is past
# its end maps nothing.
expect problem_at(cmap31(format4([a_to_c, { first: 0x43, last: 0x44, delta: 0, offset: 0 }, terminator], [])), "cmap") == Ok(12)
expect problem_at(cmap31(format4([a_to_c, { first: 0x50, last: 0x40, delta: 0, offset: 0 }, terminator], [])), "cmap") == Ok(12)
expect glyph_of(cmap31(format4([a_to_c, terminator, terminator], [])), 0x43) == 3
expect {
	bytes = cmap31(format4([{ first: 0x30, last: 0x20, delta: 1, offset: 0 }, a_to_c, terminator], []))
	glyph_of(bytes, 0x25) == 9999 and glyph_of(bytes, 0x41) == 1
}

# cmap.cc 210-214: the last segment is U+FFFF alone.
expect problem_at(cmap31(format4([a_to_c], [])), "cmap") == Ok(12)
expect problem_at(cmap31(format4([a_to_c, { ..terminator, first: 0xFFFE }], [])), "cmap") == Ok(12)

# cmap.cc 216-247: every glyph below the glyph count, the 0xFFFF segment's
# too, and every glyph array entry inside the subtable's stated length.
expect problem_at(cmap31(format4([a_to_c, { ..terminator, delta: 5 }], [])), "cmap") == Ok(12)
expect reads(cmap31(format4([a_to_c, { ..terminator, delta: 3 }], [])))
expect problem_at(cmap31(format4([{ first: 0x41, last: 0x42, delta: 0, offset: 4 }, terminator], [1])), "cmap") == Ok(12)
expect glyph_of(cmap31(format4([{ first: 0x41, last: 0x42, delta: 0, offset: 4 }, terminator], [3, 2])), 0x42) == 2

# A subtable for platform 0 is checked the same way.
expect problem_at(font_with("cmap", FontBuild.cmap([{ system: 0, encoding: 3, subtable: FontBuild.patch(one_map, 8, FontBuild.u16(2)) }])), "cmap") == Ok(12)

# ------------------------------------------------------------ cmap formats 12, 13, 14 and 0

cmap310 : List(U8) -> List(U8)
cmap310 = |subtable| font_with("cmap", FontBuild.cmap([{ system: 3, encoding: 10, subtable }]))

# cmap.cc 281-290: language 0 and at least one group.
expect problem_at(cmap310(FontBuild.patch(FontBuild.cmap12([{ first: 0x41, last: 0x43, glyph: 1 }]), 8, FontBuild.u32(1))), "cmap") == Ok(12)
expect problem_at(cmap310(FontBuild.cmap12([])), "cmap") == Ok(12)
expect problem_at(cmap310(FontBuild.cmap13([])), "cmap") == Ok(12)

# cmap.cc 304-320 and 385-387: glyphs below the glyph count (a start glyph
# past 0xFFFF is refused whatever the count).
expect problem_at(cmap310(FontBuild.cmap12([{ first: 0x41, last: 0x43, glyph: 2 }])), "cmap") == Ok(12)
expect problem_at(cmap310(FontBuild.cmap12([{ first: 0x41, last: 0x41, glyph: 0x10001 }])), "cmap") == Ok(12)
expect problem_at(cmap310(FontBuild.cmap13([{ first: 0x41, last: 0x43, glyph: 4 }])), "cmap") == Ok(12)
expect glyph_of(cmap310(FontBuild.cmap12([{ first: 0x41, last: 0x43, glyph: 1 }])), 0x43) == 3

# OTS does not ask a format 13 group to end after it starts; such a group
# maps nothing.
expect {
	bytes = cmap310(FontBuild.cmap13([{ first: 0x50, last: 0x41, glyph: 1 }, { first: 0x60, last: 0x61, glyph: 2 }]))
	glyph_of(bytes, 0x48) == 9999 and glyph_of(bytes, 0x61) == 2
}

# A format 12 map for platform 0, encoding 4, is checked too.
expect problem_at(font_with("cmap", FontBuild.cmap([{ system: 0, encoding: 4, subtable: FontBuild.cmap12([{ first: 0x41, last: 0x43, glyph: 3 }]) }])), "cmap") == Ok(12)

# Variation sequences (format 14, platform 0, encoding 5) beside the basic
# map: one record for `selector` with a default table holding U+0041 and
# a non-default table mapping U+0042 to `glyph`.
variations : U64, U64 -> List(U8)
variations = |selector, glyph|
	FontBuild.pack([
		U16(14),
		U32(10 + 11 + 8 + 9),
		U32(1),
		Raw([selector.shr_zf_wrap(16).to_u8_wrap(), selector.shr_zf_wrap(8).to_u8_wrap(), selector.to_u8_wrap()]),
		U32(21),
		U32(29),
		U32(1),
		Raw([0, 0, 0x41, 0]),
		U32(1),
		Raw([0, 0, 0x42]),
		U16(glyph),
	])

variations_font : List(U8) -> List(U8)
variations_font = |subtable| font_with("cmap", FontBuild.cmap([{ system: 0, encoding: 5, subtable }, { system: 3, encoding: 1, subtable: one_map }]))

# cmap.cc 403-537: a variation selector, a glyph other than 0, and the last
# table read ending the subtable exactly.
expect reads(variations_font(variations(0xFE00, 2)))
expect problem_at(variations_font(variations(0x41, 2)), "cmap") == Ok(20)
expect problem_at(variations_font(variations(0xFE00, 0)), "cmap") == Ok(20)
expect problem_at(variations_font(FontBuild.patch(variations(0xFE00, 2), 2, FontBuild.u32(39)).append(0)), "cmap") == Ok(20)

# cmap.cc 539-565: a Macintosh Roman map holds 256 glyph ids, though OTS
# compares none of them with the glyph count.
expect problem_at(font_with("cmap", FontBuild.cmap([{ system: 1, encoding: 0, subtable: FontBuild.patch(FontBuild.cmap0([]), 2, FontBuild.u16(261)) }, { system: 3, encoding: 1, subtable: one_map }])), "cmap") == Ok(20)
expect reads(font_with("cmap", FontBuild.cmap([{ system: 1, encoding: 0, subtable: FontBuild.cmap0([200]) }, { system: 3, encoding: 1, subtable: one_map }])))

# ------------------------------------------------------------ GSUB

# A `GSUB` table built by hand: script list, feature list, lookup list.
gsub_of : List(U8), List(U8), List(U8) -> List(U8)
gsub_of = |scripts, features, lookups| FontBuild.pack([U32(0x00010000), Ref(scripts), Ref(features), Ref(lookups)])

no_features : List(U8)
no_features = FontBuild.pack([U16(0)])

no_lookups : List(U8)
no_lookups = FontBuild.pack([U16(0)])

one_script : Str, List(U8) -> List(U8)
one_script = |tag, script| FontBuild.pack([U16(1), Tag(tag), Ref(script)])

# A table whose `liga` feature uses each lookup, in the basic font.
gsub_font : List({ kind : U64, subtables : List(List(U8)) }) -> List(U8)
gsub_font = |lookups| font_with("GSUB", FontBuild.layout("latn", [{ tag: "liga", lookups: FontBuild.counting(lookups.len()) }], lookups))

# layout.cc 1664-1666: version 1.0 or 1.1.
expect problem_at(font_with("GSUB", FontBuild.patch(FontBuild.layout("latn", [], []), 2, FontBuild.u16(2))), "GSUB") == Ok(0)

# layout.cc 1677-1680: a list offset inside the header names its field.
expect problem_at(font_with("GSUB", FontBuild.patch(FontBuild.layout("latn", [], []), 8, FontBuild.u16(4))), "GSUB") == Ok(8)

# Absent lists are allowed.
expect reads(font_with("GSUB", FontBuild.pack([U32(0x00010000), U16(0), U16(0), U16(0)])))

# layout.cc 98-102: a `DFLT` script needs a default language system (the
# script table, after the 10-byte header and the 8-byte script list, is at
# 18); another script does not.
expect problem_at(font_with("GSUB", gsub_of(one_script("DFLT", FontBuild.pack([U16(0), U16(0)])), no_features, no_lookups)), "GSUB") == Ok(18)
expect reads(font_with("GSUB", gsub_of(one_script("latn", FontBuild.pack([U16(0), U16(0)])), no_features, no_lookups)))

# layout.cc 113-126 and 59-62: language system records in tag order, and a
# language system's reserved lookup order offset 0.
expect {
	language = FontBuild.pack([U16(0), U16(0xFFFF), U16(0)])
	script = FontBuild.pack([U16(0), U16(2), Tag("TRK "), Ref(language), Tag("DEU "), Ref(language)])
	problem_at(font_with("GSUB", gsub_of(one_script("latn", script), no_features, no_lookups)), "GSUB") == Ok(18 + 4 + 6)
}
expect {
	language = FontBuild.pack([U16(4), U16(0xFFFF), U16(0)])
	script = FontBuild.pack([U16(0), U16(1), Tag("TRK "), Ref(language)])
	problem_at(font_with("GSUB", gsub_of(one_script("latn", script), no_features, no_lookups)), "GSUB") == Ok(18 + 10)
}

# layout.cc 159-163: feature parameters (when present) past the lookup
# indices; the feature table follows the 10-byte header, a 4-byte script
# list and the 8-byte feature list.
expect {
	features = FontBuild.pack([U16(1), Tag("liga"), Ref(FontBuild.pack([U16(2), U16(0)]))])
	problem_at(font_with("GSUB", gsub_of(FontBuild.pack([U16(0)]), features, no_lookups)), "GSUB") == Ok(10 + 2 + 8)
}

# layout.cc 1306-1308 and gsub.cc 495-500: lookup types 1 to 8, an
# extension of any but another extension.
expect problem_at(gsub_font([{ kind: 9, subtables: [FontBuild.single1([1], 1)] }]), "GSUB").is_ok()
expect problem_at(gsub_font([{ kind: 7, subtables: [FontBuild.extension(7, FontBuild.single1([1], 1))] }]), "GSUB").is_ok()
expect reads(gsub_font([{ kind: 7, subtables: [FontBuild.extension(1, FontBuild.single1([1], 1))] }]))

# OTS checks every lookup, not only those a feature reaches.
expect {
	gsub = FontBuild.layout("latn", [{ tag: "liga", lookups: [0] }], [{ kind: 1, subtables: [FontBuild.single1([1], 1)] }, { kind: 1, subtables: [FontBuild.single1([4], 1)] }])
	problem_at(font_with("GSUB", gsub), "GSUB").is_ok()
}

# gsub.cc 164-193: a single substitution's delta smaller than the glyph
# count in size (the glyph it gives is not compared), and substitutes below
# the count.
expect problem_at(gsub_font([{ kind: 1, subtables: [FontBuild.single1([1], 4)] }]), "GSUB").is_ok()
expect problem_at(gsub_font([{ kind: 1, subtables: [FontBuild.single1([1], -4)] }]), "GSUB").is_ok()
expect reads(gsub_font([{ kind: 1, subtables: [FontBuild.single1([3], 3)] }]))
expect problem_at(gsub_font([{ kind: 1, subtables: [FontBuild.single2([1], [4])] }]), "GSUB").is_ok()

# gsub.cc 32-137: sequence, alternate and ligature glyphs below the glyph
# count.
expect problem_at(gsub_font([{ kind: 2, subtables: [FontBuild.multiple([1], [[2, 4]])] }]), "GSUB").is_ok()
expect problem_at(gsub_font([{ kind: 3, subtables: [FontBuild.multiple([1], [[4]])] }]), "GSUB").is_ok()
expect problem_at(gsub_font([{ kind: 4, subtables: [FontBuild.ligature([1], [[{ glyph: 4, rest: [2] }]])] }]), "GSUB").is_ok()
expect problem_at(gsub_font([{ kind: 4, subtables: [FontBuild.ligature([1], [[{ glyph: 3, rest: [4] }]])] }]), "GSUB").is_ok()

# layout.cc 261-346: coverage glyphs below the glyph count, and ranges
# starting at the coverage index the previous ranges reach.
expect problem_at(gsub_font([{ kind: 1, subtables: [FontBuild.single1([1, 4], 1)] }]), "GSUB").is_ok()
expect problem_at(gsub_font([{ kind: 1, subtables: [FontBuild.pack([U16(1), Ref(FontBuild.coverage2([{ first: 1, last: 2, index: 1 }])), I16(1)])] }]), "GSUB").is_ok()

# layout.cc 178-215: a class definition's first glyph below the glyph
# count.
expect problem_at(gsub_font([{ kind: 5, subtables: [FontBuild.context2([1], FontBuild.classes1(4, [1]), [])] }]), "GSUB").is_ok()

# layout.cc 350-366: a lookup record's sequence index below the font's
# glyph count (OTS compares it with that, not with the rule's length), and
# its lookup index below the lookup count.
expect problem_at(gsub_font([{ kind: 5, subtables: [FontBuild.context3([[1]], [{ at: 4, lookup: 0 }])] }]), "GSUB").is_ok()
expect reads(gsub_font([{ kind: 5, subtables: [FontBuild.context3([[1]], [{ at: 3, lookup: 0 }])] }]))
expect problem_at(gsub_font([{ kind: 6, subtables: [FontBuild.chain3([], [[1]], [], [{ at: 0, lookup: 1 }])] }]), "GSUB").is_ok()

# layout.cc 965-1074: a chained rule with no input is read, and never
# applies.
expect {
	bytes = gsub_font([{ kind: 6, subtables: [FontBuild.chain3([[1]], [], [[2]], [])] }])
	match lenient(bytes) {
		Ok(font) => Font.shape(font, "ABC", Font.ShapeOptions.{}).glyphs == [1, 2, 3]
		Err(_) => False
	}
}

# gsub.cc 394-493: reverse chaining substitutes below the glyph count. OTS
# does not check the format; another format never applies.
reverse : U64, U64 -> List(U8)
reverse = |format, substitute| FontBuild.pack([U16(format), Ref(FontBuild.coverage1([1])), U16(0), U16(0), U16(1), U16(substitute)])

expect problem_at(gsub_font([{ kind: 8, subtables: [reverse(1, 4)] }]), "GSUB").is_ok()
expect {
	bytes = gsub_font([{ kind: 8, subtables: [reverse(2, 3)] }])
	match lenient(bytes) {
		Ok(font) => Font.shape(font, "A", Font.ShapeOptions.{}).glyphs == [1]
		Err(_) => False
	}
}
expect {
	bytes = gsub_font([{ kind: 8, subtables: [reverse(1, 3)] }])
	match lenient(bytes) {
		Ok(font) => Font.shape(font, "A", Font.ShapeOptions.{}).glyphs == [3]
		Err(_) => False
	}
}

# layout.cc 1336-1349: a mark filtering set the font's `GDEF` defines;
# without `GDEF` the set is not checked.
expect {
	gsub = FontBuild.flagged_layout("liga", [{ kind: 1, flag: 0x10, set: 0, subtables: [FontBuild.single1([1], 1)] }])
	gdef = FontBuild.pack([U32(0x00010000), U16(0), U16(0), U16(0), U16(0)])
	tables = FontBuild.replace(FontBuild.replace(FontBuild.basic, "GSUB", gsub), "GDEF", gdef)
	problem_at(FontBuild.file(tables), "GSUB").is_ok() and reads(font_with("GSUB", gsub))
}

# ------------------------------------------------------------ post

# post.cc 17-26: versions 1.0, 2.0 and 3.0; the deprecated 2.5 is refused.
expect reads(font_with("post", FontBuild.post(0x00010000, [], [])))
expect reads(font_with("post", FontBuild.post(0x00030000, [], [])))
expect reads(font_with("post", FontBuild.post(0x00020000, [0, 36, 258, 259], ["A.alt", "B.alt"])))
expect problem_at(font_with("post", FontBuild.post(0x00025000, [], []).concat([0, 4, 0, 0, 0, 0])), "post") == Ok(0)
expect problem_at(font_with("post", FontBuild.post(0x00040000, [], [])), "post") == Ok(0)

# post.cc 28-36: the 32-byte header.
expect problem_at(font_with("post", FontBuild.post(0x00010000, [], []).take_first(31)), "post") == Ok(0)

# post.cc 59-73: a version 2.0 count other than `maxp`'s is refused; none
# at all is allowed for a font of at most 258 glyphs.
expect problem_at(font_with("post", FontBuild.post(0x00020000, [0, 1, 2], [])), "post") == Ok(32)
expect reads(font_with("post", FontBuild.post(0x00020000, [], [])))

# post.cc 91-117: a stored name past the end of the table or holding a
# zero byte, and an index past the stored names.
expect problem_at(font_with("post", FontBuild.post(0x00020000, [0, 1, 2, 258], ["A"]).concat([9, 0x41])), "post") == Ok(44)
expect problem_at(font_with("post", FontBuild.post(0x00020000, [0, 1, 2, 258], ["A\u(0)"])), "post") == Ok(42)
expect problem_at(font_with("post", FontBuild.post(0x00020000, [0, 1, 2, 259], ["A"])), "post") == Ok(40)

# Glyph names of a version 2.0 table that reads.
expect
	match lenient(font_with("post", FontBuild.post(0x00020000, [0, 36, 258, 259], ["A.alt", "B.alt"]))) {
		Ok(font) => [0, 1, 2, 3, 4].map(|g| Font.glyph_name(font, g)) == [Ok(".notdef"), Ok("A"), Ok("A.alt"), Ok("B.alt"), Err(Missing)]
		Err(_) => False
	}

# ------------------------------------------------------------ name

windows : U64, Str -> { system : U64, encoding : U64, language : U64, id : U64, text : List(U8) }
windows = |id, text| { system: 3, encoding: 1, language: 0x409, id, text: FontBuild.utf16(text) }

# name.cc 69-82, 92-102: the format, the string offset inside the table,
# and the records inside it.
expect problem_at(font_with("name", FontBuild.patch(FontBuild.naming([windows(1, "Family")], []), 0, FontBuild.u16(2))), "name") == Ok(0)
expect problem_at(font_with("name", FontBuild.patch(FontBuild.naming([windows(1, "Family")], []), 4, FontBuild.u16(100))), "name") == Ok(4)
expect problem_at(font_with("name", FontBuild.u16(0).concat(FontBuild.u16(3)).concat(FontBuild.u16(6)).concat(List.repeat(0, 12))), "name") == Ok(2)

# name.cc 178-200: a language tag outside the table or over 200 bytes, and
# string storage that starts inside the records.
expect problem_at(font_with("name", FontBuild.naming([windows(1, "Family")], [List.repeat(0x41, 202)])), "name") == Ok(20)
expect problem_at(font_with("name", FontBuild.patch(FontBuild.naming([windows(1, "Family")], []), 4, FontBuild.u16(6))), "name") == Ok(4)

# name.cc 103-155: records OTS discards (an unknown platform, a string
# outside the table) and strings it keeps but no `Str` holds (odd-length
# UTF-16) leave the font readable; the family name comes from a usable
# record.
expect {
	records = [
		{ system: 7, encoding: 0, language: 0, id: 1, text: "Seven".to_utf8() },
		{ system: 3, encoding: 1, language: 0x409, id: 1, text: [0, 0x41, 0] },
		{ system: 1, encoding: 0, language: 0, id: 1, text: "Mac Family".to_utf8() },
	]
	bytes = font_with("name", FontBuild.naming(records, []))
	match lenient(bytes) {
		Ok(font) => Font.family_name(font) == Ok("Mac Family")
		Err(_) => False
	}
}

# name.cc 266-313: more than 65535 bytes of strings once OTS adds its
# placeholder names, counting records that share one string once each.
expect {
	# 5000 records of one 14-byte string: 70000 bytes as OTS writes them.
	record = FontBuild.u16(3).concat(FontBuild.u16(1)).concat(FontBuild.u16(0x409)).concat(FontBuild.u16(1)).concat(FontBuild.u16(14)).concat(FontBuild.u16(0))
	table = FontBuild.u16(0).concat(FontBuild.u16(5000)).concat(FontBuild.u16(6 + 12 * 5000)).concat(List.repeat(record, 5000).join_map(|r| r)).concat(FontBuild.utf16("Family!"))
	problem_at(font_with("name", table), "name") == Ok(4) and reads(font_with("name", FontBuild.patch(table, 2, FontBuild.u16(4000))))
}

# ------------------------------------------------------------ problems together

# Problems of several tables are reported together, each naming its table
# and offset.
expect {
	tables = FontBuild.basic
		.map(|t| if (t.tag == "head") { tag: t.tag, data: FontBuild.patch(FontBuild.head(1000, False), 12, FontBuild.u32(0)) } else t)
		.map(|t| if (t.tag == "cmap") { tag: t.tag, data: FontBuild.patch(t.data, 0, FontBuild.u16(1)) } else t)
	bytes = FontBuild.file(tables)
	problems_of(bytes) == [bad("head", table_offset(bytes, "head") + 12), bad("cmap", table_offset(bytes, "cmap"))]
}
expect {
	tables = FontBuild.basic
		.map(|t| if (t.tag == "cmap") { tag: t.tag, data: FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.patch(one_map, 8, FontBuild.u16(2)) }]) } else t)
		.append({ tag: "GSUB", data: gsub_of(one_script("DFLT", FontBuild.pack([U16(0), U16(0)])), no_features, no_lookups) })
	bytes = FontBuild.file(tables)
	problems_of(bytes) == [bad("cmap", table_offset(bytes, "cmap") + 12), bad("GSUB", table_offset(bytes, "GSUB") + 18)]
}
