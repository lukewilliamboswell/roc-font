import build.FontBuild
import font.Font
import fuzz.Model

# OpenType 1.9.1 MathKern tables. Each correction height separates two
# value slots. The two corners' heights may pass each other, but heights
# within each corner stay ordered and can meet as the font varies.
# https://learn.microsoft.com/en-us/typography/opentype/spec/math#mathkern-table
MathLocations := {}.{
	check : {} -> Bool
	check = |_| {
		result = Model.explore(machine, { depth: 2, key: |world| world.location, verify: EveryStep })
		if result.verdict == Holds(Exhausted) and result.states == 5 and result.reached.len() == 3 {
			True
		} else {
			crash "MATH corner location model ${Str.inspect(result)}"
		}
	}
}

Location : [Home, Weight, Width, Both, Half]

World : { font : Font, location : Location }

math_kern : List(I64), List(I64), U64 -> List(U8)
math_kern = |heights, values, first_row| {
	records = heights.concat(values).map_with_index(|value, index| [I16(value), FontBuild.device_field(Index(0, first_row + index))])
	FontBuild.pack([U16(heights.len())].concat(records.join_map(|record| record)))
}

fixture : Font
fixture = {
	top = math_kern([-40, 0, 40], [-30, 11, 23, 37], 0)
	bottom = math_kern([-60, -20, 20], [-50, -14, 7, 40], 7)
	corners = FontBuild.pack([Ref(FontBuild.coverage1([1])), U16(1), Ref(top), U16(0), U16(0), Ref(bottom)])
	info = FontBuild.pack([U16(0), U16(0), U16(0), Ref(corners)])
	math = FontBuild.pack([U16(1), U16(0), Ref(List.repeat(0, 214)), Ref(info), Ref(List.repeat(0, 10))])
	ramp = { start: 0, peak: 16384, end: 16384 }
	neutral = { start: 0, peak: 0, end: 0 }
	rows = [[60, 0], [20, 0], [-20, 0], [8, -4], [0, 2], [-6, 10], [12, 0], [0, 20], [0, -20], [0, -60], [4, 6], [-8, 0], [0, 8], [-12, 4]]
	store = FontBuild.variation_store(2, [[ramp, neutral], [neutral, ramp]], [{ regions: [0, 1], rows }])
	fvar = FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 900 }, { tag: "wdth", min: 50, default: 100, max: 200 }])
	bytes = FontBuild.parity_font([{ tag: "MATH", data: math }, { tag: "GDEF", data: FontBuild.gdef_store(store) }, { tag: "fvar", data: fvar }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "valid variable MATH corners did not read strictly"
}

settings : Location -> Font.Variation
settings = |location| match location {
	Home => Font.Variation.{}
	Weight => Font.Variation.{ weight: Black }
	Width => Font.Variation.{ width: UltraExpanded }
	Both => Font.Variation.{ weight: Black, width: UltraExpanded }
	Half => Font.Variation.{ weight: Weight(650), width: ExtraExpanded }
}

corner_agrees : Font, Font.MathCorner, Font.MathKernTable -> Bool
corner_agrees = |font, corner, expected| {
	probes = expected.heights.join_map(|height| [height - 1, height, height + 1])
	Font.math_kern_table(font, 1, corner) == expected
		and probes.all(
			|height| {
				# With a three-way tie HarfBuzz visits the middle threshold
				# first. Otherwise the count gives the ordered range slot.
				count = expected.heights.keep_if(|threshold| threshold <= height).len()
				slot = if (expected.heights == [height, height, height]) 2 else count
				value = expected.values.get(slot) ?? crash "expected corner slot is present"
				Font.math_kern(font, 1, corner, height) == value
			},
		)
}

agrees : World -> Bool
agrees = |world| {
	# w and d count half-steps. Both independent region scalars are exact.
	(w, d) = match world.location {
		Home => (0, 0)
		Weight => (2, 0)
		Width => (0, 2)
		Both => (2, 2)
		Half => (1, 1)
	}
	top = { heights: [-40 + 30 * w, 10 * w, 40 - 10 * w], values: [-30 + 4 * w - 2 * d, 11 + d, 23 - 3 * w + 5 * d, 37 + 6 * w] }
	bottom = { heights: [-60 + 10 * d, -20 - 10 * d, 20 - 30 * d], values: [-50 + 2 * w + 3 * d, -14 - 4 * w, 7 + 4 * d, 40 - 6 * w + 2 * d] }
	corner_agrees(world.font, TopRight, top) and corner_agrees(world.font, BottomLeft, bottom)
}

machine : Model.Machine(World, Location)
machine = {
	init: { font: fixture, location: Home },
	actions: |_| [Home, Weight, Width, Both, Half],
	step: |world, location| { font: Font.at(world.font, settings(location)), location },
	rules: [
		Model.always("each corner retains its height and value slots at the selected location", agrees),
		Model.sometimes_step("omitting width breaks the bottom-left tie", |{ before, action, after: _ }| before.location == Both and action == Weight),
		Model.sometimes_step("omitting weight breaks the top-right tie", |{ before, action, after: _ }| before.location == Both and action == Width),
		Model.sometimes_step("the default location restores both sets of distinct heights", |{ before, action, after: _ }| before.location == Both and action == Home),
	],
}
