import build.FontBuild
import font.Font

IndicShapeTests :: {}.{}

# The presentation subtable can see the i sign only after its move to
# the left of ka. The face's advances also make that move observable in
# visual pen coordinates. The three syllables occupy 0..6, 6..12, 12..15.
expect {
	gsub = FontBuild.layout(
		"dev2",
		[{ tag: "ccmp", lookups: [0] }, { tag: "pres", lookups: [1] }],
		[
			{ kind: 1, subtables: [FontBuild.single1([2], 4)] },
			{ kind: 6, subtables: [FontBuild.chain3([], [[6]], [[1]], [{ at: 0, lookup: 2 }])] },
			{ kind: 1, subtables: [FontBuild.single1([6], 1)] },
		],
	)
	cmap = FontBuild.cmap([
		{
			system: 3,
			encoding: 10,
			subtable: FontBuild.cmap12([
				{ first: 0x0915, last: 0x0915, glyph: 1 },
				{ first: 0x0924, last: 0x0924, glyph: 3 },
				{ first: 0x092C, last: 0x092C, glyph: 5 },
				{ first: 0x093E, last: 0x093E, glyph: 4 },
				{ first: 0x093F, last: 0x093F, glyph: 2 },
			]),
		},
	])
	raw = FontBuild.glyphs_font([500, 700, 210, 520, 240, 490, 235, 260], cmap, [{ tag: "GSUB", data: gsub }])
	font = Font.from_bytes(raw, Font.ReadOptions.{ strict: True }) ?? crash "Indic trace fixture was rejected"
	text = "किताब"
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Deva", language: "hi" })
	trace = Font.shape_traced(font, plan, text) ?? crash "the short word exhausted shaping budgets"
	advance = trace.run.advances
	ranges = Font.cluster_ranges(trace.run, text.to_utf8().len())
	control = Font.shape(font, text, Font.ShapeOptions.{ script: "Deva", language: "ne" })
	trace.run.glyphs == [7, 1, 3, 4, 5]
		and advance == [260, 700, 520, 240, 490].map(|x| { x, y: 0 })
		and trace.origins == [Substituted({ feature: "pres" }), Mapped, Mapped, Mapped, Mapped]
		and ranges == [{ start: 0, end: 6 }, { start: 0, end: 6 }, { start: 6, end: 12 }, { start: 6, end: 12 }, { start: 12, end: 15 }]
		and control.glyphs == [1, 6, 3, 4, 5]
}
