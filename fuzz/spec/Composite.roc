import build.FontBuild
import font.Font
import fuzz.Model

# OpenType 1.9.1 gvar, “Point numbers and processing for composite
# glyphs” (https://learn.microsoft.com/en-us/typography/opentype/spec/gvar).
# The adjusted XY offset is scaled when SCALED_COMPONENT_OFFSET is set.
# The last USE_MY_METRICS component supplies its varied phantom points.
Composite := {}.{
	check : {} -> Bool
	check = |_| {
		result = report({})
		(result.verdict, result.states, result.steps, result.depth, result.reached.len()) == (Holds(Exhausted), 64, 448, 5, 5)
	}
}

Components : { b_first : Bool, scaled_offset : Bool, a_metrics : Bool, b_metrics : Bool }

Location : [Below, Default, Half, Peak]

Action : [Reverse, ToggleOffset, ToggleA, ToggleB, At(Location)]

World : { components : Components, location : Location, font : Try(Font, List(Font.Problem)) }

locations : List(Location)
locations = [Below, Default, Half, Peak]

variation : Location -> Font.Variation
variation = |location| {
	weight = match location {
		Below => 200
		Default => 400
		Half => 600
		Peak => 800
	}
	Font.Variation.{ axes: [{ tag: "wght", value: weight }] }
}

rectangle : I64, I64, I64, I64 -> List(U8)
rectangle = |left, bottom, right, top| FontBuild.simple_glyph([
	[
		{ x: left, y: bottom, on: True },
		{ x: right, y: bottom, on: True },
		{ x: right, y: top, on: True },
		{ x: left, y: top, on: True },
	],
])

peak_tuple : List(U64), List(I64), List(I64) -> FontBuild.GvarTuple
peak_tuple = |points, xs, ys| {
	peak: Embedded([16384]),
	between: Peak,
	points: Own(points),
	xs,
	ys,
}

fixture : Components -> List(U8)
fixture = |c| {
	# A is reduced by half in both dimensions. B's XY offset stays fixed.
	# B remains nearest the left and bottom edges at every location.
	more = |more_components| if (more_components) 0x0020 else 0
	metrics = |use_my_metrics| if (use_my_metrics) 0x0200 else 0
	a_flags = 0x000B + more(!c.b_first) + metrics(c.a_metrics) + (if (c.scaled_offset) 0x0800 else 0x1000)
	b_flags = 0x0003 + more(c.b_first) + metrics(c.b_metrics)
	a = [U16(a_flags), U16(1), I16(80), I16(32), U16(8192)]
	b = [U16(b_flags), U16(2), I16(-20), I16(-16)]
	right = if (c.scaled_offset) 46 else 86
	top = if (c.scaled_offset) 20 else 36
	header = [I16(-1), I16(0), I16(0), I16(right), I16(top)]
	composite = FontBuild.pack(header.concat(if (c.b_first) b.concat(a) else a.concat(b)))
	characters = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'A', glyph: 3 }]) }])
	fvar = FontBuild.fvar([{ tag: "wght", min: 200, default: 400, max: 800 }])
	gvar = FontBuild.gvar(
		1,
		[],
		[
			{ shared: None, tuples: [] },
			{ shared: None, tuples: [peak_tuple([4], [6], [0])] },
			{ shared: None, tuples: [peak_tuple([4], [10], [0])] },
			{ shared: None, tuples: [peak_tuple([if (c.b_first) 1 else 0, 2], [12, 16], [-8, 0])] },
		],
		False,
	)
	FontBuild.outline_font(
		[[], rectangle(4, 0, 12, 8), rectangle(20, 16, 40, 28), composite],
		[300, 300, 300, 300],
		[0, 0, 2, -2],
		4,
		False,
		characters,
		[{ tag: "fvar", data: fvar }, { tag: "gvar", data: gvar }],
	)
}

load : Components, Location -> World
load = |components, location| {
	components,
	location,
	font: Font.from_bytes(fixture(components), Font.ReadOptions.{ strict: True }).map_ok(|font| Font.at(font, variation(location))),
}

expected : World -> Font.Extents
expected = |world| {
	c = world.components
	# Half and Peak keep the offset and both phantom deltas integral.
	twice_scalar = match world.location {
		Half => 1
		Peak => 2
		_ => 0
	}
	# At the default location the header and horizontal bearing give
	# the bounds. Other locations use the outline and left phantom.
	shift = if world.location == Default {
		2
	} else if c.a_metrics and (!c.b_metrics or c.b_first) {
		4 + 3 * twice_scalar
	} else if c.b_metrics {
		18 + 5 * twice_scalar
	} else {
		2 + 8 * twice_scalar
	}
	right = if (c.scaled_offset) 46 + 3 * twice_scalar else 86 + 6 * twice_scalar
	top = if (c.scaled_offset) 20 - 2 * twice_scalar else 36 - 4 * twice_scalar
	{ x_min: -shift, y_min: 0, x_max: right - shift, y_max: top }
}

machine : Model.Machine(World, Action)
machine = {
	init: load({ b_first: False, scaled_offset: False, a_metrics: False, b_metrics: False }, Default),
	actions: |world| [Reverse, ToggleOffset, ToggleA, ToggleB].concat(locations.drop_if(|loc| loc == world.location).map(|loc| At(loc))),
	step: |world, action| {
		c = world.components
		match action {
			Reverse => load({ ..c, b_first: !c.b_first }, world.location)
			ToggleOffset => load({ ..c, scaled_offset: !c.scaled_offset }, world.location)
			ToggleA => load({ ..c, a_metrics: !c.a_metrics }, world.location)
			ToggleB => load({ ..c, b_metrics: !c.b_metrics }, world.location)
			At(loc) => { ..world, location: loc, font: world.font.map_ok(|font| Font.at(font, variation(loc))) }
		}
	},
	rules: [
		Model.always(
			"the composite reads and has the expected extents",
			|world| match world.font {
				Ok(font) => Font.extents(font, 3) == Extents(expected(world))
				Err(_) => False
			},
		),
		Model.sometimes("the varied offset scales at half strength", |w| w.components.scaled_offset and w.location == Half),
		Model.sometimes("the varied offset stays unscaled at full strength", |w| !w.components.scaled_offset and w.location == Peak),
		Model.sometimes("B is last and both components supply metrics", |w| !w.components.b_first and w.components.a_metrics and w.components.b_metrics and w.location == Peak),
		Model.sometimes("A is last and both components supply metrics", |w| w.components.b_first and w.components.a_metrics and w.components.b_metrics and w.location == Peak),
		Model.sometimes_step("a varied composite with two donors returns to default", |{ before, action, after }| before.location == Peak and action == At(Default) and after.components.a_metrics and after.components.b_metrics),
	],
}

report = |_| Model.explore(
	machine,
	{
		depth: 6,
		key: |world| (world.components, world.location),
		verify: EveryStep,
	},
)
