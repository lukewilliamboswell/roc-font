import build.FontBuild
import build.MarkBuild
import font.Font
import fuzz.Model

# OpenType GPOS anchor format 3. Each VariationIndex adjusts its own
# anchor coordinate before the mark is moved from its pen to the base.
VariedAnchors := {}.{
	check : {} -> Bool
	check = |_| [VariableLast, StaticLast].all(check_order) and invalid_reference(fixture(StaticLast, True))
}

Order : [VariableLast, StaticLast]

Place : [Home, HalfWeight, HalfWidth, BothHalf, Peak]

World : { font : Font, place : Place, static_enabled : Bool }

Action : [Move(Place), Toggle]

check_order : Order -> Bool
check_order = |order| {
	font = Font.from_bytes(fixture(order, False), Font.ReadOptions.{ strict: True }) ?? crash "variable mark fixture rejected"
	machine : Model.Machine(World, Action)
	machine = {
		init: { font, place: Home, static_enabled: False },
		actions: |_| [Move(Home), Move(HalfWeight), Move(HalfWidth), Move(BothHalf), Move(Peak), Toggle],
		step: |world, action| match action {
			Move(place) => { ..world, place, font: Font.at(world.font, variation(place)) }
			Toggle => { ..world, static_enabled: !world.static_enabled }
		},
		rules: [
			Model.always("the final writer moves the mark from its pen using its independently varied anchors", |world| agrees(order, world)),
			Model.sometimes_step("moving from both half axes to one resets the omitted coordinate", |{ before, action, after: _ }| before.place == BothHalf and action == Move(HalfWeight)),
			Model.sometimes_step("restoring defaults with both writers enabled resets anchor deltas", |{ before, action, after: _ }| before.static_enabled and before.place == Peak and action == Move(Home)),
		],
	}
	result = Model.explore(machine, { depth: 3, key: |world| (world.place, world.static_enabled), verify: EveryStep })
	if result.verdict == Holds(Exhausted) and result.states == 10 and result.reached.len() == 2 {
		True
	} else {
		crash "mark writers ${Str.inspect(order)}: ${Str.inspect(result)}"
	}
}

variation : Place -> Font.Variation
variation = |place| match place {
	Home => Font.Variation.{}
	HalfWeight => Font.Variation.{ axes: [{ tag: "wght", value: 600 }] }
	HalfWidth => Font.Variation.{ axes: [{ tag: "wdth", value: 150 }] }
	BothHalf => Font.Variation.{ axes: [{ tag: "wght", value: 600 }, { tag: "wdth", value: 150 }] }
	Peak => Font.Variation.{ axes: [{ tag: "wght", value: 800 }, { tag: "wdth", value: 200 }] }
}

# An equivalent font built with fontTools gives these mark offsets in
# HarfBuzz 14.6.0 at 1000 units per em: default (-597, -20), half weight
# (-597, -21), half width (-598, -18), both half (-598, -19), and both
# peaks (-599, -18). Device rounding uses a tie toward positive infinity.
varied_offset : Place -> { x : I32, y : I32 }
varied_offset = |place| {
	(w, d) = match place {
		Home => (0, 0)
		HalfWeight => (1, 0)
		HalfWidth => (0, 1)
		BothHalf => (1, 1)
		Peak => (2, 2)
	}
	round_half : I32 -> I32
	round_half = |n| if (n >= 0) (n + 1) // 2 else -((0 - n) // 2)
	x = 12 - (-3) + round_half(2 * w - d) - round_half(w + 2 * d) - 612
	y = -14 - 6 + round_half(d - 2 * w) - round_half(-w - 2 * d)
	{ x, y }
}

observe : Font, Bool -> Font.Run
observe = |font, static_enabled| {
	features = if (static_enabled) [Font.Feature.{ tag: "tst2", value: 1 }] else []
	Font.shape(font, "AB", Font.ShapeOptions.{ script: "Latn", features })
}

agrees : Order, World -> Bool
agrees = |order, world| {
	run = observe(world.font, world.static_enabled)
	offset = if (world.static_enabled and order == StaticLast) { x: -632, y: 93 } else varied_offset(world.place)
	if run.glyphs == [1, 2] and run.clusters == [0, 1] and run.advances == [{ x: 612, y: 0 }, { x: 0, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, offset] {
		True
	} else {
		crash "mark ${Str.inspect(world.place)} static writer enabled ${Str.inspect(world.static_enabled)}: ${Str.inspect(run)} expected ${Str.inspect(offset)}"
	}
}

fixture : Order, Bool -> List(U8)
fixture = |order, invalid| {
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'B', glyph: 1 }]) }])
	fvar = FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 800 }, { tag: "wdth", min: 50, default: 100, max: 200 }])
	ramp = { start: 0, peak: 16384, end: 16384 }
	neutral = { start: 0, peak: 0, end: 0 }
	store = FontBuild.variation_store(2, [[ramp, neutral], [neutral, ramp]], [{ regions: [0, 1], rows: [[2, -1], [-2, 1], [1, 2], [-1, -2]] }])
	classes = FontBuild.classes2([{ first: 1, last: 1, class: 1 }, { first: 2, last: 2, class: 3 }])
	gdef = FontBuild.pack([U32(0x00010003), Ref(classes), U16(0), U16(0), U16(0), U16(0), Ref32(store)])
	index = |inner| FontBuild.pack([U16(0), U16(inner), U16(0x8000)])
	lookup = |base, mark| MarkBuild.Lookup.{ kind: 4, subtables: [MarkBuild.position([{ glyph: 2, class: 0, anchor: mark }], 1, [{ glyph: 1, anchors: [base] }])] }
	varied = lookup(MarkBuild.device_anchor(12, -14, index(0), index(1)), MarkBuild.device_anchor(-3, 6, index(2), index(if (invalid) 4 else 3)))
	static = lookup(MarkBuild.anchor(-15, 73), MarkBuild.anchor(5, -20))
	features = [{ tag: "mark", lookups: [if (order == StaticLast) 0 else 1] }, { tag: "tst2", lookups: [if (order == StaticLast) 1 else 0] }]
	gpos = MarkBuild.layout("latn", features, if (order == StaticLast) [varied, static] else [static, varied])
	FontBuild.glyphs_font([500, 612, 0], cmap, [{ tag: "fvar", data: fvar }, { tag: "GDEF", data: gdef }, { tag: "GPOS", data: gpos }])
}

invalid_reference : List(U8) -> Bool
invalid_reference = |bytes| {
	font = Font.from_bytes(bytes, Font.ReadOptions.{}) ?? crash "lenient invalid anchor index rejected"
	problems = Font.dropped(font)
	strict = match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
		Err(found) => found == problems
		Ok(_) => False
	}
	at = Font.at(font, variation(Peak))
	match problems {
		[BadTable({ table: "GPOS", offset })] =>
			strict and bytes.sublist({ start: offset.to_u64(), len: 6 }) == [0, 0, 0, 4, 0x80, 0]
				and Font.axes(at).is_empty() and observe(at, False).offsets == [{ x: 0, y: 0 }, varied_offset(Home)]
		_ => crash "invalid anchor index diagnostics: ${Str.inspect(problems)}"
	}
}
