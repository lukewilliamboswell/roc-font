import build.FontBuild
import font.Font

# HarfBuzz 14.6.0 positions marks from the base advance and the ink
# bounds. In position_around_base, consecutive marks of the same
# positioning class grow the bounds. A class change starts at the
# base again, even for two classes that both place their marks above.
# https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/hb-ot-shape-fallback.cc
FallbackMarks := {}.{
	check : {} -> Bool
	check = |_| {
		font = fixture({})
		# At 1000 units per em the gap is 62. With A's top at 520,
		# the second accent starts after the gap and the first
		# accent's height. U+0315 resets to 520 plus one gap and
		# aligns to the right edge of A's 600-unit advance.
		agrees(
			font,
			"A\u(323)\u(301)\u(300)\u(315)B\u(301)",
			{
				glyphs: [1, 6, 4, 3, 5, 2, 4],
				clusters: [0, 1, 3, 5, 7, 9, 10],
				advances: [600, 0, 0, 0, 0, 31, 0],
				offsets: [
					{ x: 0, y: 0 },
					{ x: -328, y: -117 },
					{ x: -310, y: 572 },
					{ x: -347, y: 691 },
					{ x: -55, y: 586 },
					{ x: 0, y: 0 },
					{ x: -25, y: 392 },
				],
				flags: [0, 1, 1, 1, 1, 0, 1],
			},
		) and agrees(
			font,
			"A\u(300)\u(301)\u(315)",
			{
				glyphs: [1, 3, 4, 5],
				clusters: [0, 1, 3, 5],
				advances: [600, 0, 0, 0],
				offsets: [{ x: 0, y: 0 }, { x: -347, y: 595 }, { x: -310, y: 686 }, { x: -55, y: 586 }],
				flags: [0, 1, 1, 1],
			},
		)
	}
}

fixture : {} -> Font
fixture = |_| {
	box = |left, bottom, right, top| FontBuild.simple_glyph([
		[{ x: left, y: bottom, on: True }, { x: right, y: bottom, on: True }, { x: left, y: top, on: True }],
	])
	# The two bases have distinct widths and ink. Nonzero mark advances
	# make zeroing observable. Mark boxes differ in both axes.
	glyphs = [
		[],
		box(40, -30, 440, 520),
		box(-17, -90, 330, 340),
		box(7, -13, 87, 39),
		box(-20, 10, 40, 44),
		box(15, -4, 55, 16),
		box(3, -5, 53, 25),
	]
	cmap = FontBuild.cmap([
		{
			system: 3,
			encoding: 10,
			subtable: FontBuild.cmap12([
				{ first: 'A', last: 'B', glyph: 1 },
				{ first: 0x0300, last: 0x0301, glyph: 3 },
				{ first: 0x0315, last: 0x0315, glyph: 5 },
				{ first: 0x0323, last: 0x0323, glyph: 6 },
			]),
		},
	])
	file = FontBuild.outline_font(glyphs, [500, 600, 31, 123, 111, 150, 99], [0, 40, -17, 7, -20, 15, 3], 7, False, cmap, [])
	Font.from_bytes(file, Font.ReadOptions.{ strict: True }) ?? crash "fallback mark fixture did not read strictly"
}

Expected : { glyphs : List(U32), clusters : List(U64), advances : List(I32), offsets : List({ x : I32, y : I32 }), flags : List(U8) }

agrees : Font, Str, Expected -> Bool
agrees = |font, text, { glyphs, clusters, advances, offsets, flags }| {
	run = Font.shape(font, text, Font.ShapeOptions.{ script: "Latn", clusters: Characters })
	want = { glyphs, clusters, advances: advances.map(|x| { x, y: 0 }), offsets, flags }
	if run == want {
		True
	} else {
		crash "fallback marks for ${Str.inspect(text)} expected ${Str.inspect(want)}, got ${Str.inspect(run)}"
	}
}
