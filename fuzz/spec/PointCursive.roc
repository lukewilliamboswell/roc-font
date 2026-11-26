import build.FontBuild
import build.MarkBuild
import font.Font

# OpenType GPOS Anchor format 2 stores coordinates and a contour point.
# With ppem unset, HarfBuzz 14.6.0 uses the stored coordinates even when
# both glyphs have real outlines and gvar moves the referenced points.
PointCursive := {}.{
	check : {} -> Bool
	check = |_| [False, True].all(|point_exit| [False, True].all(|point_entry| check_pair(point_exit, point_entry)))
}

check_pair : Bool, Bool -> Bool
check_pair = |point_exit, point_entry| {
	font = Font.from_bytes(fixture(point_exit, point_entry), Font.ReadOptions.{ strict: True }) ?? crash "valid cursive point-anchor fixture was rejected"
	var $at = font
	for half_steps in [0, 1, 2, 0] {
		variation = if (half_steps == 0) Font.Variation.{} else Font.Variation.{ weight: Weight((400 + 200 * half_steps).to_u16_wrap()) }
		$at = Font.at($at, variation)
		# The point referenced by A's anchor sets both maxima. The point
		# referenced by B's anchor sets yMax and lies inside the x range.
		a = Extents({ x_min: 0, y_min: 0, x_max: 37 + 10 * half_steps, y_max: 44 + 8 * half_steps })
		b = Extents({ x_min: 0, y_min: 0, x_max: 32, y_max: 35 + 12 * half_steps })
		run = Font.shape($at, "AB", Font.ShapeOptions.{ script: "Latn" })
		# The pen advances to A's exit (54). B's entry is 13 units from
		# its origin, so its x offset is −13 and its advance is 130 − 13.
		# A stays on the baseline and B shifts by 11 − (−6).
		if Font.extents($at, 1) != a or Font.extents($at, 2) != b or run.glyphs != [1, 2] or run.clusters != [0, 1]
			or run.advances != [{ x: 54, y: 0 }, { x: 117, y: 0 }] or run.offsets != [{ x: 0, y: 0 }, { x: -13, y: 17 }]
			or run.flags.map(Font.is_unsafe_to_break) != [False, True] {
			crash "cursive format 2 exit ${Str.inspect(point_exit)}, entry ${Str.inspect(point_entry)}, half steps ${Str.inspect(half_steps)}: ${Str.inspect(run)}"
		}
	}
	True
}

fixture : Bool, Bool -> List(U8)
fixture = |point_exit, point_entry| {
	geometry = |points| FontBuild.simple_glyph([points.map(|(x, y)| { x, y, on: True })])
	glyphs = [[], geometry([(0, 0), (37, 44), (5, 8)]), geometry([(0, 0), (32, 7), (23, 35)])]
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'B', glyph: 1 }]) }])
	fvar = FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 800 }])
	moves = |xs, ys| { shared: None, tuples: [{ peak: Embedded([16384]), between: Peak, points: Own([0, 1, 2]), xs, ys }] }
	gvar = FontBuild.gvar(1, [], [{ shared: None, tuples: [] }, moves([0, 20, 0], [0, 16, 0]), moves([0, 0, -12], [0, 0, 24])], False)
	anchor = |with_point, x, y, index| if (with_point) MarkBuild.point_anchor(x, y, index) else MarkBuild.anchor(x, y)
	subtable = FontBuild.pack([
		U16(1),
		Ref(FontBuild.coverage1([1, 2])),
		U16(2),
		U16(0),
		Ref(anchor(point_exit, 54, 11, 1)),
		Ref(anchor(point_entry, 13, -6, 2)),
		U16(0),
	])
	gpos = FontBuild.layout("latn", [{ tag: "curs", lookups: [0] }], [{ kind: 3, subtables: [subtable] }])
	FontBuild.outline_font(glyphs, [500, 100, 130], [0, 0, 0], 3, False, cmap, [{ tag: "fvar", data: fvar }, { tag: "gvar", data: gvar }, { tag: "GPOS", data: gpos }])
}
