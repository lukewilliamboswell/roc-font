import build.FontBuild
import font.Font
import fuzz.Model

# OpenType axis tags are case-sensitive. The registered axes ital and
# slnt are independent, and ITAL is a distinct foundry-defined tag.
# Font.at takes those three values explicitly and gives them no CSS
# font-style default; its named width follows CSS and explicit settings
# override it.
# https://learn.microsoft.com/en-us/typography/opentype/spec/dvaraxisreg
# https://www.w3.org/TR/css-fonts-4/#font-variation-settings-def
CssAxes := {}.{
	check : {} -> Bool
	check = |_| {
		result = Model.explore(machine({}), { depth: 2, key: |world| world.choice, verify: EveryStep })
		result.verdict == Holds(Exhausted) and result.states == 6 and result.reached.len() == 3
	}
}

Choice : [Default, AllStyles, Italic, Custom, OverrideWidth, Limits]

World : { font : Font, choice : Choice }

fixture : {} -> Font
fixture = |_| {
	fvar = FontBuild.fvar([
		{ tag: "ITAL", min: -40, default: 8, max: 40 },
		{ tag: "slnt", min: -20, default: -4, max: 20 },
		{ tag: "ital", min: 0, default: 0, max: 1 },
		{ tag: "wdth", min: 75, default: 100, max: 125 },
	])
	negative = { start: -16384, peak: -16384, end: 0 }
	positive = { start: 0, peak: 16384, end: 16384 }
	neutral = { start: 0, peak: 0, end: 0 }
	axes = [0, 1, 2, 3]
	columns = axes.join_map(|i| [negative, positive].map(|p| axes.map(|j| if (i == j) p else neutral)))
	# A distinct glyph for each axis makes mistaken tag identity
	# observable even when two locations have equal total advance.
	rows = [List.repeat(0, 8)].concat(axes.map(|i| axes.join_map(|j| if (i == j) [-16384, 16384] else [0, 0])))
	store = FontBuild.variation_store(4, columns, [{ regions: [0, 1, 2, 3, 4, 5, 6, 7], rows }])
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'D', glyph: 1 }]) }])
	bytes = FontBuild.glyphs_font([500, 20000, 20000, 20000, 20000], cmap, [{ tag: "fvar", data: fvar }, { tag: "HVAR", data: FontBuild.hvar(store, []) }])
	match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
		Ok(font) => font
		Err(problems) => crash "CSS axes fixture rejected: ${Str.inspect(problems)}"
	}
}

settings : Choice -> Font.Variation
settings = |choice| match choice {
	Default => Font.Variation.{}
	AllStyles => Font.Variation.{ width: SemiCondensed, axes: [{ tag: "ITAL", value: 24 }, { tag: "slnt", value: -12 }, { tag: "ital", value: 0.5 }] }
	Italic => Font.Variation.{ axes: [{ tag: "ital", value: 1 }, { tag: "ITAl", value: -40 }] }
	Custom => Font.Variation.{ axes: [{ tag: "ITAL", value: -16 }] }
	OverrideWidth => Font.Variation.{ width: Expanded, axes: [{ tag: "wdth", value: 75 }, { tag: "ital", value: 0.25 }, { tag: "wdth", value: 112.5 }] }
	Limits => Font.Variation.{ axes: [{ tag: "ITAL", value: -80 }, { tag: "slnt", value: 80 }, { tag: "ital", value: 2 }, { tag: "wdth", value: 20 }] }
}

agrees : World -> Bool
agrees = |world| {
	# Each magnitude is the fraction of that axis's range from its
	# default toward the relevant endpoint, in F2Dot14 units.
	(custom, slant, italic, width) = match world.choice {
		Default => (0, 0, 0, 0)
		AllStyles => (8192, -8192, 8192, -8192)
		Italic => (0, 0, 16384, 0)
		Custom => (-8192, 0, 0, 0)
		OverrideWidth => (0, 0, 4096, 8192)
		Limits => (-16384, 16384, 16384, -16384)
	}
	expected = [
		{ tag: "ITAL", value: custom },
		{ tag: "slnt", value: slant },
		{ tag: "ital", value: italic },
		{ tag: "wdth", value: width },
	]
	Font.coordinates(world.font) == expected
		and [1, 2, 3, 4].map(|g| Font.advance(world.font, g)) == expected.map(|axis| 20000 + axis.value.to_i32())
}

machine : {} -> Model.Machine(World, Choice)
machine = |_| {
	init: { font: fixture({}), choice: Default },
	actions: |_| [Default, AllStyles, Italic, Custom, OverrideWidth, Limits],
	step: |world, choice| { font: Font.at(world.font, settings(choice)), choice },
	rules: [
		Model.always("each requested tag selects its own coordinate and advance", agrees),
		Model.sometimes_step("a lone italic setting resets omitted axes and ignores an unmatched tag", |{ before, after, action: _ }| before.choice == AllStyles and after.choice == Italic),
		Model.sometimes_step("a lone custom setting then drops italic", |{ before, after, action: _ }| before.choice == Italic and after.choice == Custom),
		Model.sometimes_step("the last explicit width wins after leaving the clamped endpoints", |{ before, after, action: _ }| before.choice == Limits and after.choice == OverrideWidth),
	],
}
