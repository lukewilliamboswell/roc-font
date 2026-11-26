import build.FontBuild
import font.Font
import fuzz.Model

# OpenType 1.9.1, MVAR value tags and variation data evaluation.
# https://learn.microsoft.com/en-us/typography/opentype/spec/mvar
# A metric uses all contributing regions at the current location.
MetricVariations := {}.{
	check : {} -> Bool
	check = |_| [RequestedTypographic, Header, FallbackTypographic, Windows].all(
		|source| {
			result = Model.explore(machine(source), { depth: 2, key: |world| world.position, verify: EveryStep })
			if result.verdict == Holds(Exhausted) and result.states == 5 and result.reached.len() == 4 {
				True
			} else {
				crash "MVAR metrics ${Str.inspect(source)}: ${Str.inspect(result)}"
			}
		},
	)

	wide_check : {} -> Bool
	wide_check = |_| {
		font = wide_font({})
		pair = |at| {
			metrics = Font.metrics(at)
			(metrics.x_height, metrics.underline.position)
		}
		weight_peak = Font.at(font, location(800, 100))
		both_peaks = Font.at(weight_peak, location(800, 200))
		# At the weight peak, binary32 rounds the base plus a single
		# region to these still-representable values.
		pair(font) == (500, -200)
			and pair(weight_peak) == (1073742336, -1073742080)
			and pair(both_peaks) == (I32.highest, I32.lowest)
			and pair(Font.at(both_peaks, Font.Variation.{})) == (500, -200)
	}
}

Source : [RequestedTypographic, Header, FallbackTypographic, Windows]

Position : [Default, WeightHalf, WidthHalf, BothHalf, Peak]

World : { font : Font, position : Position }

axis_table : List(U8)
axis_table = FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 800 }, { tag: "wdth", min: 50, default: 100, max: 200 }])

# A zero peak leaves that axis out of the region scalar.
neutral : { start : I64, peak : I64, end : I64 }
neutral = { start: 0, peak: 0, end: 0 }

ramp : { start : I64, peak : I64, end : I64 }
ramp = { start: 0, peak: 16384, end: 16384 }

read : List({ tag : Str, data : List(U8) }) -> Font
read = |tables| match Font.from_bytes(FontBuild.file(tables), Font.ReadOptions.{ strict: True }) {
	Ok(font) => font
	Err(problems) => crash "valid MVAR font rejected: ${Str.inspect(problems)}"
}

location : Dec, Dec -> Font.Variation
location = |w, d| Font.Variation.{ axes: [{ tag: "wght", value: w }, { tag: "wdth", value: d }] }

variation : Position -> Font.Variation
variation = |position| match position {
	Default => Font.Variation.{}
	WeightHalf => Font.Variation.{ axes: [{ tag: "wght", value: 600 }] }
	WidthHalf => Font.Variation.{ axes: [{ tag: "wdth", value: 150 }] }
	BothHalf => location(600, 150)
	Peak => location(800, 200)
}

fixture : Source -> Font
fixture = |source| {
	(typo_ascent, typo_descent) = if (source == Windows) (0, 0) else (900, -300)
	(header_ascent, header_descent) = if (source == RequestedTypographic or source == Header) (800, -200) else (0, 0)
	os2 = FontBuild.os2({ use_typo: source == RequestedTypographic, typo_ascent, typo_descent, win_ascent: 1000, win_descent: 400 })
	header = FontBuild.patch(FontBuild.hhea(header_ascent, header_descent, 4), 8, FontBuild.i16(30))
	base = FontBuild.basic.map(|table| if (table.tag == "hhea") { tag: "hhea", data: header } else table)
	store = FontBuild.variation_store(
		2,
		[[ramp, neutral], [neutral, ramp], [ramp, ramp]],
		[{ regions: [0, 1, 2], rows: [[1, 3, -6], [-2, -3, 4], [2, -1, -2], [-1, -3, 6], [3, -1, 6]] }],
	)
	mvar = FontBuild.mvar(store, ["hasc", "hcla", "hcld", "hdsc", "hlgp"].map_with_index(|tag, inner| { tag, outer: 0, inner }))
	read(base.concat([{ tag: "fvar", data: axis_table }, { tag: "MVAR", data: mvar }, { tag: "OS/2", data: FontBuild.patch(os2, 72, FontBuild.i16(60)) }]))
}

agrees : Source, World -> Bool
agrees = |source, world| {
	# Coordinates are half-steps. The region scalars W, D and W*D
	# therefore share a denominator of four. Round the full sum once
	# toward positive infinity at a tie, then convert the descent sign.
	(w, d) = match world.position {
		Default => (0, 0)
		WeightHalf => (1, 0)
		WidthHalf => (0, 1)
		BothHalf => (1, 1)
		Peak => (2, 2)
	}
	rounded : I32, I32, I32, I32 -> I32
	rounded = |base, a, b, c| {
		numerator = 4 * base + 2 * w * a + 2 * d * b + w * d * c + 2
		if (numerator >= 0) numerator // 4 else -((3 - numerator) // 4)
	}
	(ascent, descent, gap) = match source {
		RequestedTypographic | FallbackTypographic => (rounded(900, 1, 3, -6), -rounded(-300, -1, -3, 6), rounded(60, 3, -1, 6))
		Header => (rounded(800, 1, 3, -6), -rounded(-200, -1, -3, 6), rounded(30, 3, -1, 6))
		Windows => (rounded(1000, -2, -3, 4), rounded(400, 2, -1, -2), 0)
	}
	metrics = Font.metrics(world.font)
	(metrics.ascent, metrics.descent, metrics.line_gap) == (ascent, descent, gap)
}

machine : Source -> Model.Machine(World, Position)
machine = |source| {
	init: { font: fixture(source), position: Default },
	actions: |_| [Default, WeightHalf, WidthHalf, BothHalf, Peak],
	step: |world, position| { font: Font.at(world.font, variation(position)), position },
	rules: [
		Model.always("vertical metrics follow the selected base and sum the active regions before rounding", |world| agrees(source, world)),
		Model.sometimes("both axes are halfway to their peaks", |world| world.position == BothHalf),
		Model.sometimes_step("a variation with no axes restores the defaults", |{ before, action, after: _ }| before.position == Peak and action == Default),
		Model.sometimes_step("omitting width clears its region contributions", |{ before, action, after: _ }| before.position == BothHalf and action == WeightHalf),
		Model.sometimes_step("omitting weight clears its region contributions", |{ before, action, after: _ }| before.position == BothHalf and action == WidthHalf),
	],
}

wide_font : {} -> Font
wide_font = |_| {
	# Each row's two regions reach full strength together at (800, 200).
	store = FontBuild.variation_store_long(2, [[ramp, neutral], [neutral, ramp]], [[-1073741824, -1073741824], [1073741824, 1073741824]])
	mvar = FontBuild.mvar(store, [{ tag: "undo", outer: 0, inner: 0 }, { tag: "xhgt", outer: 0, inner: 1 }])
	# OS/2 version 2 stores x-height, and post version 3 stores the
	# underline position without containing any glyph names.
	os2 = FontBuild.os2({ use_typo: False, typo_ascent: 800, typo_descent: -200, win_ascent: 900, win_descent: 300 }).concat(List.repeat(0, 18))
	heights = FontBuild.patch(FontBuild.patch(os2, 0, FontBuild.u16(2)), 86, FontBuild.u16(500))
	post = FontBuild.pack([U32(0x00030000), U32(0), I16(-200), I16(20), Raw(List.repeat(0, 20))])
	read(FontBuild.basic.concat([{ tag: "fvar", data: axis_table }, { tag: "MVAR", data: mvar }, { tag: "OS/2", data: heights }, { tag: "post", data: post }]))
}
