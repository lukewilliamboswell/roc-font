import build.FontBuild
import build.MarkBuild
import font.Font

# HarfBuzz 14.6.0 at cluster level 1 agrees with both cases. The acute
# mark takes component two after nested substitution and the last
# component when D supplies the same intermediate glyph directly.
LigatureProvenance := {}.{
	check : {} -> Bool
	check = |_| {
		font = fixture({})
		options = Font.ShapeOptions.{ script: "Latn", clusters: Characters }
		cases = [
			{ text: "A\u(300)B\u(301)C\u(302)", glyphs: [8, 4, 5, 6], clusters: [0, 0, 0, 7], offsets: [(0, 0), (-631, 193), (-397, -63), (-199, 97)], flags: [0, 0, 0, 1] },
			{ text: "AD\u(301)", glyphs: [8, 5], clusters: [0, 2], offsets: [(0, 0), (-157, 67)], flags: [0, 1] },
		]
		for case in cases {
			run = Font.shape(font, case.text, options)
			advances = [{ x: 720, y: 0 }].concat(List.repeat({ x: 0, y: 0 }, case.glyphs.len() - 1))
			if run.glyphs != case.glyphs or run.clusters != case.clusters or run.advances != advances or run.flags != case.flags or run.offsets != case.offsets.map(|(x, y)| { x, y }) {
				crash "nested ligature mark placement ${Str.inspect(case.text)}: ${Str.inspect(run)}"
			}
		}
		True
	}
}

fixture : {} -> Font
fixture = |_| {
	cmap = FontBuild.cmap([
		{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'C', glyph: 1 }, { first: 'D', last: 'D', glyph: 7 }, { first: 0x300, last: 0x302, glyph: 4 }]) },
	])
	gdef = MarkBuild.gdef([{ first: 1, last: 3, class: 1 }, { first: 4, last: 6, class: 3 }, { first: 7, last: 8, class: 2 }], [])
	lookup = |first, second, glyph| MarkBuild.Lookup.{ kind: 4, flag: 8, subtables: [FontBuild.ligature([first], [[{ glyph, rest: [second] }]])] }
	# B+C produces glyph 7, then A+7 produces glyph 8. The mark on B
	# follows glyph 7 and needs A's component added to its old index.
	gsub = MarkBuild.layout("latn", [{ tag: "liga", lookups: [0, 1] }], [lookup(2, 3, 7), lookup(1, 7, 8)])
	a = MarkBuild.anchor
	marks = [{ glyph: 4, class: 0, anchor: a(11, 17) }, { glyph: 5, class: 0, anchor: a(-13, 23) }, { glyph: 6, class: 0, anchor: a(29, -7) }]
	mark = MarkBuild.ligatures(marks, 1, [{ glyph: 8, components: [[a(100, 210)], [a(310, -40)], [a(550, 90)]] }])
	gpos = MarkBuild.layout("latn", [{ tag: "mark", lookups: [0] }], [MarkBuild.Lookup.{ kind: 5, subtables: [mark] }])
	bytes = FontBuild.glyphs_font([500, 500, 500, 500, 0, 0, 0, 600, 720], cmap, [{ tag: "GDEF", data: gdef }, { tag: "GSUB", data: gsub }, { tag: "GPOS", data: gpos }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "nested ligature mark fixture rejected"
}
