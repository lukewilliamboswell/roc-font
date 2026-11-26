import build.FontBuild
import font.Font

# OpenType 1.9.1 glyf and gvar. Vary the child outlines, apply any
# component transformation, then align the two contour points.
# https://learn.microsoft.com/en-us/typography/opentype/spec/glyf
# https://learn.microsoft.com/en-us/typography/opentype/spec/gvar#point-numbers-and-processing-for-composite-glyphs
PointComposites := {}.{
	check : {} -> Bool
	check = |_| {
		base = Font.from_bytes(fixture, Font.ReadOptions.{ strict: True }) ?? crash "point-attached composite fixture was rejected"
		[
			{ weight: 200, right: 148, top: 56 },
			{ weight: 400, right: 148, top: 56 },
			{ weight: 600, right: 152, top: 62 },
			{ weight: 800, right: 156, top: 68 },
		].all(
			|row| {
				font = Font.at(base, Font.Variation.{ axes: [{ tag: "wght", value: row.weight }] })
				actual = Font.extents(font, 4)
				if actual == Extents({ x_min: 0, y_min: 0, x_max: row.right, y_max: row.top }) {
					True
				} else {
					crash "point-attached composite at ${row.weight.to_str()}: ${Str.inspect(actual)}"
				}
			},
		)
	}
}

rectangle : I64, I64, I64, I64 -> List(U8)
rectangle = |l, b, r, t| FontBuild.simple_glyph([
	[{ x: l, y: b, on: True }, { x: r, y: b, on: True }, { x: r, y: t, on: True }, { x: l, y: t, on: True }],
])

peak : List(I64), List(I64) -> FontBuild.GvarTuple
peak = |xs, ys| { peak: Embedded([16384]), between: Peak, points: Own([0, 1, 2, 3]), xs, ys }

fixture : List(U8)
fixture = {
	# The first two components give eight parent points. Point 6 is
	# the third point in the second component, at (120, 40) before
	# variation. At scalar s its position is (120 + 16s, 40 + 8s).
	# The donor transforms (x, y) to (-y/2, x). Relative to its
	# transformed point 3, it reaches 28 - 8s right and 16 + 4s up.
	composite = FontBuild.pack([
		I16(-1),
		I16(0),
		I16(0),
		I16(148),
		I16(56),
		U16(0x0023),
		U16(1),
		I16(0),
		I16(0),
		U16(0x0023),
		U16(2),
		I16(100),
		I16(20),
		U16(0x0081),
		U16(3),
		U16(6),
		U16(3),
		I16(0),
		I16(16384),
		I16(-8192),
		I16(0),
	])
	gvar = FontBuild.gvar(
		1,
		[],
		[
			{ shared: None, tuples: [] },
			{ shared: None, tuples: [] },
			{ shared: None, tuples: [peak([0, 0, 16, 0], [0, 0, 8, 0])] },
			{ shared: None, tuples: [peak([0, 8, 8, 4], [0, 0, 0, -16])] },
			{ shared: None, tuples: [] },
		],
		False,
	)
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'A', glyph: 4 }]) }])
	FontBuild.outline_font(
		[[], rectangle(0, 0, 16, 16), rectangle(0, 0, 20, 20), rectangle(24, 8, 40, 64), composite],
		List.repeat(500, 5),
		[0, 0, 0, 24, 0],
		5,
		False,
		cmap,
		[
			{ tag: "fvar", data: FontBuild.fvar([{ tag: "wght", min: 200, default: 400, max: 800 }]) },
			{ tag: "gvar", data: gvar },
		],
	)
}
