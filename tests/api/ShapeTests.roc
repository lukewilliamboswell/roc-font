import font.Font
import build.FontBuild
import "../../tests/fonts/Inter-Regular-metrics.ttf" as inter_file : List(U8)

## The tests of shaping options: direction, script and language, features
## and their ranges, plans, scalars with offsets, widths, limits and
## unsafe-to-break flags, through the public `Font` API. Values said to be
## HarfBuzz's come from HarfBuzz 14.6.0 (uharfbuzz 0.56.3) at the monotone
## character cluster level, printed by `tests/api/oracle.py`. Run with
## `roc test tests/api/main.roc`.
ShapeTests :: {}.{}

inter : Font
inter = match Font.from_bytes(inter_file, Font.ReadOptions.{}) {
	Ok(font) => font
	Err(_) => crash "the Inter test font could not be read"
}

read : List({ tag : Str, data : List(U8) }) -> Font
read = |tables|
	match Font.from_bytes(FontBuild.file(tables), Font.ReadOptions.{}) {
		Ok(font) => font
		Err(_) => crash "a test font could not be read"
	}

Expected : { glyphs : List(U32), clusters : List(U64), advances : List(I32), flags : List(U8) }

agrees : Font.Run, Expected -> Bool
agrees = |run, expected|
	run.glyphs == expected.glyphs and run.clusters == expected.clusters and run.advances.map(|a| a.x) == expected.advances and run.flags == expected.flags and run.advances.all(|a| a.y == 0)

latin : Font.ShapeOptions
latin = Font.ShapeOptions.{ script: "Latn" }

# ------------------------------------------------------------ Inter against HarfBuzz

# Glyphs, clusters, advances and unsafe-to-break flags: a kerned pair is
# unsafe to break between its glyphs, and so is a contextual substitution
# across its context.
expect agrees(Font.shape(inter, "AVATAR", latin), { glyphs: [2, 456, 2, 411, 2, 384], clusters: [0, 1, 2, 3, 4, 5], advances: [1273, 1273, 1239, 1148, 1413, 1318], flags: [0, 1, 1, 1, 1, 0] })
expect agrees(Font.shape(inter, "Tomorrow", latin), { glyphs: [411, 790, 766, 790, 852, 852, 790, 984], clusters: [0, 1, 2, 3, 4, 5, 6, 7], advances: [1162, 1228, 1794, 1228, 803, 737, 1191, 1676], flags: [0, 1, 0, 0, 0, 1, 1, 1] })
expect agrees(Font.shape(inter, "office ->", latin), { glyphs: [790, 647, 647, 689, 586, 614, 1777, 1805], clusters: [0, 1, 2, 3, 4, 5, 6, 7], advances: [1228, 678, 758, 496, 1170, 1194, 576, 1954], flags: [0, 0, 1, 0, 0, 0, 0, 0] })
expect agrees(Font.shape(inter, "A*B", latin), { glyphs: [2, 1548, 65], clusters: [0, 1, 2], advances: [1344, 1321, 1340], flags: [0, 1, 0] })

# A ligature takes the clusters of all its characters, so nothing inside
# it is a break.
expect agrees(Font.shape(inter, "x --> y", latin), { glyphs: [993, 1777, 1806, 1777, 998], clusters: [0, 1, 2, 5, 6], advances: [1118, 576, 2746, 576, 1151], flags: [0, 0, 0, 0, 0] })

# Right to left: the run is in visual order. For a script written left to
# right, HarfBuzz shapes the reversed text, so kerning and contextual forms
# see the glyphs in visual order. (HarfBuzz also mirrors characters such as
# `>` in right-to-left text, from Unicode data roc-font leaves to the
# `unicode` package; these texts have none.)
expect agrees(Font.shape(inter, "AV", Font.ShapeOptions.{ script: "Latn", direction: RightToLeft }), { glyphs: [456, 2], clusters: [1, 0], advances: [1273, 1413], flags: [1, 0] })
expect agrees(Font.shape(inter, "AVATAR", Font.ShapeOptions.{ script: "Latn", direction: RightToLeft }), { glyphs: [384, 2, 411, 2, 456, 2], clusters: [5, 4, 3, 2, 1, 0], advances: [1318, 1239, 1148, 1273, 1273, 1413], flags: [0, 1, 1, 1, 1, 0] })
expect agrees(Font.shape(inter, "office", Font.ShapeOptions.{ script: "Latn", direction: RightToLeft }), { glyphs: [614, 586, 689, 647, 647, 790], clusters: [5, 4, 3, 2, 1, 0], advances: [1194, 1170, 496, 678, 698, 1228], flags: [0, 0, 0, 1, 1, 0] })
expect agrees(Font.shape(inter, "Tomorrow", Font.ShapeOptions.{ script: "Latn", direction: RightToLeft }), { glyphs: [984, 790, 852, 852, 790, 766, 790, 411], clusters: [7, 6, 5, 4, 3, 2, 1, 0], advances: [1639, 1228, 803, 737, 1228, 1794, 1068, 1322], flags: [1, 0, 1, 1, 0, 0, 1, 0] })

# For a right-to-left script (here Thaana, which HarfBuzz's default shaper
# shapes) the text is shaped in its own order and the run reversed.
expect agrees(Font.shape(inter, "AVATAR", Font.ShapeOptions.{ script: "Thaa", direction: RightToLeft }), { glyphs: [384, 2, 411, 2, 456, 2], clusters: [5, 4, 3, 2, 1, 0], advances: [1318, 1413, 1148, 1239, 1273, 1273], flags: [0, 1, 1, 1, 1, 0] })
expect agrees(Font.shape(inter, "office", Font.ShapeOptions.{ script: "Thaa", direction: RightToLeft }), { glyphs: [614, 586, 689, 647, 647, 790], clusters: [5, 4, 3, 2, 1, 0], advances: [1194, 1170, 496, 758, 678, 1228], flags: [0, 0, 0, 1, 0, 0] })

# `FromScript` takes the script's own direction.
expect Font.shape(inter, "AV", Font.ShapeOptions.{ script: "Thaa" }).clusters == [1, 0]
expect Font.shape(inter, "AV", Font.ShapeOptions.{ script: "Hebr" }).clusters == [1, 0]
expect Font.shape(inter, "AV", Font.ShapeOptions.{ script: "Latn" }).clusters == [0, 1]
expect Font.shape(inter, "AV", Font.ShapeOptions.{}).clusters == [0, 1]

# Features: off over a byte range, off everywhere, off for the second
# glyph of a pair (a pair needs the feature on both glyphs), and on.
expect agrees(Font.shape(inter, "->->", Font.ShapeOptions.{ script: "Latn", features: [Font.Feature.{ tag: "calt", value: 0, end: 2 }, Font.Feature.{ tag: "liga", value: 0, end: 2 }] }), { glyphs: [1459, 1517, 1805], clusters: [0, 1, 2], advances: [942, 1355, 1954], flags: [0, 0, 0] })
expect agrees(Font.shape(inter, "AVA", Font.ShapeOptions.{ script: "Latn", features: [Font.Feature.{ tag: "kern", value: 0 }] }), { glyphs: [2, 456, 2], clusters: [0, 1, 2], advances: [1413, 1413, 1413], flags: [0, 0, 0] })
expect agrees(Font.shape(inter, "AVA", Font.ShapeOptions.{ script: "Latn", features: [Font.Feature.{ tag: "kern", value: 0, start: 1, end: 3 }] }), { glyphs: [2, 456, 2], clusters: [0, 1, 2], advances: [1413, 1413, 1413], flags: [0, 0, 0] })
expect agrees(Font.shape(inter, "1234", Font.ShapeOptions.{ script: "Latn", features: [Font.Feature.{ tag: "tnum" }] }), { glyphs: [1360, 1361, 1362, 1363], clusters: [0, 1, 2, 3], advances: [1328, 1328, 1328, 1328], flags: [0, 0, 0, 0] })

# A later feature setting wins: on, then off.
expect Font.shape(inter, "1234", Font.ShapeOptions.{ features: [Font.Feature.{ tag: "tnum" }, Font.Feature.{ tag: "tnum", value: 0 }] }).glyphs == Font.shape(inter, "1234", Font.ShapeOptions.{}).glyphs

# Greek and Cyrillic, with clusters as UTF-8 byte offsets.
expect agrees(Font.shape(inter, "\u(3B1)\u(3B2)\u(3B3)", Font.ShapeOptions.{ script: "Grek" }), { glyphs: [1110, 1136, 1137], clusters: [0, 2, 4], advances: [1360, 1220, 1151], flags: [0, 0, 0] })
expect agrees(Font.shape(inter, "\u(41F)\u(440)\u(438)\u(432)\u(435)\u(442)", Font.ShapeOptions.{ script: "Cyrl" }), { glyphs: [2434, 848, 1262, 1254, 641, 1280], clusters: [0, 2, 4, 6, 8, 10], advances: [1522, 1254, 1211, 1157, 1194, 954], flags: [0, 0, 0, 0, 0, 0] })

# ------------------------------------------------------------ plans, scalars and widths

# A plan gives what shaping directly gives, for any text.
expect {
	plan = Font.plan(inter, latin)
	["AVATAR", "office ->", "", "A*B"].all(|t| Font.shape_planned(inter, plan, t) == Font.shape(inter, t, latin))
}

# Scalars with their offsets: the offsets are the clusters. Scalars that
# share an offset form one cluster, so kerning between them is no break.
expect {
	plan = Font.plan(inter, latin)
	run = Font.shape_scalars(inter, plan, [{ scalar: 'A', offset: 10 }, { scalar: 'V', offset: 10 }, { scalar: 'A', offset: 12 }])
	run.glyphs == [2, 456, 2] and run.clusters == [10, 10, 12] and run.flags == [0, 0, 1] and run.advances.map(|a| a.x) == [1273, 1273, 1413]
}
expect Font.shape_scalars(inter, Font.plan(inter, latin), []) == Font.shape(inter, "", latin)

# Offsets past 2^32 are clusters unchanged, never clamped, and feature
# ranges reach them.
expect {
	big = 5_000_000_000
	run = Font.shape_scalars(inter, Font.plan(inter, latin), [{ scalar: 'A', offset: big }, { scalar: 'V', offset: big + 1 }])
	run.clusters == [big, big + 1]
}
expect {
	big = 5_000_000_000
	gsub = layout_with([{ script: "latn", langs: [{ tag: "dflt", features: [0] }] }], ["smcp"])
	font = read(FontBuild.replace(FontBuild.basic, "GSUB", gsub))
	plan = Font.plan(font, Font.ShapeOptions.{ features: [Font.Feature.{ tag: "smcp", start: big + 1 }] })
	Font.shape_scalars(font, plan, [{ scalar: 'A', offset: big }, { scalar: 'A', offset: big + 1 }]).glyphs == [1, 2]
}

expect Font.width(inter, "AV") == 1273 + 1413
expect Font.width(inter, "") == 0
expect Font.width(inter, "x --> y") == 1118 + 576 + 2746 + 576 + 1151

# Both cluster levels merge ligature clusters the same way.
expect Font.shape(inter, "x --> y", Font.ShapeOptions.{ clusters: Characters }) == Font.shape(inter, "x --> y", Font.ShapeOptions.{ clusters: Graphemes })

# Empty text, and characters the font lacks (glyph 0).
expect Font.shape(inter, "", latin) == { glyphs: [], advances: [], offsets: [], clusters: [], flags: [] }
expect Font.shape(inter, "\u(378)", latin).glyphs == [0]

# ------------------------------------------------------------ scripts and languages

# A `GSUB` table with the scripts and language systems given, each a
# language system tag (`dflt` for the default) and the features it lists
# by index; feature i uses lookup i, which adds i + 1 to glyph 1.
layout_with : List({ script : Str, langs : List({ tag : Str, features : List(U64) }) }), List(Str) -> List(U8)
layout_with = |scripts, features| {
	langsys = |features_listed| FontBuild.pack([U16(0), U16(0xFFFF), U16(features_listed.len())].concat(features_listed.map(|i| U16(i))))
	script_table = |langs| {
		default = langs.find_first(|l| l.tag == "dflt")
		others = langs.drop_if(|l| l.tag == "dflt")
		default_field = match default {
			Ok(d) => Ref(langsys(d.features))
			Err(_) => U16(0)
		}
		FontBuild.pack([default_field, U16(others.len())].concat(others.join_map(|l| [Tag(l.tag), Ref(langsys(l.features))])))
	}
	script_list = FontBuild.pack([U16(scripts.len())].concat(scripts.join_map(|s| [Tag(s.script), Ref(script_table(s.langs))])))
	feature_list = FontBuild.pack([U16(features.len())].concat(features.map_with_index(|tag, i| [Tag(tag), Ref(FontBuild.pack([U16(0), U16(1), U16(i)]))]).join_map(|f| f)))
	lookup_list = FontBuild.pack([U16(features.len())].concat(features.map_with_index(|_, i| Ref(FontBuild.pack([U16(1), U16(0), U16(1), Ref(FontBuild.single1([1], (i + 1).to_i64_wrap()))])))))
	FontBuild.pack([U32(0x00010000), Ref(script_list), Ref(feature_list), Ref(lookup_list)])
}

# Glyph 1 (`A`) after shaping with these options.
first_glyph : List(U8), Font.ShapeOptions -> U32
first_glyph = |gsub, options| (Font.shape(read(FontBuild.replace(FontBuild.basic, "GSUB", gsub)), "A", options).glyphs.first() ?? 9999)

# Scripts are chosen by ISO 15924 code; an empty script is Latin; a script
# the font lacks falls back to `DFLT`, then `latn`.
expect {
	gsub = layout_with([{ script: "cyrl", langs: [{ tag: "dflt", features: [2] }] }, { script: "latn", langs: [{ tag: "dflt", features: [0] }] }], ["liga", "liga", "liga"])
	first_glyph(gsub, Font.ShapeOptions.{}) == 2 and first_glyph(gsub, Font.ShapeOptions.{ script: "Cyrl" }) == 4 and first_glyph(gsub, Font.ShapeOptions.{ script: "Grek" }) == 2 and first_glyph(gsub, Font.ShapeOptions.{ script: "cyrl" }) == 4
}
expect {
	gsub = layout_with([{ script: "DFLT", langs: [{ tag: "dflt", features: [1] }] }, { script: "latn", langs: [{ tag: "dflt", features: [0] }] }], ["liga", "liga"])
	first_glyph(gsub, Font.ShapeOptions.{ script: "Grek" }) == 3 and first_glyph(gsub, Font.ShapeOptions.{ script: "Latn" }) == 2
}

# Languages are chosen by BCP 47 tag: Turkish is `TRK`, Azerbaijani `AZE`;
# a language the script lacks uses its default language system. Private-use
# subtags give raw OpenType tags.
turkish : List(U8)
turkish = layout_with([{ script: "latn", langs: [{ tag: "dflt", features: [0] }, { tag: "AZE ", features: [2] }, { tag: "TRK ", features: [1] }] }], ["liga", "liga", "liga"])

expect first_glyph(turkish, Font.ShapeOptions.{}) == 2
expect first_glyph(turkish, Font.ShapeOptions.{ language: "tr" }) == 3
expect first_glyph(turkish, Font.ShapeOptions.{ language: "TR-tr" }) == 3
expect first_glyph(turkish, Font.ShapeOptions.{ language: "az-Latn" }) == 4
expect first_glyph(turkish, Font.ShapeOptions.{ language: "de" }) == 2
expect first_glyph(turkish, Font.ShapeOptions.{ language: "x-hbotTRK" }) == 3
expect first_glyph(turkish, Font.ShapeOptions.{ language: "en-x-hbot-54524b20" }) == 3
expect first_glyph(turkish, Font.ShapeOptions.{ language: "x-hbsccyrl" }) == 2

# Three-letter ISO 639-3 codes the table does not list are upper-cased.
expect first_glyph(layout_with([{ script: "latn", langs: [{ tag: "dflt", features: [0] }, { tag: "QQQ ", features: [1] }] }], ["liga", "liga"]), Font.ShapeOptions.{ language: "qqq" }) == 3

# Default features depend on direction: `ltra` for left to right, `rtla`
# for right to left.
expect {
	gsub = layout_with([{ script: "latn", langs: [{ tag: "dflt", features: [0, 1] }] }], ["ltra", "rtla"])
	first_glyph(gsub, Font.ShapeOptions.{}) == 2 and first_glyph(gsub, Font.ShapeOptions.{ direction: RightToLeft }) == 3
}

# A feature that is off by default applies when asked for, over its range.
expect {
	gsub = layout_with([{ script: "latn", langs: [{ tag: "dflt", features: [0] }] }], ["smcp"])
	font = read(FontBuild.replace(FontBuild.basic, "GSUB", gsub))
	Font.shape(font, "AAA", Font.ShapeOptions.{}).glyphs == [1, 1, 1] and Font.shape(font, "AAA", Font.ShapeOptions.{ features: [Font.Feature.{ tag: "smcp", start: 1, end: 2 }] }).glyphs == [1, 2, 1]
}

# ------------------------------------------------------------ synthetic runs

# Right to left on a font with no layout tables: the glyphs in visual
# order, clusters falling.
expect {
	run = Font.shape(read(FontBuild.basic), "ABC", Font.ShapeOptions.{ script: "Arab" })
	run.glyphs == [3, 2, 1] and run.clusters == [2, 1, 0] and run.advances.map(|a| a.x) == [800, 700, 600]
}

# A ligature's cluster is its first character's; the glyphs after it keep
# theirs.
expect {
	gsub = FontBuild.layout("latn", [{ tag: "liga", lookups: [0] }], [{ kind: 4, subtables: [FontBuild.ligature([1], [[{ glyph: 3, rest: [2] }]])] }])
	run = Font.shape(read(FontBuild.replace(FontBuild.basic, "GSUB", gsub)), "ABAC", Font.ShapeOptions.{})
	run.glyphs == [3, 1, 3] and run.clusters == [0, 2, 3]
}

# Pair positioning marks the second glyph unsafe to break; a pair whose
# values are all zero does not.
pairs_font : List(U8) -> Font
pairs_font = |subtable| read(FontBuild.replace(FontBuild.basic, "GPOS", FontBuild.layout("DFLT", [{ tag: "kern", lookups: [0] }], [{ kind: 2, subtables: [subtable] }])))

expect Font.shape(pairs_font(FontBuild.pair1(4, 0, [{ glyph: 1, pairs: [{ second: 2, values: [-50] }] }])), "ABA", Font.ShapeOptions.{}).flags == [0, 1, 0]
expect Font.shape(pairs_font(FontBuild.pair1(4, 0, [{ glyph: 1, pairs: [{ second: 2, values: [0] }] }])), "ABA", Font.ShapeOptions.{}).flags == [0, 0, 0]

# Placements move a glyph without changing its advance.
expect {
	run = Font.shape(pairs_font(FontBuild.pair1(0x07, 0x02, [{ glyph: 1, pairs: [{ second: 2, values: [3, 4, -50, 9] }] }])), "AB", Font.ShapeOptions.{})
	run.offsets == [{ x: 3, y: 4 }, { x: 0, y: 9 }] and run.advances == [{ x: 550, y: 0 }, { x: 700, y: 0 }]
}

# Contextual lookups nest as deep as `Limits.max_depth` allows: lookup 0
# calls 1, which calls 2, which adds 2.
expect {
	gsub = FontBuild.layout(
		"latn",
		[{ tag: "calt", lookups: [0] }],
		[
			{ kind: 5, subtables: [FontBuild.context3([[1]], [{ at: 0, lookup: 1 }])] },
			{ kind: 5, subtables: [FontBuild.context3([[1]], [{ at: 0, lookup: 2 }])] },
			{ kind: 1, subtables: [FontBuild.single1([1], 2)] },
		],
	)
	bytes = FontBuild.file(FontBuild.replace(FontBuild.basic, "GSUB", gsub))
	glyphs_with = |depth|
		match Font.from_bytes(bytes, Font.ReadOptions.{ limits: Font.Limits.{ max_depth: depth } }) {
			Ok(font) => Font.shape(font, "A", Font.ShapeOptions.{}).glyphs
			Err(_) => []
		}
	glyphs_with(64) == [3] and glyphs_with(2) == [3] and glyphs_with(1) == [1] and glyphs_with(0) == [1]
}

# ------------------------------------------------------------ the README example

readme_width : List(U8) -> Try(I32, List(Font.Problem))
readme_width = |bytes| {
	font = Font.from_bytes(bytes, Font.ReadOptions.{})?
	Ok(Font.width(font, "AV"))
}

readme_shaped : List(U8) -> Try(Font.Run, List(Font.Problem))
readme_shaped = |bytes| {
	font = Font.at(Font.from_bytes(bytes, Font.ReadOptions.{})?, Font.Variation.{ weight: Bold })
	Ok(Font.shape(font, "office -> home", Font.ShapeOptions.{ script: "Latn", language: "en" }))
}

expect readme_width(inter_file) == Ok(1273 + 1413)
expect {
	match readme_shaped(inter_file) {
		Ok(run) => run.glyphs.len() == 13 and run.clusters.first() == Ok(0)
		Err(_) => False
	}
}

# ------------------------------------------------------------ cluster levels against HarfBuzz

# Graphemes and characters as the units of clusters: glyphs, clusters and
# flags as HarfBuzz 14.6.0 (uharfbuzz 0.56.3) gives them at cluster levels 0
# and 1 (mark offsets come from `GPOS` mark positioning, which is not
# compared here).
by_level : Str, Font.ClusterLevel, Font.Direction -> { glyphs : List(U32), clusters : List(U64), flags : List(U8) }
by_level = |text, clusters, direction| {
	run = Font.shape(inter, text, Font.ShapeOptions.{ script: "Latn", direction, clusters })
	{ glyphs: run.glyphs, clusters: run.clusters, flags: run.flags }
}

# A letter and a combining acute: one cluster at the grapheme level; two at
# the character level, unsafe to break between them.
expect by_level("x\u(301)", Graphemes, LeftToRight) == { glyphs: [993, 1770], clusters: [0, 0], flags: [0, 0] }
expect by_level("x\u(301)", Characters, LeftToRight) == { glyphs: [993, 1770], clusters: [0, 1], flags: [0, 1] }

# Marks reordered by combining class merge the clusters of what moved, at
# either level.
expect by_level("x\u(301)\u(323)y", Graphemes, LeftToRight).clusters == [0, 0, 0, 5]
expect by_level("x\u(301)\u(323)y", Characters, LeftToRight) == { glyphs: [993, 1775, 1770, 998], clusters: [0, 1, 1, 5], flags: [0, 1, 1, 0] }

# An emoji modifier and a ZWJ sequence continue the grapheme before them.
expect by_level("\u(1F44D)\u(1F3FD)", Graphemes, LeftToRight) == { glyphs: [0, 0], clusters: [0, 0], flags: [2, 2] }
expect by_level("\u(1F44D)\u(1F3FD)", Characters, LeftToRight) == { glyphs: [0, 0], clusters: [0, 4], flags: [2, 3] }
expect by_level("a\u(200D)\u(1F600)b", Graphemes, LeftToRight) == { glyphs: [507, 1777, 0, 578], clusters: [0, 0, 0, 8], flags: [0, 0, 2, 0] }
expect by_level("a\u(200D)\u(1F600)b", Characters, LeftToRight) == { glyphs: [507, 1777, 0, 578], clusters: [0, 1, 4, 8], flags: [0, 1, 3, 0] }

# Shaped against the script's direction, graphemes reverse whole; at the
# character level their clusters merge as they do.
expect by_level("x\u(301)\u(323)y", Characters, RightToLeft).clusters == [5, 0, 0, 0]
expect by_level("\u(1F44D)\u(1F3FD)", Characters, RightToLeft).clusters == [0, 0]
