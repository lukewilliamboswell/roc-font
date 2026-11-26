import build.FontBuild
import font.Font
import fuzz.Model

# OpenType 1.9.1, OpenType Layout Common Table Formats, “Feature variations”.
# Each layout table uses its first matching condition set. Format 1 range
# endpoints are inclusive. A user setting is an absolute location, so the
# default option for an omitted axis applies regardless of previous settings.
# https://learn.microsoft.com/en-us/typography/opentype/spec/chapter2#feature-variations
FeatureVariations := {}.{
	check : {} -> Bool
	check = |_| {
		result = report({})
		(result.verdict, result.states, result.steps, result.depth, result.reached.len()) == (Holds(Exhausted), 16, 400, 1, 5)
	}
}

Location : [Default, Below, Edge, Above]

Setting : [Omit, Set(Location)]

Move : { weight : Setting, width : Setting }

World : { weight : Location, width : Location, font : Try(Font, List(Font.Problem)) }

settings : List(Setting)
settings = [Omit, Set(Default), Set(Below), Set(Edge), Set(Above)]

location : Setting -> Location
location = |setting| match setting {
	Omit => Default
	Set(spot) => spot
}

coordinate : Location -> I16
coordinate = |spot| match spot {
	Default => 0
	Below => 8191
	Edge => 8192
	Above => 8193
}

axes : Move -> List({ tag : Str, value : Dec })
axes = |move| {
	# Sample both sides of 0.5 one F2Dot14 unit away from the overlap.
	weight = match move.weight {
		Omit => []
		Set(Default) => [{ tag: "wght", value: 400 }]
		Set(Below) => [{ tag: "wght", value: 599.9755859375 }]
		Set(Edge) => [{ tag: "wght", value: 600 }]
		Set(Above) => [{ tag: "wght", value: 600.0244140625 }]
	}
	width = match move.width {
		Omit => []
		Set(Default) => [{ tag: "wdth", value: 100 }]
		Set(Below) => [{ tag: "wdth", value: 124.9969482421875 }]
		Set(Edge) => [{ tag: "wdth", value: 125 }]
		Set(Above) => [{ tag: "wdth", value: 125.0030517578125 }]
	}
	weight.concat(width)
}

fixture : List(U8)
fixture = {
	# GSUB prefers the lower range on wght. GPOS prefers the upper one
	# on wdth. Kerning applies to the nominal A and to either replacement.
	record = |axis, min, max, lookup| { conditions: [{ axis, min, max }], substitutions: [{ feature: 0, lookups: [lookup] }] }
	gsub = FontBuild.layout_varied(
		"latn",
		[{ tag: "calt", lookups: [0] }],
		[1, 3, 4].map(|g| { kind: 1, subtables: [FontBuild.single2([1], [g])] }),
		FontBuild.feature_variations([record(0, 4096, 8192, 1), record(0, 8192, 12288, 2)]),
	)
	pair = |values| {
		sets = [1, 3, 4].map(|g| { glyph: g, pairs: [{ second: 2, values }] })
		{ kind: 2, subtables: [FontBuild.pair1(5, 0, sets)] }
	}
	gpos = FontBuild.layout_varied(
		"latn",
		[{ tag: "kern", lookups: [0] }],
		[[0, 0], [-20, 25], [10, -15]].map(pair),
		FontBuild.feature_variations([record(1, 8192, 12288, 1), record(1, 4096, 8192, 2)]),
	)
	characters = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'a', last: 'b', glyph: 1 }]) }])
	fvar = FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 800 }, { tag: "wdth", min: 50, default: 100, max: 150 }])
	FontBuild.glyphs_font([500, 500, 500, 500, 500], characters, [{ tag: "fvar", data: fvar }, { tag: "GSUB", data: gsub }, { tag: "GPOS", data: gpos }])
}

agrees : Font, Location, Location -> Bool
agrees = |font, weight, width| {
	glyph = match weight {
		Default => 1
		Below | Edge => 3
		Above => 4
	}
	(placement, advance) = match width {
		Default => (0, 500)
		Below => (10, 485)
		Edge | Above => (-20, 525)
	}
	run = Font.shape(font, "ab", Font.ShapeOptions.{})
	Font.coordinates(font) == [{ tag: "wght", value: coordinate(weight) }, { tag: "wdth", value: coordinate(width) }]
		and run.glyphs == [glyph, 2]
		and run.advances == [{ x: advance, y: 0 }, { x: 500, y: 0 }]
		and run.offsets == [{ x: placement, y: 0 }, { x: 0, y: 0 }]
		and run.clusters == [0, 1]
}

machine : Model.Machine(World, Move)
machine = {
	init: { weight: Default, width: Default, font: Font.from_bytes(fixture, Font.ReadOptions.{ strict: True }) },
	actions: |_| settings.join_map(|weight| settings.map(|width| { weight, width })),
	step: |world, move| {
		weight: location(move.weight),
		width: location(move.width),
		font: world.font.map_ok(|font| Font.at(font, Font.Variation.{ axes: axes(move) })),
	},
	rules: [
		Model.always(
			"both layout tables shape at the selected location",
			|world| match world.font {
				Ok(font) => agrees(font, world.weight, world.width)
				Err(_) => False
			},
		),
		Model.sometimes("both tables find two matches at their inclusive endpoint", |w| w.weight == Edge and w.width == Edge),
		Model.sometimes("one unit above the overlap selects the later GSUB record and the earlier GPOS record", |w| w.weight == Above and w.width == Above),
		Model.sometimes("one unit below the overlap selects the earlier GSUB record and the later GPOS record", |w| w.weight == Below and w.width == Below),
		Model.sometimes_step("omitting weight restores its default after both axes moved", |{ before, action, after }| before.weight != Default and before.width != Default and action.weight == Omit and after.width != Default),
		Model.sometimes_step("omitting width restores its default after both axes moved", |{ before, action, after }| before.weight != Default and before.width != Default and action.width == Omit and after.weight != Default),
	],
}

report = |_| Model.explore(
	machine,
	{
		depth: 2,
		key: |world| (world.weight, world.width),
		verify: EveryStep,
	},
)
