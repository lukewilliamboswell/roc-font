app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import fuzz.Fuzz
import font.Font
import build.FontBuild

## Variable fonts: axes (`fvar`), axis maps (`avar`), advance variations
## (`HVAR`) and metric variations (`MVAR`), and measuring at fuzzed
## locations. The first input byte picks the shape of the font: 1 to 4
## axes (bits 0 and 1), 2 to 5 regions (bits 2 and 3), `OS/2` typographic
## metrics (bit 4), a delta-set index map in `HVAR` (bit 5), and axis maps
## and regions taken raw from the input, which may be invalid (bit 6). The next 48
## bytes choose the axes (tags, which may repeat, and ranges), the axis
## maps, the regions, the deltas and which metrics vary; the rest chooses
## up to eight locations (named weights and widths, optical sizes and axis
## values, small, huge, fractional or for tags the font lacks). The same
## choices build a font at two sizes: 32 and 256 glyphs, and 8 times the
## regions, which only the extra glyphs use.
##
## Contract: both fonts read leniently, and in full (nothing dropped, the
## axes as built) unless the maps and regions were raw; `at` and every query on
## its result are total and deterministic; advances are finite and never
## negative, and the default location (every axis at its default) gives the
## `hmtx` advances; every glyph and metric of the smaller font measures the
## same in the larger at every location. Reading the larger font takes at
## most `10 × small + 256` allocations (linear); `at` and advance lookups
## cost no more allocations in the larger font (constant per query); nothing
## leaks.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = bytes.first() ?? 0
	picks = bytes.drop_first(1).take_first(48)
	places = locations(bytes.drop_first(49))
	small = recipe(choice, picks, 1)
	large = recipe(choice, picks, 8)
	small_font = check!(small, places)
	large_font = check!(large, places)
	for place in places {
		a = Font.at(small_font, place)
		b = Font.at(large_font, place)
		if Str.inspect(Font.metrics(a)) != Str.inspect(Font.metrics(b)) {
			crash "metric variations differ between the fonts at ${Str.inspect(place)}"
		}
		for g in 0..<small.glyphs {
			if Font.advance(a, g.to_u32_wrap()) != Font.advance(b, g.to_u32_wrap()) {
				crash "glyph ${g.to_str()} advances ${Font.advance(a, g.to_u32_wrap()).to_str()} in the smaller font and ${Font.advance(b, g.to_u32_wrap()).to_str()} in the larger at ${Str.inspect(place)}"
			}
		}
	}
	small_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(small.file, Font.ReadOptions.{}))
	large_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(large.file, Font.ReadOptions.{}))
	Fuzz.expect_no_leaks!(|{}| Font.from_bytes(large.file, Font.ReadOptions.{}))
	if large_read.allocations > 10 * small_read.allocations + 256 {
		crash "reading a variable font 8 times larger took ${large_read.allocations.to_str()} allocations, against ${small_read.allocations.to_str()}"
	}
	place = places.first() ?? Font.Variation.{ weight: Bold }
	small_at = Fuzz.measure_allocs!(|{}| Font.at(small_font, place))
	large_at = Fuzz.measure_allocs!(|{}| Font.at(large_font, place))
	Fuzz.expect_no_leaks!(|{}| Font.at(large_font, place))
	if large_at.allocations > small_at.allocations + 4 {
		crash "moving a font with 8 times the regions took ${large_at.allocations.to_str()} allocations, against ${small_at.allocations.to_str()}"
	}
	small_query = Fuzz.measure_allocs!(|{}| advances(small_at.value, small.glyphs))
	large_query = Fuzz.measure_allocs!(|{}| advances(large_at.value, small.glyphs))
	Fuzz.expect_no_leaks!(|{}| advances(large_at.value, small.glyphs))
	if large_query.allocations > small_query.allocations + 4 {
		crash "looking up ${small.glyphs.to_str()} advances took ${large_query.allocations.to_str()} allocations in a font 8 times larger, against ${small_query.allocations.to_str()}"
	}
	Fuzz.keep
}

## The font a recipe builds: its file, glyph count, axes, and whether its
## axis maps and regions were taken raw (and may be invalid).
Built : { file : List(U8), glyphs : U64, axes : List({ tag : Str, min : I64, default : I64, max : I64 }), raw : Bool }

pick : List(U8), U64 -> U64
pick = |bytes, i| if (bytes.is_empty()) 0 else (bytes.get(i % bytes.len()) ?? 0).to_u64()

## A signed value from a byte, -128 to 127.
signed : U64 -> I64
signed = |b| b.to_i64_wrap() - 128

tags : List(Str)
tags = ["wght", "wdth", "opsz", "slnt", "GRAD", "ital", "XOPQ", "wght"]

## The metrics `MVAR` can vary, in increasing tag order.
metric_tags : List(Str)
metric_tags = ["cpht", "hasc", "hcla", "hcld", "hdsc", "hlgp", "stro", "strs", "undo", "unds", "xhgt"]

recipe : U8, List(U8), U64 -> Built
recipe = |choice, picks, copies| {
	axis_count = 1 + choice.to_u64() % 4
	own = 2 + choice.shr_zf_wrap(2).to_u64() % 4
	region_count = own * copies
	glyphs = 32 * copies
	raw = choice.bitwise_and(0x40) != 0
	axes = FontBuild.counting(axis_count).map(
		|a| {
			default = signed(pick(picks, 3 * a)) * 4 + 400
			{ tag: tags.get(pick(picks, 3 * a) % 8) ?? "wght", min: default - pick(picks, 3 * a + 1).to_i64_wrap() * 2, default, max: default + pick(picks, 3 * a + 2).to_i64_wrap() * 3 }
		},
	)
	maps = FontBuild.counting(axis_count).map(
		|a| {
			b = pick(picks, 12 + a)
			c = pick(picks, 16 + a)
			if raw {
				[{ from: signed(b) * 128, to: signed(c) * 128 }, { from: 0, to: 0 }, { from: signed(c) * 256, to: signed(b) * 64 }]
			} else if b % 3 == 0 {
				[]
			} else {
				[{ from: -16384, to: -16384 }, { from: -1 - (b * 61 % 16383).to_i64_wrap(), to: -(c * 64).to_i64_wrap() }, { from: 0, to: 0 }, { from: 1 + (c * 61 % 16383).to_i64_wrap(), to: (b * 64).to_i64_wrap() }, { from: 16384, to: 16384 }]
			}
		},
	)
	regions = FontBuild.counting(region_count).map(
		|r| FontBuild.counting(axis_count).map(
			|a| {
				peak = (signed(pick(picks, 20 + r + a)) * 128).max(-16384).min(16384)
				spread = pick(picks, 28 + r + 2 * a).to_i64_wrap() * 64
				# Ranges ordered, inside [-1, 1] and not crossing zero, as
				# OTS requires; with raw maps, a byte from 0xF0 gives a
				# region of the smaller font (so both fonts have it) whose
				# start is past its peak.
				low = if (peak > 0) 0 else -16384
				high = if (peak < 0) 0 else 16384
				if (raw and r < own and pick(picks, 28 + r) >= 0xF0) { start: peak + 1, peak, end: peak } else { start: (peak - spread).max(low).min(peak), peak, end: (peak + spread).min(high).max(peak) }
			},
		),
	)
	columns = FontBuild.counting(own.min(4))
	delta = |row, column| signed(pick(picks, 36 + row + 3 * column)) * (if (pick(picks, 40 + column) % 5 == 0) 200 else 1)
	# Rows of the first subtable use the smaller font's regions; the second
	# subtable (only in the larger font) uses the extra ones.
	extra_columns = FontBuild.counting(4).map(|k| own + k % (region_count - own).max(1)).keep_if(|k| k < region_count)
	mapped = choice.bitwise_and(0x20) != 0
	rows = if (mapped) 7 else glyphs
	first = { regions: columns, rows: FontBuild.counting(rows).map(|row| columns.map(|c| delta(row, c))) }
	second = { regions: extra_columns, rows: FontBuild.counting(5).map(|row| extra_columns.map(|c| delta(row + 3, c))) }
	subtables = if (copies > 1 and !extra_columns.is_empty()) [first, second] else [first]
	store = FontBuild.variation_store(axis_count, regions, subtables)
	small_glyphs = 32
	mapping = if (mapped) FontBuild.counting(glyphs).map(|g| if (g < small_glyphs or subtables.len() < 2) { outer: 0, inner: g % rows } else { outer: 1, inner: g % 5 }) else []
	mask = pick(picks, 44) * 256 + pick(picks, 45)
	values = FontBuild.counting(metric_tags.len()).keep_if(|k| mask.shr_zf_wrap(k.to_u8_wrap()).bitwise_and(1) != 0).map(|k| { tag: metric_tags.get(k) ?? "xhgt", outer: 0, inner: k % rows })
	metric_store = FontBuild.variation_store(axis_count, regions, [{ regions: columns, rows: FontBuild.counting(11).map(|row| columns.map(|c| delta(row + 5, c))) }])
	mvar_values = values.map(|v| { tag: v.tag, outer: v.outer, inner: v.inner % 11 })
	os2 = if (choice.bitwise_and(0x10) != 0) [{ tag: "OS/2", data: FontBuild.os2({ use_typo: True, typo_ascent: 750, typo_descent: -250, win_ascent: 900, win_descent: 300 }) }] else []
	extra = [
		{ tag: "fvar", data: FontBuild.fvar(axes) },
		{ tag: "avar", data: FontBuild.avar(maps) },
		{ tag: "HVAR", data: FontBuild.hvar(store, mapping) },
		{ tag: "MVAR", data: FontBuild.mvar(metric_store, mvar_values) },
	].concat(os2)
	# `A` to `H` only: both fonts map the same letters, so the metrics
	# estimated from letters agree.
	characters = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 0x41, last: 0x48, delta: 65536 - 0x40, glyphs: [] }]) }])
	file = FontBuild.glyphs_font(FontBuild.counting(glyphs).map(|g| 100 + g % 400), characters, extra)
	{ file, glyphs, axes, raw }
}

## A `Dec` from a 16-bit signed value and a scale byte: whole, thousandths,
## thousands or billions.
dec : U64, U64, U64 -> Dec
dec = |high, low, scale| {
	v = (high * 256 + low).to_i64_wrap() - 32768
	attos =
		match scale % 4 {
			0 => v.to_i128() * 1_000_000_000_000_000_000
			1 => v.to_i128() * 1_000_000_000_000_000
			2 => v.to_i128() * 1_000_000_000_000_000_000_000
			_ => v.to_i128() * 1_000_000_000_000_000_000_000_000_000
		}
	Dec.from_attos(attos)
}

weights : List(Font.Weight)
weights = [Thin, ExtraLight, Light, Regular, Medium, SemiBold, Bold, ExtraBold, Black]

widths : List(Font.Width)
widths = [UltraCondensed, ExtraCondensed, Condensed, SemiCondensed, Normal, SemiExpanded, Expanded, ExtraExpanded, UltraExpanded]

## Up to eight locations, eight bytes each.
locations : List(U8) -> List(Font.Variation)
locations = |bytes| {
	count = (bytes.len() // 8).min(8)
	FontBuild.counting(count).map(
		|k| {
			b = |i| (bytes.get(8 * k + i) ?? 0).to_u64()
			weight = if (b(0) < 9) weights.get(b(0)) ?? Regular else if (b(0) < 128) Weight((b(0) * 256 + b(1)).to_u16_wrap()) else Regular
			width = if (b(2) < 9) widths.get(b(2)) ?? Normal else if (b(2) < 64) Percent(dec(b(3), b(4), b(5))) else Normal
			optical_size = if (b(5) % 3 == 0) Size(dec(b(6), b(7), b(5).shr_zf_wrap(2))) else FontDefault
			tag = if (b(6) % 4 == 3) "abcde" else if (b(6) % 4 == 2) "" else tags.get(b(6) % 8) ?? "wght"
			axes = if (b(7) % 2 == 0) [] else [{ tag, value: dec(b(1), b(4), b(7).shr_zf_wrap(1)) }, { tag: tags.get(b(3) % 8) ?? "wdth", value: dec(b(4), b(1), b(3)) }]
			Font.Variation.{ weight, width, optical_size, axes }
		},
	)
}

## The sum of the advances of glyphs `0 ..< count` (no list of them).
advances : Font, U64 -> I64
advances = |font, count| {
	var $sum = 0
	var $g = 0
	while $g < count {
		$sum = $sum + Font.advance(font, $g.to_u32_wrap()).to_i64()
		$g = $g + 1
	}
	$sum
}

check! : Built, List(Font.Variation) => Font
check! = |built, places| {
	font = match Font.from_bytes(built.file, Font.ReadOptions.{}) {
		Ok(f) => f
		Err(problems) => crash "a variable font was rejected: ${Str.inspect(problems)}"
	}
	if !built.raw {
		if !Font.dropped(font).is_empty() {
			crash "a valid variable font lost tables: ${Str.inspect(Font.dropped(font))}"
		}
		want = built.axes.map(|a| { tag: a.tag, min: Dec.from_attos(a.min.to_i128() * 1_000_000_000_000_000_000), default: Dec.from_attos(a.default.to_i128() * 1_000_000_000_000_000_000), max: Dec.from_attos(a.max.to_i128() * 1_000_000_000_000_000_000) })
		if Str.inspect(Font.axes(font)) != Str.inspect(want) {
			crash "the axes read are not the axes built: ${Str.inspect(Font.axes(font))}"
		}
	}
	# Every axis at its default (when no tag repeats): the `hmtx` advances.
	unique = built.axes.all(|a| built.axes.keep_if(|o| o.tag == a.tag).len() == 1)
	if unique {
		home = Font.at(font, Font.Variation.{ axes: built.axes.map(|a| { tag: a.tag, value: Dec.from_attos(a.default.to_i128() * 1_000_000_000_000_000_000) }) })
		for g in 0..<built.glyphs {
			if Font.advance(home, g.to_u32_wrap()).to_i64() != 100 + (g % 400).to_i64_wrap() {
				crash "glyph ${g.to_str()} advances ${Font.advance(home, g.to_u32_wrap()).to_str()} at the default location, not its hmtx advance"
			}
		}
	}
	for place in places.append(Font.Variation.{}) {
		moved = Font.at(font, place)
		again = Font.at(font, place)
		if Str.inspect(Font.metrics(moved)) != Str.inspect(Font.metrics(again)) {
			crash "the metrics at one location differ between two calls"
		}
		for g in 0..<(built.glyphs + 2) {
			advance = Font.advance(moved, g.to_u32_wrap())
			if advance != Font.advance(again, g.to_u32_wrap()) {
				crash "an advance at one location differs between two calls"
			}
			if advance < 0 or advance > 1_000_000 {
				crash "glyph ${g.to_str()} advances ${advance.to_str()} at ${Str.inspect(place)}"
			}
			if g >= built.glyphs and advance != 0 {
				crash "a glyph past the font has an advance"
			}
		}
		run = Font.shape(moved, "ABCDEFGH", Font.ShapeOptions.{})
		if run.glyphs.len() != 8 or run.advances.len() != 8 or run.clusters != [0, 1, 2, 3, 4, 5, 6, 7] {
			crash "shaping a moved font broke its run"
		}
	}
	font
}

target = Fuzz.target_with!({
	name: "font-var",
	generator: Fuzz.raw_bytes,
	test!,
	show: |bytes| Str.inspect(bytes.take_first(49)),
})
