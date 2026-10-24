import font.Font
import build.FontBuild
import "../../tests/fonts/Inter-Regular-metrics.ttf" as inter_file : List(U8)

## Tests of the shaping steps that make roc-font agree with a browser
## (HarfBuzz) beyond plain `GSUB` and `GPOS`, through the public `Font`
## API: glyph classes and lookup flags, alternates chosen by a feature's
## value, `rand`, reverse chaining, automatic fractions, composing and
## decomposing by what the font maps, hiding default-ignorable characters,
## spaces the font lacks, the no-break hyphen, mirroring in right-to-left
## text, grapheme clusters and the missing-glyph flag. Expected values are
## HarfBuzz 14.6.0's (uharfbuzz 0.56.3), for the Inter test font directly
## and for the built fonts through equivalent fonts made with fontTools.
## Run with `roc test tests/api/main.roc`.
ShapeParityTests :: {}.{}

inter : Font
inter = match Font.from_bytes(inter_file, Font.ReadOptions.{}) {
	Ok(font) => font
	Err(_) => crash "the Inter test font could not be read"
}

latin : Font.ShapeOptions
latin = Font.ShapeOptions.{ script: "Latn" }

Shaped : { glyphs : List(U32), clusters : List(U64), advances : List(I32), flags : List(U8) }

shaped : Font, Str, Font.ShapeOptions -> Shaped
shaped = |font, text, options| {
	run = Font.shape(font, text, options)
	{ glyphs: run.glyphs, clusters: run.clusters, advances: run.advances.map(|a| a.x), flags: run.flags }
}

# ------------------------------------------------------------ Inter against HarfBuzz

# A feature's value chooses among alternates (`aalt` lists three for `a`).
expect shaped(inter, "a", Font.ShapeOptions.{ script: "Latn", features: [Font.Feature.{ tag: "aalt", value: 1 }] }).glyphs == [1624]
expect shaped(inter, "a", Font.ShapeOptions.{ script: "Latn", features: [Font.Feature.{ tag: "aalt", value: 2 }] }).glyphs == [1575]
expect shaped(inter, "a", Font.ShapeOptions.{ script: "Latn", features: [Font.Feature.{ tag: "aalt", value: 3 }] }) == { glyphs: [1560], clusters: [0], advances: [929], flags: [0] }

# Brackets mirror in right-to-left text.
expect shaped(inter, "(a)", Font.ShapeOptions.{ script: "Latn", direction: RightToLeft }) == { glyphs: [1437, 507, 1438], clusters: [2, 1, 0], advances: [747, 1150, 747], flags: [0, 0, 0] }
expect shaped(inter, "[x]<", Font.ShapeOptions.{ script: "Latn", direction: RightToLeft }).glyphs == [1517, 1439, 993, 1441]

# Digits around U+2044 FRACTION SLASH take numerator and denominator forms,
# unsafe to break inside the fraction.
expect shaped(inter, "1\u(2044)2", latin) == { glyphs: [1701, 1673, 1678], clusters: [0, 1, 4], advances: [589, 393, 753], flags: [0, 1, 1] }
expect shaped(inter, "a 1\u(2044)2 b", latin).glyphs == [507, 1777, 1701, 1673, 1678, 1777, 578]

# A base and marks compose to the character the font maps, whichever form
# the text uses; the composite takes the cluster of both.
expect shaped(inter, "e\u(301)", latin) == { glyphs: [618], clusters: [0], advances: [1194], flags: [0] }
expect shaped(inter, "\u(E9)", latin).glyphs == [618]
expect shaped(inter, "\u(1EC7)", latin).glyphs == [640]
# Marks out of canonical order are reordered first.
expect shaped(inter, "a\u(323)\u(302)", latin) == { glyphs: [518], clusters: [0], advances: [1150], flags: [0] }

# Default-ignorable characters are drawn with the space glyph and no width;
# a ZWJ continues the cluster before it.
expect shaped(inter, "a\u(AD)b", latin) == { glyphs: [507, 1777, 578], clusters: [0, 1, 3], advances: [1150, 0, 1254], flags: [0, 0, 0] }
expect shaped(inter, "x\u(200D)y", latin) == { glyphs: [993, 1777, 998], clusters: [0, 0, 4], advances: [1118, 0, 1151], flags: [0, 0, 0] }

# Spaces and the no-break hyphen the font maps keep their own glyphs.
expect shaped(inter, "A\u(2003)B", latin).glyphs == [2, 1784, 65]
expect shaped(inter, "A\u(2011)B", latin).glyphs == [2, 2593, 65]

# ------------------------------------------------------------ built fonts
#
# Glyph g (from 1) draws U+10000 + g, as in SubstituteTests; U+10000 maps
# nothing. Glyphs 5 and 6 are marks in `GDEF` (attachment classes 1 and 2),
# glyph 5 alone is in mark glyph set 0.

text_of : List(U64) -> Str
text_of = |glyphs| {
	var $bytes = []
	for g in glyphs {
		c = 0x10000 + g
		$bytes = $bytes.concat([0xF0 + c.shr_zf_wrap(18), 0x80 + c.shr_zf_wrap(12).bitwise_and(0x3F), 0x80 + c.shr_zf_wrap(6).bitwise_and(0x3F), 0x80 + c.bitwise_and(0x3F)].map(|b| b.to_u8_wrap()))
	}
	Str.from_utf8($bytes) ?? ""
}

base_tables : List({ tag : Str, data : List(U8) })
base_tables = [
	{ tag: "head", data: FontBuild.head(1000, False) },
	{ tag: "hhea", data: FontBuild.hhea(800, -200, 64) },
	{ tag: "maxp", data: FontBuild.maxp(64) },
	{ tag: "hmtx", data: FontBuild.hmtx(List.repeat(500, 64)) },
	{ tag: "cmap", data: FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 0x20, last: 0x20, glyph: 3 }, { first: 0x10001, last: 0x1003F, glyph: 1 }]) }]) },
]

gdef : List(U8)
gdef = FontBuild.pack([
	U32(0x00010002),
	Ref(FontBuild.classes2([{ first: 1, last: 4, class: 1 }, { first: 5, last: 6, class: 3 }])),
	U16(0),
	U16(0),
	Ref(FontBuild.classes2([{ first: 5, last: 5, class: 1 }, { first: 6, last: 6, class: 2 }])),
	Ref(FontBuild.pack([U16(1), U16(1), Ref32(FontBuild.coverage1([5]))])),
])

## A `GSUB` table whose feature `tag` uses every lookup; each lookup has a
## type, a lookup flag, a mark filtering set (used with flag 0x10) and its
## subtables.
gsub : Str, List({ kind : U64, flag : U64, set : U64, subtables : List(List(U8)) }) -> List(U8)
gsub = |tag, lookups| {
	language = FontBuild.pack([U16(0), U16(0xFFFF), U16(1), U16(0)])
	scripts = FontBuild.pack([U16(1), Tag("latn"), Ref(FontBuild.pack([Ref(language), U16(0)]))])
	features = FontBuild.pack([U16(1), Tag(tag), Ref(FontBuild.pack([U16(0), U16(lookups.len())].concat(lookups.map_with_index(|_, i| U16(i)))))])
	lookup_list = FontBuild.pack(
		[U16(lookups.len())].concat(
			lookups.map(
				|l| {
					filter = if (l.flag.bitwise_and(0x10) != 0) [U16(l.set)] else []
					Ref(FontBuild.pack([U16(l.kind), U16(l.flag), U16(l.subtables.len())].concat(l.subtables.map(|s| Ref(s))).concat(filter)))
				},
			),
		),
	)
	FontBuild.pack([U32(0x00010000), Ref(scripts), Ref(features), Ref(lookup_list)])
}

font_with : List({ tag : Str, data : List(U8) }) -> Font
font_with = |extra|
	match Font.from_bytes(FontBuild.file(base_tables.concat(extra)), Font.ReadOptions.{}) {
		Ok(font) => font
		Err(_) => crash "a built test font could not be read"
	}

# The ligature 1 + 2 -> 9, under a lookup flag.
ligature_font : U64, U64 -> Font
ligature_font = |flag, set| font_with([{ tag: "GDEF", data: gdef }, { tag: "GSUB", data: gsub("liga", [{ kind: 4, flag, set, subtables: [FontBuild.ligature([1], [[{ glyph: 9, rest: [2] }]])] }]) }])

glyphs_of : Font, List(U64) -> List(U32)
glyphs_of = |font, input| Font.shape(font, text_of(input), Font.ShapeOptions.{}).glyphs

# Ignoring marks, a ligature forms across a mark, which follows it; without
# the flag the mark blocks it.
expect glyphs_of(ligature_font(0x08, 0), [1, 5, 2]) == [9, 5]
expect Font.shape(ligature_font(0x08, 0), text_of([1, 5, 2]), Font.ShapeOptions.{}).clusters == [0, 0]
expect glyphs_of(ligature_font(0, 0), [1, 5, 2]) == [1, 5, 2]
# A mark filtering set keeps only its marks: mark 5 (in the set) blocks the
# ligature, mark 6 is skipped.
expect glyphs_of(ligature_font(0x10, 0), [1, 5, 2]) == [1, 5, 2]
expect glyphs_of(ligature_font(0x10, 0), [1, 6, 2]) == [9, 6]
# A mark attachment type keeps only marks of that class: type 1 skips mark
# 6 (class 2) and is blocked by mark 5 (class 1).
expect glyphs_of(ligature_font(0x0100, 0), [1, 6, 2]) == [9, 6]
expect glyphs_of(ligature_font(0x0100, 0), [1, 5, 2]) == [1, 5, 2]
# Ignoring base glyphs, a single substitution leaves base glyphs alone.
expect glyphs_of(font_with([{ tag: "GDEF", data: gdef }, { tag: "GSUB", data: gsub("liga", [{ kind: 1, flag: 0x02, set: 0, subtables: [FontBuild.single1([1, 5], 10)] }]) }]), [1, 5]) == [1, 15]

# Alternate substitution: the feature's value chooses; a value past the
# alternates changes nothing.
alternates : U64 -> List(U8)
alternates = |count| FontBuild.pack([U16(1), Ref(FontBuild.coverage1([1])), U16(1), Ref(FontBuild.pack([U16(count)].concat(FontBuild.counting(count).map(|i| U16(20 + i)))))])

salt_font : Font
salt_font = font_with([{ tag: "GSUB", data: gsub("salt", [{ kind: 3, flag: 0, set: 0, subtables: [alternates(2)] }]) }])

expect Font.shape(salt_font, text_of([1]), Font.ShapeOptions.{ features: [Font.Feature.{ tag: "salt" }] }).glyphs == [20]
expect Font.shape(salt_font, text_of([1]), Font.ShapeOptions.{ features: [Font.Feature.{ tag: "salt", value: 2 }] }).glyphs == [21]
expect Font.shape(salt_font, text_of([1]), Font.ShapeOptions.{ features: [Font.Feature.{ tag: "salt", value: 3 }] }).glyphs == [1]
expect Font.shape(salt_font, text_of([1, 1]), Font.ShapeOptions.{ features: [Font.Feature.{ tag: "salt", value: 2, start: 4, end: 8 }] }).glyphs == [1, 21]

# `rand` (on by default) picks alternates with HarfBuzz's generator, the
# same way every time.
expect {
	font = font_with([{ tag: "GSUB", data: gsub("rand", [{ kind: 3, flag: 0, set: 0, subtables: [alternates(3)] }]) }])
	glyphs_of(font, List.repeat(1, 12)) == [21, 20, 20, 20, 20, 20, 22, 22, 20, 21, 21, 22]
}

# Reverse chaining applies from the end: glyph 1 before 2 or 11 becomes 11,
# so a run of them changes whole.
expect {
	reverse = FontBuild.pack([U16(1), Ref(FontBuild.coverage1([1])), U16(0), U16(1), Ref(FontBuild.coverage1([2, 11])), U16(1), U16(11)])
	glyphs_of(font_with([{ tag: "GSUB", data: gsub("liga", [{ kind: 8, flag: 0, set: 0, subtables: [reverse] }]) }]), [1, 1, 2]) == [11, 11, 2]
}

# A space the font lacks is drawn with the space glyph at HarfBuzz's width
# for it: an em, a fifth of one, half the space.
expect {
	run = Font.shape(font_with([]), "\u(2003)\u(2009)\u(202F)", Font.ShapeOptions.{})
	run.glyphs == [3, 3, 3] and run.advances.map(|a| a.x) == [1000, 200, 250]
}

# A character the font does not map draws glyph 0 with the missing flag
# (bit 1); grapheme-extending characters share their base's cluster.
expect Font.shape(font_with([]), text_of([1, 0, 2]), Font.ShapeOptions.{}).flags == [0, 2, 0]
expect {
	run = Font.shape(font_with([]), "\u(1F44D)\u(1F3FD)", Font.ShapeOptions.{})
	run.glyphs == [0, 0] and run.clusters == [0, 0] and run.flags == [2, 2]
}
