import build.FontBuild
import font.Font

# GPOS pair ValueRecords can mix pixel-size Device tables and design-space
# VariationIndex references. HarfBuzz 14.6.0 at scale 1000 and ppem zero
# applies only the VariationIndex deltas, in both records of this pair.
PairDevices := {}.{
	check : {} -> Bool
	check = |_| {
		font = Font.from_bytes(fixture({}), Font.ReadOptions.{ strict: True }) ?? crash "valid mixed pair device fixture rejected"
		var $at = font
		for row in [
			{ variation: Font.Variation.{}, advance: 480, first_x: 7, second_y: 9 },
			{ variation: Font.Variation.{ weight: Weight(600) }, advance: 478, first_x: 12, second_y: 13 },
			{ variation: Font.Variation.{ weight: Weight(800) }, advance: 475, first_x: 16, second_y: 16 },
			{ variation: Font.Variation.{}, advance: 480, first_x: 7, second_y: 9 },
		] {
			$at = Font.at($at, row.variation)
			run = Font.shape($at, "AB", Font.ShapeOptions.{})
			# The hint fields leave the first glyph's y and the second
			# glyph's x and advance at their stored values at every location.
			advances = [{ x: row.advance, y: 0 }, { x: 632, y: 0 }]
			offsets = [{ x: row.first_x, y: -8 }, { x: -4, y: row.second_y }]
			if run.glyphs != [1, 2] or run.clusters != [0, 1] or run.advances != advances or run.offsets != offsets or Font.width($at, "AB") != row.advance + 632 {
				crash "mixed pair device expected advances ${Str.inspect(advances)} and offsets ${Str.inspect(offsets)}, got ${Str.inspect(run)}"
			}
		}
		True
	}
}

fixture : {} -> List(U8)
fixture = |_| {
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'B', glyph: 1 }]) }])
	fvar = FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 800 }])
	ramp = { start: 0, peak: 16384, end: 16384 }
	# All three hint headers have start and end ppem 1. Their first two
	# words would identify a valid, nonzero row if read as variation indices.
	store = FontBuild.variation_store(1, [[ramp]], [{ regions: [0], rows: [[9], [-5], [7]] }, { regions: [0], rows: [[0], [-43]] }])
	device = FontBuild.device_field
	values = [
		I16(7),
		I16(-8),
		I16(-30),
		device(Index(0, 0)),
		device(Hinting(1, 1, 2, 0x2000)),
		device(Index(0, 1)),
		I16(-4),
		I16(9),
		I16(12),
		device(Hinting(1, 1, 1, 0xC000)),
		device(Index(0, 2)),
		device(Hinting(1, 1, 3, 0x7F00)),
	]
	pair_set = FontBuild.pack([U16(1), U16(2)].concat(values))
	pair = FontBuild.pack([U16(1), Ref(FontBuild.coverage1([1])), U16(0x77), U16(0x77), U16(1), Ref(pair_set)])
	gpos = FontBuild.layout("latn", [{ tag: "kern", lookups: [0] }], [{ kind: 2, subtables: [pair] }])
	FontBuild.glyphs_font([500, 510, 620], cmap, [{ tag: "fvar", data: fvar }, { tag: "GDEF", data: FontBuild.gdef_store(store) }, { tag: "GPOS", data: gpos }])
}
