import build.FontBuild
import font.Font
import fuzz.Model

# OpenType 1.9.1 gvar, "Processing inferred deltas for un-referenced
# point numbers": use the two nearest touched points in contour order,
# wrapping at the end. A lone anchor moves its contour. Equal anchor
# coordinates with unequal deltas give an untouched point zero on
# that axis. Infer within each tuple, then scale and add.
# https://learn.microsoft.com/en-us/typography/opentype/spec/gvar
Outlines := {}.{
	check : {} -> Bool
	check = |_| {
		result = report({})
		(result.verdict, result.states, result.steps, result.depth, result.reached.len()) == (Holds(Exhausted), 124, 492, 3, 5)
	}
}

Patch : [SingleAnchor, EqualDeltas, UnequalDeltas, Wrap, OtherContour]

Location : [Below, Default, Half, Peak]

Action : [Add(Patch), At(Location)]

World : { patches : List(Patch), location : Location, font : Try(Font, List(Font.Problem)) }

patches : List(Patch)
patches = [SingleAnchor, EqualDeltas, UnequalDeltas, Wrap, OtherContour]

locations : List(Location)
locations = [Below, Default, Half, Peak]

contours : List(List({ x : I64, y : I64 }))
contours = [
	[{ x: 32, y: 0 }, { x: 0, y: 32 }, { x: 64, y: 64 }, { x: 0, y: 96 }, { x: 128, y: 160 }],
	[{ x: 16, y: 200 }, { x: 32, y: 200 }, { x: 16, y: 220 }],
]

variation : Location -> Font.Variation
variation = |location| {
	weight = match location {
		Below => 100
		Default => 400
		Half => 600
		Peak => 800
	}
	Font.Variation.{ axes: [{ tag: "wght", value: weight }] }
}

tuple : Patch, U64 -> FontBuild.GvarTuple
tuple = |patch, index| {
	selection = match patch {
		SingleAnchor => { points: [2], xs: [16], ys: [-20] }
		EqualDeltas => { points: [1, 3], xs: [8, 8], ys: [0, 0] }
		UnequalDeltas => { points: [1, 3], xs: [8, 24], ys: [0, 0] }
		Wrap => { points: [1, 4], xs: [0, 0], ys: [-16, 16] }
		OtherContour => { points: [6], xs: [4], ys: [12] }
	}
	{
		peak: Embedded(if (index == 0) [16384] else [8192]),
		between: if (index == 0) Peak else Range([0], [16384]),
		points: Own(selection.points),
		xs: selection.xs,
		ys: selection.ys,
	}
}

fixture : List(Patch) -> List(U8)
fixture = |applied| {
	glyph = FontBuild.simple_glyph(contours.map(|c| c.map(|p| { x: p.x, y: p.y, on: True })))
	characters = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'A', glyph: 1 }]) }])
	fvar = FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 800 }])
	gvar = FontBuild.gvar(1, [], [{ shared: None, tuples: [] }, { shared: None, tuples: applied.map_with_index(tuple) }], False)
	# xMin and the left side bearing both start at zero. No tuple
	# explicitly moves a phantom point.
	FontBuild.outline_font([[], glyph], [300, 300], [0, 0], 2, False, characters, [{ tag: "fvar", data: fvar }, { tag: "gvar", data: gvar }])
}

load : List(Patch), Location -> World
load = |applied, location| {
	patches: applied,
	location,
	font: Font.from_bytes(fixture(applied), Font.ReadOptions.{ strict: True }).map_ok(|font| Font.at(font, variation(location))),
}

# Hand-derived point deltas for the chosen geometry. The wrap makes p0
# take the lower y anchor's delta past the end of the contour. In the
# other direction p2 and p3 are a quarter and half of the way from p1
# to p4, respectively. The second contour has three points after these.
deltas : Patch -> List((I64, I64))
deltas = |patch| match patch {
	SingleAnchor => List.repeat((16, -20), 5).concat(List.repeat((0, 0), 3))
	EqualDeltas => List.repeat((8, 0), 5).concat(List.repeat((0, 0), 3))
	UnequalDeltas => [(0, 0), (8, 0), (0, 0), (24, 0), (0, 0), (0, 0), (0, 0), (0, 0)]
	Wrap => [(0, -16), (0, -16), (0, -8), (0, 0), (0, 16), (0, 0), (0, 0), (0, 0)]
	OtherContour => List.repeat((0, 0), 5).concat(List.repeat((4, 12), 3))
}

# The first tuple is at full strength at Peak and half at Half. The
# second, whose explicit region ends at Peak, is at full strength only
# at Half. All relevant terms here are even.
twice_scalar : Location, U64 -> I64
twice_scalar = |location, index| match (location, index) {
	(Peak, 0) | (Half, 1) => 2
	(Half, 0) => 1
	_ => 0
}

box : World -> Font.Extents
box = |world| {
	base = contours.join_map(|c| c)
	moved = world.patches.map_with_index(|p, i| { changes: deltas(p), scale: twice_scalar(world.location, i) }).fold(
		base,
		|points, t| {
			points.map2(t.changes, |p, (dx, dy)| { x: p.x + (dx * t.scale) // 2, y: p.y + (dy * t.scale) // 2 })
		},
	)
	start = moved.first() ?? { x: 0, y: 0 }
	moved.fold(
		{ x_min: start.x.to_i32_wrap(), y_min: start.y.to_i32_wrap(), x_max: start.x.to_i32_wrap(), y_max: start.y.to_i32_wrap() },
		|bounds, p| {
			x_min: bounds.x_min.min(p.x.to_i32_wrap()),
			y_min: bounds.y_min.min(p.y.to_i32_wrap()),
			x_max: bounds.x_max.max(p.x.to_i32_wrap()),
			y_max: bounds.y_max.max(p.y.to_i32_wrap()),
		},
	)
}

machine : Model.Machine(World, Action)
machine = {
	init: load([], Default),
	actions: |world| {
		queries = locations.drop_if(|loc| loc == world.location).map(|loc| At(loc))
		if (world.patches.len() < 2) queries.concat(patches.map(|p| Add(p))) else queries
	},
	step: |world, action| match action {
		Add(p) => load(world.patches.append(p), world.location)
		At(location) => { ..world, location, font: world.font.map_ok(|font| Font.at(font, variation(location))) }
	},
	rules: [
		Model.always("each outline and its tuples read strictly", |world| world.font.is_ok()),
		Model.always(
			"the tuple geometry agrees with the observed ink box",
			|world| match world.font {
				Ok(font) => Font.extents(font, 1) == Extents(box(world))
				Err(_) => True
			},
		),
		Model.sometimes("one touched point moves its own contour at a half scalar", |w| w.patches == [SingleAnchor] and w.location == Half),
		Model.sometimes("the widest untouched point lies between equal-coordinate unequal-delta anchors", |w| w.patches == [UnequalDeltas] and w.location == Peak),
		Model.sometimes("the lowest untouched point takes a delta across the contour start", |w| w.patches == [Wrap] and w.location == Peak),
		Model.sometimes("two tuples contribute at the same location", |w| w.patches == [SingleAnchor, OtherContour] and w.location == Half),
		Model.sometimes_step("a previously varied outline returns to default", |{ before, action, after }| before.location == Peak and action == At(Default) and !after.patches.is_empty()),
	],
}

report = |_| Model.explore(
	machine,
	{
		depth: 4,
		# Tuple order determines the region of each patch. EveryStep also
		# observes locations reached by a different series of At actions.
		key: |world| (world.patches, world.location),
		verify: EveryStep,
	},
)
