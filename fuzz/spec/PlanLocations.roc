import build.FontBuild
import font.Font
import fuzz.Model

# The same prepared face can be moved without rereading its tables.
# At plan time the two FeatureVariations tables choose their lookups.
# At shaping time HVAR and the chosen positioning device use live axes.
PlanLocations := {}.{
	check : {} -> Bool
	check = |_| {
		report = Model.explore(
			machine({}),
			{
				depth: 4,
				key: |world| (world.live, world.planned),
				verify: EveryStep,
			},
		)
		if (report.verdict, report.states, report.steps, report.reached.len()) == (Holds(Exhausted), 9, 45, 3) {
			True
		} else {
			crash "plan location model: ${Str.inspect(report)}"
		}
	}
}

Location : [Default, Half, Peak]

Action : [At(Location), Replan, Reuse]

World : { live : Location, planned : Location, font : Font, plan : Font.ShapePlan }

move : Font, Location -> Font
move = |font, location| {
	weight = match location {
		Default => 400
		Half => 600
		Peak => 800
	}
	Font.at(font, Font.Variation.{ axes: [{ tag: "wght", value: weight }] })
}

fixture : List(U8)
fixture = {
	# One axis selects the substitution at half or above. Positioning
	# chooses a different lookup only from three quarters onward.
	variation = |min| FontBuild.feature_variations([{ conditions: [{ axis: 0, min, max: 16384 }], substitutions: [{ feature: 0, lookups: [1] }] }])
	gsub = FontBuild.layout_varied(
		"latn",
		[{ tag: "calt", lookups: [0] }],
		[1, 3].map(|glyph| { kind: 1, subtables: [FontBuild.single2([1], [glyph])] }),
		variation(8192),
	)
	pair = |value| {
		sets = [1, 3].map(|glyph| { glyph, pairs: [{ second: 2, value, device: Index(0, 0) }] })
		{ kind: 2, subtables: [FontBuild.pair1_devices(0x44, sets)] }
	}
	gpos = FontBuild.layout_varied("latn", [{ tag: "kern", lookups: [0] }], [7, -11].map(pair), variation(12288))
	store = |rows| FontBuild.variation_store(1, [[{ start: 0, peak: 16384, end: 16384 }]], [{ regions: [0], rows }])
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'a', last: 'b', glyph: 1 }]) }])
	FontBuild.glyphs_font(
		[500, 500, 400, 600],
		cmap,
		[
			{ tag: "fvar", data: FontBuild.fvar([{ tag: "wght", min: 200, default: 400, max: 800 }]) },
			{ tag: "GDEF", data: FontBuild.gdef_store(store([[8]])) },
			{ tag: "HVAR", data: FontBuild.hvar(store([[0], [20], [40], [60]]), []) },
			{ tag: "GSUB", data: gsub },
			{ tag: "GPOS", data: gpos },
		],
	)
}

agrees : World -> Bool
agrees = |world| {
	twice_scalar = match world.live {
		Default => 0
		Half => 1
		Peak => 2
	}
	(glyph, nominal) = if (world.planned == Default) (1, 500 + 10 * twice_scalar) else (3, 600 + 30 * twice_scalar)
	right = 400 + 20 * twice_scalar
	pair = (if (world.planned == Peak) -11 else 7) + 4 * twice_scalar
	run = Font.shape_planned(world.font, world.plan, "ab")
	run.glyphs == [glyph, 2] and run.advances == [{ x: nominal + pair, y: 0 }, { x: right, y: 0 }]
		and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }] and run.clusters == [0, 1]
		and Font.advance(world.font, glyph) == nominal
		and Font.width_planned(world.font, world.plan, "ab") == nominal + pair + right
}

machine : {} -> Model.Machine(World, Action)
machine = |_| {
	font = Font.from_bytes(fixture, Font.ReadOptions.{ strict: True }) ?? crash "plan location fixture was rejected"
	{
		init: { live: Default, planned: Default, font, plan: Font.plan(font, Font.ShapeOptions.{}) },
		actions: |_| [At(Default), At(Half), At(Peak), Replan, Reuse],
		step: |world, action| match action {
			At(location) => { ..world, live: location, font: move(world.font, location) }
			Replan => { ..world, planned: world.live, plan: Font.plan(world.font, Font.ShapeOptions.{}) }
			Reuse => world
		},
		rules: [
			Model.always("live metrics and device values use the captured layout", agrees),
			Model.sometimes("a half-location plan selects GSUB without alternate GPOS", |world| world.planned == Half and world.live == Peak),
			Model.sometimes_step("returning to default keeps the peak plan", |{ before, action, after }| before.live == Peak and before.planned == Peak and action == At(Default) and after.planned == Peak),
			Model.sometimes_step("replanning after a move replaces both lookup choices", |{ before, action, after }| before.planned == Default and before.live == Peak and action == Replan and after.planned == Peak),
		],
	}
}
