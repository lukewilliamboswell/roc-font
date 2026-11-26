import build.FontBuild
import font.Font

# BCP 47 identifies the locale. HarfBuzz 14.6 maps zh-Hant-MO to
# ZHTM, then ZHH. Each layout table can offer a different candidate.
# https://www.rfc-editor.org/rfc/rfc5646
# https://learn.microsoft.com/en-us/typography/opentype/spec/chapter2#language-system-table
LanguageSelection := {}.{
	check : {} -> Bool
	check = |_| [False, True].all(agrees)
}

Lang : { tag : Str, index : U64 }

languages : Bool -> List(Lang)
languages = |has_macau| {
	common = [{ tag: "ZHH ", index: 1 }, { tag: "ZHT ", index: 2 }]
	if (has_macau) common.append({ tag: "ZHTM", index: 3 }) else common
}

layout : U64, Str, List(Lang), List(List(U8)) -> List(U8)
layout = |kind, feature, offered, bodies| {
	langsys = |i| FontBuild.pack([U16(0), U16(0xFFFF), U16(1), U16(i)])
	script = FontBuild.pack([Ref(langsys(0)), U16(offered.len())].concat(offered.join_map(|row| [Tag(row.tag), Ref(langsys(row.index))])))
	scripts = FontBuild.pack([U16(1), Tag("hani"), Ref(script)])
	features = FontBuild.pack([U16(bodies.len())].concat(FontBuild.counting(bodies.len()).join_map(|i| [Tag(feature), Ref(FontBuild.pack([U16(0), U16(1), U16(i)]))])))
	lookups = FontBuild.pack([U16(bodies.len())].concat(bodies.map(|body| Ref(FontBuild.pack([U16(kind), U16(0), U16(1), Ref(body)])))))
	FontBuild.pack([U32(0x00010000), Ref(scripts), Ref(features), Ref(lookups)])
}

fixture : Bool -> Font
fixture = |macau_substitution| {
	# The first output glyph identifies the GSUB language. Its advance
	# then identifies the GPOS language, independently of that glyph.
	changes = [2, 3, 4, 5].map(|delta| FontBuild.single1([1], delta))
	pairs = [11, -23, 37, -41].map(
		|adjustment| FontBuild.pair1(4, 0, [3, 4, 5, 6].map(|glyph| { glyph, pairs: [{ second: 2, values: [adjustment] }] })),
	)
	gsub = layout(1, "locl", languages(macau_substitution), changes)
	gpos = layout(2, "kern", languages(!macau_substitution), pairs)
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 0x4E00, last: 0x4E01, glyph: 1 }]) }])
	bytes = FontBuild.glyphs_font([500, 600, 700, 800, 900, 1000, 1100], cmap, [{ tag: "GSUB", data: gsub }, { tag: "GPOS", data: gpos }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "valid Han language systems rejected"
}

agrees : Bool -> Bool
agrees = |macau_substitution| {
	font = fixture(macau_substitution)
	(macau_glyph, macau_delta) = if (macau_substitution) (6, -23) else (4, -41)
	cases = [
		("", 3, 11),
		("ja", 3, 11),
		("zh-Hant", 5, 37),
		("zh-Hant-HK", 4, -23),
		("zh-Hant-MO", macau_glyph, macau_delta),
		("ZH_hAnT_mO", macau_glyph, macau_delta),
		("zh-Hant-MO-u-nu-hanidec", macau_glyph, macau_delta),
	]
	cases.all(
		|(language, glyph, adjustment)| {
			run = Font.shape(font, "\u(4E00)\u(4E01)", Font.ShapeOptions.{ script: "Hani", language, direction: LeftToRight })
			run.glyphs == [glyph, 2]
				and run.clusters == [0, 3]
				and run.advances == [{ x: 500 + 100 * glyph.to_i32_wrap() + adjustment, y: 0 }, { x: 700, y: 0 }]
		},
	)
}
