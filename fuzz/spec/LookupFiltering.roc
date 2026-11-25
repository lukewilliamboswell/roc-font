import build.FontBuild
import font.Font

LookupFiltering := [].{
	check : {} -> Bool
	check = |{}| {
		face = font_with_filters({})
		cases = [
			# The parent selects E and reaches B. The ligature still needs F.
			{ text: "AEB", glyphs: [1, 5, 9], clusters: [0, 1, 2] },
			# F belongs to attachment class 2 but is outside the parent's set.
			{ text: "AFB", glyphs: [1, 6, 2], clusters: [0, 1, 2] },
			# The ligature child can use F, which the parent skipped. Its own
			# class filter skips E, which stays at the ligature's cluster.
			{ text: "AEFB", glyphs: [8, 5, 9], clusters: [0, 0, 3] },
			# With adjacent components, E keeps its own source cluster.
			{ text: "AFEB", glyphs: [8, 5, 9], clusters: [0, 2, 3] },
			# An additional set member blocks the parent's match.
			{ text: "AEEFB", glyphs: [1, 5, 5, 6, 2], clusters: [0, 1, 2, 3, 4] },
		]
		for case in cases {
			run = Font.shape(face, case.text, Font.ShapeOptions.{ script: "Latn" })
			if (run.glyphs, run.clusters) != (case.glyphs, case.clusters) {
				crash "lookup filters for ${case.text}: ${Str.inspect((run.glyphs, run.clusters))}"
			}
		}
		True
	}
}

# OpenType 1.9.1 Layout Common Table Formats, "Lookup table". A mark
# filtering set supersedes an attachment class. The parent flags select
# the input slots. Each nested lookup then uses its own flags.
# https://learn.microsoft.com/en-us/typography/opentype/spec/chapter2#lookup-table
font_with_filters : {} -> Font
font_with_filters = |{}| {
	gsub = FontBuild.flagged_listing(
		"calt",
		[0],
		[
			{
				kind: 5,
				flag: 0x0210,
				set: 0,
				subtables: [FontBuild.context3([[1], [5, 6], [2]], [{ at: 2, lookup: 1 }, { at: 0, lookup: 2 }])],
			},
			{ kind: 1, flag: 0, set: 0, subtables: [FontBuild.single2([2], [9])] },
			{ kind: 4, flag: 0x0200, set: 0, subtables: [FontBuild.ligature([1], [[{ glyph: 8, rest: [6] }]])] },
		],
	)
	cmap = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 'A', last: 'F', delta: 65536 - 64, glyphs: [] }]) }])
	file = FontBuild.glyphs_font(List.repeat(500, 10), cmap, [{ tag: "GDEF", data: FontBuild.marks_gdef }, { tag: "GSUB", data: gsub }])
	Font.from_bytes(file, Font.ReadOptions.{ strict: True }) ?? crash "lookup filtering fixture did not read strictly"
}
