import build.FontBuild
import font.Font

# HarfBuzz 14.6.0, _hb_ot_shape_fallback_spaces. A missing figure
# space uses the first mapped digit's advance. Missing punctuation
# space prefers a period, then a comma. Without a donor, each keeps
# the regular space advance. GPOS then adjusts the glyph in the run.
# https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/hb-ot-shape-fallback.cc
SpaceWidths := {}.{
	check : {} -> Bool
	check = |_| [BothDonors, LaterDonors, NeitherDonor, Mapped].all(check_font)
}

Scenario : [BothDonors, LaterDonors, NeitherDonor, Mapped]

fixture : Scenario -> List(U8)
fixture = |scenario| {
	mapping = |cp, glyph| { first: cp, last: cp, glyph }
	donors = match scenario {
		BothDonors | Mapped => [mapping(',', 6), mapping('.', 5), mapping('0', 3), mapping('7', 4)]
		LaterDonors => [mapping(',', 6), mapping('7', 4)]
		NeitherDonor => []
	}
	explicit = if (scenario == Mapped) [mapping(0x2007, 2), mapping(0x2008, 7)] else []
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([mapping(' ', 2)].concat(donors).append(mapping('A', 1)).concat(explicit)) }])
	fvar = FontBuild.fvar([{ tag: "wght", min: 200, default: 400, max: 800 }])
	store = FontBuild.variation_store(1, [[{ start: 0, peak: 16384, end: 16384 }]], [{ regions: [0], rows: [[0], [0], [30], [41], [51], [22], [32], [16]] }])
	pairs = [2, 7].map(|glyph| { glyph, pairs: [{ second: 1, values: [6, -7, 13] }] })
	position = FontBuild.pair1(7, 0, pairs)
	gpos = FontBuild.layout("DFLT", [{ tag: "kern", lookups: [0] }], [{ kind: 2, subtables: [position] }])
	FontBuild.glyphs_font(
		[500, 500, 301, 601, 701, 212, 142, 451],
		cmap,
		[
			{ tag: "fvar", data: fvar },
			{ tag: "HVAR", data: FontBuild.hvar(store, []) },
			{ tag: "GPOS", data: gpos },
		],
	)
}

check_font : Scenario -> Bool
check_font = |scenario| {
	face = Font.from_bytes(fixture(scenario), Font.ReadOptions.{ strict: True }) ?? crash "space width fixture did not read strictly"
	agrees(face, scenario, 0) and agrees(Font.at(face, Font.Variation.{ weight: Weight(800) }), scenario, 1)
}

agrees : Font, Scenario, I32 -> Bool
agrees = |font, scenario, peak| {
	space = 301 + peak * 30
	(figure, punctuation) = match scenario {
		BothDonors => (601 + peak * 41, 212 + peak * 22)
		LaterDonors => (701 + peak * 51, 142 + peak * 32)
		NeitherDonor => (space, space)
		Mapped => (space, 451 + peak * 16)
	}
	# NBSP, figure, punctuation, narrow NBSP, and medium mathematical space.
	# The mapped figure space shares the regular space glyph with the
	# fallbacks. Its explicit character mapping gives it the normal width.
	spaces = if (scenario == Mapped) [2, 2, 7, 2, 2] else [2, 2, 2, 2, 2]
	widths = [500].concat([space, figure, punctuation, space // 2, 222].join_map(|width| [width + 13, 500]))
	zero = { x: 0, y: 0 }
	offsets = [zero].concat(List.repeat([{ x: 6, y: -7 }, zero], 5).join_map(|pair| pair))
	run = Font.shape(font, "A\u(A0)A\u(2007)A\u(2008)A\u(202F)A\u(205F)A", Font.ShapeOptions.{ script: "Latn" })
	if run.glyphs == [1].concat(spaces.join_map(|g| [g, 1]))
		and run.clusters == [0, 1, 3, 4, 7, 8, 11, 12, 15, 16, 19]
		and run.advances == widths.map(|width| { x: width, y: 0 })
		and run.offsets == offsets
		and run.flags == [0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1] {
		True
	} else {
		crash "space advances for ${Str.inspect(scenario)} at peak scalar ${peak.to_str()}: ${Str.inspect(run)}"
	}
}
