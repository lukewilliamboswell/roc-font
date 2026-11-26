import build.FontBuild
import font.Font
import fuzz.Model

# OpenType 1.9.1, avar version 1 and coordinate normalization.
# https://learn.microsoft.com/en-us/typography/opentype/spec/avar
# Both axes have their own segment map. Two advances expose their mapped
# coordinates even when a movement resets just one of the axes.
AxisMapping := {}.{
	check : {} -> Bool
	check = |_| {
		result = Model.explore(machine, { depth: 2, key: |world| world.position, verify: EveryStep })
		if result.verdict == Holds(Exhausted) and result.states == 7 and result.reached.len() == 3 {
			True
		} else {
			crash "axis mapping model: ${Str.inspect(result)}"
		}
	}
}

Position : [BrowserDefault, FontDefault, BothBent, WeightOnly, OpticalOnly, Knots, Limits]

World : { font : Font, position : Position }

fixture : Font
fixture = {
	fvar = FontBuild.fvar([{ tag: "wght", min: 192, default: 448, max: 960 }, { tag: "opsz", min: 8, default: 16, max: 32 }])
	map = |negative, positive| [
		{ from: -16384, to: -16384 },
		{ from: -8192, to: negative },
		{ from: 0, to: 0 },
		{ from: 8192, to: positive },
		{ from: 16384, to: 16384 },
	]
	avar = FontBuild.avar([map(-8191, 8193), map(-12288, 4096)])
	negative = { start: -16384, peak: -16384, end: 0 }
	positive = { start: 0, peak: 16384, end: 16384 }
	neutral = { start: 0, peak: 0, end: 0 }
	# Each nonzero peak has a delta of the same signed size, so each
	# glyph's advance changes by exactly one of the mapped coordinates.
	store = FontBuild.variation_store(
		2,
		[[negative, neutral], [positive, neutral], [neutral, negative], [neutral, positive]],
		[{ regions: [0, 1, 2, 3], rows: [[0, 0, 0, 0], [-16384, 16384, 0, 0], [0, 0, -16384, 16384]] }],
	)
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'B', glyph: 1 }]) }])
	bytes = FontBuild.glyphs_font([500, 20000, 20000], cmap, [{ tag: "fvar", data: fvar }, { tag: "avar", data: avar }, { tag: "HVAR", data: FontBuild.hvar(store, []) }])
	match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
		Ok(font) => font
		Err(problems) => crash "valid axis maps rejected: ${Str.inspect(problems)}"
	}
}

settings : Position -> Font.Variation
settings = |position| match position {
	BrowserDefault => Font.Variation.{}
	FontDefault => Font.Variation.{ axes: [{ tag: "wght", value: 448 }, { tag: "opsz", value: 16 }] }
	BothBent => Font.Variation.{ weight: Weight(544), optical_size: Size(14) }
	WeightOnly => Font.Variation.{ weight: Weight(544) }
	OpticalOnly => Font.Variation.{ axes: [{ tag: "opsz", value: 20 }] }
	Knots => Font.Variation.{ axes: [{ tag: "wght", value: 320 }, { tag: "opsz", value: 24 }] }
	Limits => Font.Variation.{ axes: [{ tag: "wght", value: 100 }, { tag: "opsz", value: 100 }] }
}

agrees : World -> Bool
agrees = |world| {
	# CSS Regular and weight 544 normalize to -3/16 and +3/16.
	# Each is 3/8 of the distance to its map knot, giving -3071.625
	# and 3072.375 in F2Dot14 units. The first rounding, to 16.16,
	# puts both on a half-unit tie. HarfBuzz rounds that tie up.
	(w, o) = match world.position {
		BrowserDefault => (-3071, 0)
		FontDefault => (0, 0)
		BothBent => (3073, -6144)
		WeightOnly => (3073, 0)
		OpticalOnly => (-3071, 2048)
		Knots => (-8191, 4096)
		Limits => (-16384, 16384)
	}
	Font.coordinates(world.font) == [{ tag: "wght", value: w }, { tag: "opsz", value: o }]
		and Font.advance(world.font, 1) == 20000 + w.to_i32()
		and Font.advance(world.font, 2) == 20000 + o.to_i32()
}

machine : Model.Machine(World, Position)
machine = {
	init: { font: fixture, position: BrowserDefault },
	actions: |_| [BrowserDefault, FontDefault, BothBent, WeightOnly, OpticalOnly, Knots, Limits],
	step: |world, position| { font: Font.at(world.font, settings(position)), position },
	rules: [
		Model.always("each axis map supplies its own signed advance contribution", agrees),
		Model.sometimes_step("omitting optical size restores the font's declared optical size", |{ before, action, after: _ }| before.position == BothBent and action == WeightOnly),
		Model.sometimes_step("omitting weight restores CSS Regular on a font with a different declared weight", |{ before, action, after: _ }| before.position == BothBent and action == OpticalOnly),
		Model.sometimes_step("a move from the clamped limits can select the font's own default design", |{ before, action, after: _ }| before.position == Limits and action == FontDefault),
	],
}
