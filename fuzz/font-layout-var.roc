app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import fuzz.Fuzz
import font.Font
import build.FontBuild

## Layout that varies: pair kerning whose values take deltas from the
## `GDEF` item variation store through device tables, and `GSUB` and
## `GPOS` feature variations. The first input byte picks the shape of the
## font: 1 to 3 axes (its value modulo 3), value records with or without a
## stored x advance (bit 2), lookup variation records in `GSUB` (bit 3),
## feature variations in `GPOS` (bit 4) and condition combinations (and,
## or, not) besides axis ranges (bit 5) and two or three first classes
## for the class kerning lookup (bit 6). The next 48 bytes choose the
## store's regions (each on one axis, peaking at 1, 0.5 or -1 and so on,
## some intermediate) and deltas; the pairs of three kerning lookups (pair
## adjustment formats 1, 2 and 1 again) and each pair's device (none, a
## `VariationIndex` into either of two data subtables, no variation, or a
## hinting device, which adds nothing in font units); which lookups the
## `kern`, `calt` and `rvrn` features use; feature variation records
## (conditions on axis ranges, and the lookups that replace a feature's,
## sometimes two for one feature, of which the first counts); lookup
## variation records (keeping the feature's lookups or not, adding those
## of each condition that holds); and the text, up to 24 glyphs: six that
## one substitution lookup each replaces, and eleven that kern. The rest
## chooses up to four locations, four bytes each (every axis at its
## minimum, default, maximum or a fraction between). The same choices
## build a font at two sizes: 24 and 192 glyphs, with 8 times the regions,
## kerning pairs and substitution lookups, and records whose conditions
## never hold, which only the extra glyphs use.
##
## Contract: both fonts read strictly with nothing dropped; shaping is total
## and deterministic, and gives the run the recipe's model gives at every
## location: each glyph replaced exactly when the lookup that replaces it
## applies there (the first feature variation record whose conditions
## hold, then the lookup variation records, decide), and the advances are
## the glyphs' own plus, for every adjacent pair, each applied kerning
## lookup's value: its stored value plus its device's delta, the region
## scalars (exact at every location, since each region spans a power of
## two) weighted by the deltas and rounded half up, nothing for a hinting
## device or at the default location. Both fonts give the same run.
## Reading the larger font takes at most `10 × small + 256` allocations
## (linear); shaping the same text at a location with a plan costs no more
## than 8 allocations more in the larger font (constant per call), and
## planning no more than 8 more plus one for each of the 7 extra records
## (which planning evaluates before giving up on them); nothing leaks.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = bytes.first() ?? 0
	picks = bytes.drop_first(1).take_first(48)
	small = recipe(choice, picks, 1)
	large = recipe(choice, picks, 8)
	places = locations(small.axes, bytes.drop_first(49))
	glyphs = text_glyphs(picks)
	text = Str.from_utf8_lossy(glyphs.join_map(utf8))
	small_font = check!(small, places, glyphs, text)
	large_font = check!(large, places, glyphs, text)
	for place in places {
		a = Font.shape(Font.at(small_font, place), text, Font.ShapeOptions.{})
		b = Font.shape(Font.at(large_font, place), text, Font.ShapeOptions.{})
		if Str.inspect(a) != Str.inspect(b) {
			crash "the fonts shape the text differently at ${Str.inspect(Font.coordinates(Font.at(small_font, place)))}: ${Str.inspect(a.glyphs)} and ${Str.inspect(b.glyphs)}"
		}
	}
	small_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(small.file, Font.ReadOptions.{}))
	large_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(large.file, Font.ReadOptions.{}))
	Fuzz.expect_no_leaks!(|{}| Font.from_bytes(large.file, Font.ReadOptions.{}))
	if large_read.allocations > 10 * small_read.allocations + 256 {
		crash "reading 8 times the varied layout took ${large_read.allocations.to_str()} allocations, against ${small_read.allocations.to_str()}"
	}
	place = places.first() ?? Font.Variation.{}
	small_at = Font.at(small_font, place)
	large_at = Font.at(large_font, place)
	small_plan = Fuzz.measure_allocs!(|{}| Font.plan(small_at, Font.ShapeOptions.{}))
	large_plan = Fuzz.measure_allocs!(|{}| Font.plan(large_at, Font.ShapeOptions.{}))
	Fuzz.expect_no_leaks!(|{}| Font.plan(large_at, Font.ShapeOptions.{}))
	# Planning evaluates every feature variation record before the one
	# that matches, the larger font's 7 extra records among them, on one
	# reused stack, so extra records cost no allocations.
	if large_plan.allocations > small_plan.allocations + 8 {
		crash "planning with 8 times the lookups and records took ${large_plan.allocations.to_str()} allocations, against ${small_plan.allocations.to_str()}"
	}
	small_shape = Fuzz.measure_allocs!(|{}| Font.shape_planned(small_at, small_plan.value, text))
	large_shape = Fuzz.measure_allocs!(|{}| Font.shape_planned(large_at, large_plan.value, text))
	Fuzz.expect_no_leaks!(|{}| Font.shape_planned(large_at, large_plan.value, text))
	if large_shape.allocations > small_shape.allocations + 8 {
		crash "shaping one text with 8 times the varied layout took ${large_shape.allocations.to_str()} allocations, against ${small_shape.allocations.to_str()}"
	}
	Fuzz.keep
}

## Glyph ids: substituted glyphs (each replaced by `replaced + k`), and
## kerning glyphs, of which the first six are first glyphs.
triggers : U64
triggers = 6

replaced : U64
replaced = 7

kerned : U64
kerned = 13

kerned_count : U64
kerned_count = 11

firsts : U64
firsts = 6

own_glyphs : U64
own_glyphs = 24

Device : [NoDevice, Index(U64, U64), Hinting(U64, U64, U64, U64)]

Condition : { kind : U64, ranges : List({ axis : U64, min : I64, max : I64 }) }

Pair : { first : U64, second : U64, value : I64, device : Device }

Region : { axis : U64, start : I64, peak : I64, end : I64 }

## The font a recipe builds and what the model needs: the store (regions
## and the rows of its first two data subtables), the value format, the
## kerning lookups (pairs of lookups 0 and 2; class counts, cells and the
## choice that classes the second glyphs, for lookup 1), the lookups each
## feature uses and the variation records.
Built : {
	file : List(U8),
	axes : List({ tag : Str, min : I64, default : I64, max : I64 }),
	regions : List(Region),
	rows : List(List(List(I64))),
	columns : List(List(U64)),
	format : U64,
	pairs0 : List(Pair),
	pairs2 : List(Pair),
	height : U64,
	width : U64,
	cells : List({ value : I64, device : Device }),
	choice : U64,
	kern : List(U64),
	calt : List(U64),
	rvrn : List(U64),
	gsub_records : List({ conditions : List(Condition), substitutions : List({ feature : U64, lookups : List(U64) }) }),
	gsub_lookup_records : List({ feature : U64, keep : Bool, conditions : List({ condition : Condition, lookups : List(U64) }) }),
	gpos_records : List({ conditions : List(Condition), substitutions : List({ feature : U64, lookups : List(U64) }) }),
}

pick : List(U8), U64 -> U64
pick = |bytes, i| if (bytes.is_empty()) 0 else (bytes.get(i % bytes.len()) ?? 0).to_u64()

## A signed value from a byte, -128 to 127.
signed : U64 -> I64
signed = |b| b.to_i64_wrap() - 128

all_axes : List({ tag : Str, min : I64, default : I64, max : I64 })
all_axes = [{ tag: "wght", min: 100, default: 400, max: 900 }, { tag: "wdth", min: 50, default: 100, max: 200 }, { tag: "XTRA", min: -100, default: 0, max: 100 }]

## Regions on one axis whose rising and falling sides each span a power of
## two (in F2Dot14), so their scalars are exact binary fractions.
spans : List({ start : I64, peak : I64, end : I64 })
spans = [
	{ start: 0, peak: 16384, end: 16384 },
	{ start: 0, peak: 8192, end: 16384 },
	{ start: 8192, peak: 16384, end: 16384 },
	{ start: 0, peak: 8192, end: 8192 },
	{ start: 0, peak: 4096, end: 8192 },
	{ start: -16384, peak: -16384, end: 0 },
	{ start: -16384, peak: -8192, end: 0 },
	{ start: -16384, peak: -16384, end: -8192 },
	{ start: -8192, peak: -8192, end: 0 },
	{ start: -8192, peak: -4096, end: 0 },
]

## A subset of `0 ..< n` from a byte's bits.
bits_of : U64, U64 -> List(U64)
bits_of = |b, n| FontBuild.counting(n).keep_if(|k| b.shr_zf_wrap(k.to_u8_wrap()).bitwise_and(1) == 1)

## A condition from bytes: an axis range (min up to max, sometimes
## crossing so that it never holds), or with combinations, and, or or not
## of up to three ranges.
condition_of : U64, Bool, (U64 -> U64) -> Condition
condition_of = |axis_count, combine, byte| {
	range = |i| {
		low = (signed(byte(i + 1)) * 128).max(-16384).min(16384)
		high = (low + (byte(i + 2) * 96).to_i64_wrap()).min(16384)
		{ axis: byte(i) % axis_count, min: low, max: if (byte(i + 3) % 13 == 0) low - 1 else high }
	}
	kind = if (combine) [1, 1, 3, 4, 5].get(byte(0) % 5) ?? 1 else 1
	count = if (kind == 3 or kind == 4) 1 + byte(5) % 3 else 1
	{ kind, ranges: FontBuild.counting(count).map(|k| range(1 + 4 * k)) }
}

## The lookups out of `0 ..< count` a byte names, in increasing order.
lookups_of : U64, U64 -> List(U64)
lookups_of = |b, count| bits_of(b, count)

recipe : U8, List(U8), U64 -> Built
recipe = |choice, picks, copies| {
	axis_count = 1 + choice.to_u64() % 3
	axes = all_axes.take_first(axis_count)
	format = if (choice.bitwise_and(0x04) != 0) 0x40 else 0x44
	lookup_records = choice.bitwise_and(0x08) != 0
	gpos_varied = choice.bitwise_and(0x10) != 0
	combine = choice.bitwise_and(0x20) != 0
	glyph_count = own_glyphs * copies
	# The store: the smaller font's regions, then the extra ones.
	own_regions = 2 + pick(picks, 0) % 5
	regions = FontBuild.counting(own_regions * copies).map(
		|r| {
			span = spans.get(pick(picks, 1 + r) % 10) ?? { start: 0, peak: 16384, end: 16384 }
			{ axis: pick(picks, 2 + r) % axis_count, start: span.start, peak: span.peak, end: span.end }
		},
	)
	row = |salt, columns| columns.map_with_index(|_, k| signed(pick(picks, 3 * salt + 5 * k + 7)))
	columns0 = FontBuild.counting(own_regions)
	columns1 = [own_regions - 1, 0]
	columns2 = FontBuild.counting(own_regions * (copies - 1)).map(|k| own_regions + k)
	rows0 = FontBuild.counting(8).map(|r| row(r, columns0))
	rows1 = FontBuild.counting(4).map(|r| row(r + 9, columns1))
	rows2 = FontBuild.counting(8).map(|r| row(r + 2, columns2))
	subtables = [{ regions: columns0, rows: rows0 }, { regions: columns1, rows: rows1 }].concat(if (copies > 1) [{ regions: columns2, rows: rows2 }] else [])
	store = FontBuild.variation_store(
		axis_count,
		regions.map(|r| FontBuild.counting(axis_count).map(|a| if (a == r.axis) { start: r.start, peak: r.peak, end: r.end } else { start: 0, peak: 0, end: 0 })),
		subtables,
	)
	# Devices: the extra glyphs' use the extra subtable.
	device = |b, extra|
		match b % 6 {
			0 => NoDevice
			1 | 2 => if (extra) Index(2, b % 8) else Index(0, b // 6 % 8)
			3 => if (extra) Index(2, b // 6 % 8) else Index(1, b // 6 % 4)
			4 => Index(0xFFFF, 0xFFFF)
			_ => Hinting(8 + b % 10, 8 + b % 10 + b % 20, 1 + b % 3, b * 257 % 65536)
		}
	# First glyphs: six of the smaller font's, then 18 more per copy.
	first_glyphs = FontBuild.counting(firsts).map(|j| kerned + j).concat(FontBuild.counting(18 * (copies - 1)).map(|j| own_glyphs + j))
	pairs_of = |salt|
		first_glyphs.map_with_index(|f, j| (f, j)).join_map(
			|(f, j)| {
				b = pick(picks, j + salt)
				FontBuild.counting(kerned_count).keep_if(|s| (b * 7 + s * 13 + j) % 4 == 0).map(
					|s| {
						d = pick(picks, j + s + salt + 3)
						{ first: f, second: kerned + s, value: signed(pick(picks, s + 2 * j + salt)), device: device(d, f >= own_glyphs) }
					},
				)
			},
		)
	pairs0 = pairs_of(11)
	pairs2 = pairs_of(29)
	sets = |pairs| first_glyphs.map(|f| { glyph: f, pairs: pairs.keep_if(|p| p.first == f).map(|p| { second: p.second, value: p.value, device: p.device }) }).keep_if(|s| !s.pairs.is_empty())
	height = 2 + choice.shr_zf_wrap(6).to_u64() % 2
	width = 1 + pick(picks, 40) % 4
	cells = FontBuild.counting(height * width).map(|k| { value: signed(pick(picks, k + 17)), device: device(pick(picks, k + 23), False) })
	class1 = FontBuild.classes2(first_glyphs.map_with_index(|f, j| { first: f, last: f, class: 1 + j % (height - 1) }))
	class2 = FontBuild.classes1(kerned, FontBuild.counting(kerned_count).map(|s| second_class(choice.to_u64(), width, kerned + s)))
	kern_lookups = [
		{ kind: 2, subtables: [FontBuild.pair1_devices(format, sets(pairs0))] },
		{ kind: 2, subtables: [FontBuild.pair2_devices(format, FontBuild.coverage1(first_glyphs), class1, class2, height, width, cells)] },
		{ kind: 2, subtables: [FontBuild.pair1_devices(format, sets(pairs2))] },
	]
	# Substitutions: lookup k replaces glyph 1 + k; the larger font's
	# extra lookups replace extra glyphs and only never-holding records
	# use them.
	gsub_count = triggers * copies
	gsub_lookups = FontBuild.counting(gsub_count).map(
		|k| {
			from = if (k < triggers) 1 + k else own_glyphs + k
			to = if (k < triggers) replaced + k else own_glyphs + k + 1
			{ kind: 1, subtables: [if (pick(picks, k + 5) % 2 == 0) FontBuild.single1([from], to.to_i64_wrap() - from.to_i64_wrap()) else FontBuild.single2([from], [to])] }
		},
	)
	kern = lookups_of(pick(picks, 41), 2)
	calt = lookups_of(pick(picks, 42), triggers)
	rvrn = lookups_of(pick(picks, 43), triggers)
	never = { kind: 1, ranges: [{ axis: 0, min: 16384, max: -16384 }] }
	record_of = |salt, features, count|
		{
			conditions: FontBuild.counting(pick(picks, salt) % 3).map(|c| condition_of(axis_count, combine, |i| pick(picks, salt + 7 * c + i + 1))),
			substitutions: FontBuild.counting(1 + pick(picks, salt + 2) % 3).map(|k| { feature: (pick(picks, salt + k) + k) % features, lookups: lookups_of(pick(picks, salt + k + 4), count) }),
		}
	extra_records = |features, count| FontBuild.counting(copies - 1).map(|k| { conditions: [never], substitutions: [{ feature: k % features, lookups: FontBuild.counting(triggers).map(|j| (k + 1) * triggers + j).keep_if(|l| l < count) }] })
	gsub_records = FontBuild.counting(pick(picks, 44) % 4).map(|r| record_of(13 * r + 3, 2, triggers)).concat(extra_records(2, gsub_count))
	gpos_records = if (gpos_varied) FontBuild.counting(pick(picks, 45) % 4).map(|r| record_of(11 * r + 5, 1, 3)) else []
	gsub_lookup_records =
		if lookup_records {
			FontBuild.counting(1 + pick(picks, 46) % 3).map(
				|v| {
					b = |i| pick(picks, 9 * v + i + 19)
					{ feature: b(0) % 2, keep: b(1) % 2 == 0, conditions: FontBuild.counting(b(2) % 3).map(|c| { condition: condition_of(axis_count, combine, |i| b(5 * c + i + 3)), lookups: lookups_of(b(c + 4), triggers) }) }
				},
			)
		} else {
			[]
		}
	gsub = FontBuild.layout_varied("latn", [{ tag: "calt", lookups: calt }, { tag: "rvrn", lookups: rvrn }], gsub_lookups, FontBuild.layout_variations(gsub_records, gsub_lookup_records))
	gpos =
		if gpos_varied {
			FontBuild.layout_varied("latn", [{ tag: "kern", lookups: kern }], kern_lookups, FontBuild.layout_variations(gpos_records, []))
		} else {
			FontBuild.layout("latn", [{ tag: "kern", lookups: kern }], kern_lookups)
		}
	characters = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 0xE000, last: 0xE000 + glyph_count - 1, delta: 65536 - 0xE000, glyphs: [] }]) }])
	extra = [
		{ tag: "fvar", data: FontBuild.fvar(axes) },
		{ tag: "GDEF", data: FontBuild.gdef_store(store) },
		{ tag: "GSUB", data: gsub },
		{ tag: "GPOS", data: gpos },
	]
	file = FontBuild.glyphs_font(FontBuild.counting(glyph_count).map(|g| 100 + g % 400), characters, extra)
	{
		file,
		axes,
		regions,
		rows: [rows0, rows1],
		columns: [columns0, columns1],
		format,
		pairs0,
		pairs2,
		height,
		width,
		cells,
		choice: choice.to_u64(),
		kern,
		calt,
		rvrn,
		gsub_records,
		gsub_lookup_records,
		gpos_records,
	}
}

## The class lookup 1 gives a second glyph: kerning glyphs by the recipe,
## every other glyph class 0.
second_class : U64, U64, U64 -> U64
second_class = |choice, width, g| if (g >= kerned and g < kerned + kerned_count) (5 * g + choice) % width else 0

# ------------------------------------------------------------ the model

## Floor division by a positive divisor.
floor_div : I64, I64 -> I64
floor_div = |a, b| if (a >= 0) a // b else -((-a + b - 1) // b)

## A region's scalar at normalised coordinates, in units of 1/16384
## (exact: every span is a power of two).
scalar : Region, List(I64) -> I64
scalar = |r, coords| {
	c = coords.get(r.axis) ?? 0
	if c == r.peak {
		16384
	} else if c <= r.start or c >= r.end {
		0
	} else if c < r.peak {
		(c - r.start) * (16384 // (r.peak - r.start))
	} else {
		(r.end - c) * (16384 // (r.end - r.peak))
	}
}

## A device's delta at a location: the row's deltas weighted by the
## region scalars, rounded half up; none for no device, no variation or a
## hinting device, and none at the default location.
delta : Built, Device, List(I64) -> I64
delta = |built, device, coords|
	match device {
		Index(outer, inner) if outer < 2 and coords.any(|c| c != 0) => {
			row = (built.rows.get(outer) ?? []).get(inner) ?? []
			columns = built.columns.get(outer) ?? []
			sum = columns.map_with_index(|region, k| (region, k)).fold(0, |s, (region, k)| s + (row.get(k) ?? 0) * scalar(built.regions.get(region) ?? { axis: 0, start: 0, peak: 0, end: 0 }, coords))
			floor_div(sum + 8192, 16384)
		}
		_ => 0
	}

## A value record's x advance at a location.
advance_value : Built, I64, Device, List(I64) -> I64
advance_value = |built, value, device, coords| (if (built.format.bitwise_and(0x04) != 0) value else 0) + delta(built, device, coords)

## The kerning lookup `lookup` gives a pair at a location.
lookup_kerning : Built, U64, U64, U64, List(I64) -> I64
lookup_kerning = |built, lookup, left, right, coords|
	if lookup == 1 {
		if left >= kerned and left < kerned + firsts {
			j = left - kerned
			cell = built.cells.get((1 + j % (built.height - 1)) * built.width + second_class(built.choice, built.width, right)) ?? { value: 0, device: NoDevice }
			advance_value(built, cell.value, cell.device, coords)
		} else {
			0
		}
	} else {
		pairs = if (lookup == 0) built.pairs0 else built.pairs2
		match pairs.find_first(|p| p.first == left and p.second == right) {
			Ok(p) => advance_value(built, p.value, p.device, coords)
			Err(_) => 0
		}
	}

holds : Condition, List(I64) -> Bool
holds = |c, coords| {
	one = |r| {
		v = coords.get(r.axis) ?? 0
		r.min <= v and v <= r.max
	}
	first = c.ranges.first() ?? { axis: 0, min: 1, max: 0 }
	match c.kind {
		3 => c.ranges.all(one)
		4 => c.ranges.any(one)
		5 => !one(first)
		_ => one(first)
	}
}

## The lookups of feature `feature` at a location: its own, or the first
## substitution for it in the first record whose conditions all hold;
## then the first lookup variation record for it, if any, replaces them
## with those of its conditions that hold (plus its own when it keeps
## them).
feature_lookups : List({ conditions : List(Condition), substitutions : List({ feature : U64, lookups : List(U64) }) }), List({ feature : U64, keep : Bool, conditions : List({ condition : Condition, lookups : List(U64) }) }), U64, List(U64), List(I64) -> List(U64)
feature_lookups = |records, lookup_records, feature, own, coords| {
	current =
		match records.find_first(|r| r.conditions.all(|c| holds(c, coords))) {
			Ok(r) =>
				match r.substitutions.find_first(|s| s.feature == feature) {
					Ok(s) => s.lookups
					Err(_) => own
				}
			Err(_) => own
		}
	match lookup_records.find_first(|v| v.feature == feature) {
		Ok(v) => (if (v.keep) current else []).concat(v.conditions.keep_if(|c| holds(c.condition, coords)).join_map(|c| c.lookups))
		Err(_) => current
	}
}

## The run the model gives the text's glyphs at a location: the glyphs
## after substitution and the width.
model_run : Built, List(U64), List(I64) -> { glyphs : List(U64), width : I64 }
model_run = |built, text, coords| {
	gsub = feature_lookups(built.gsub_records, built.gsub_lookup_records, 0, built.calt, coords).concat(feature_lookups(built.gsub_records, built.gsub_lookup_records, 1, built.rvrn, coords))
	gpos = feature_lookups(built.gpos_records, [], 0, built.kern, coords)
	glyphs = text.map(|g| if (g >= 1 and g <= triggers and gsub.contains(g - 1)) replaced + g - 1 else g)
	var $width = 0
	for k in 0..<glyphs.len() {
		g = glyphs.get(k) ?? 0
		$width = $width + 100 + (g % 400).to_i64_wrap()
		if k + 1 < glyphs.len() {
			right = glyphs.get(k + 1) ?? 0
			for lookup in 0..<3 {
				if gpos.contains(lookup) {
					$width = $width + lookup_kerning(built, lookup, g, right, coords)
				}
			}
		}
	}
	{ glyphs, width: $width }
}

## Up to 24 glyphs: substituted glyphs and kerning glyphs.
text_glyphs : List(U8) -> List(U64)
text_glyphs = |picks|
	FontBuild.counting(picks.len().min(24)).map(
		|k| {
			b = pick(picks, 3 * k + 1)
			if (b % 2 == 0) 1 + b // 2 % triggers else kerned + b // 2 % kerned_count
		},
	)

## A private-use character's UTF-8 bytes: glyph `g` is U+E000 + `g`.
utf8 : U64 -> List(U8)
utf8 = |g| {
	cp = 0xE000 + g
	[(0xE0 + cp.shr_zf_wrap(12)).to_u8_wrap(), (0x80 + cp.shr_zf_wrap(6).bitwise_and(0x3F)).to_u8_wrap(), (0x80 + cp.bitwise_and(0x3F)).to_u8_wrap()]
}

## Up to four locations, four bytes each (every axis at its minimum,
## default, maximum or a fraction between), then every axis at its
## maximum and every axis at its minimum.
locations : List({ tag : Str, min : I64, default : I64, max : I64 }), List(U8) -> List(Font.Variation)
locations = |axes, bytes| {
	whole = |v| Dec.from_attos(v.to_i128() * 1_000_000_000_000_000_000)
	value = |a, b|
		match b % 4 {
			0 => whole(a.min)
			1 => whole(a.default)
			2 => whole(a.max)
			_ => Dec.from_attos((a.min * 63 + (b // 4).to_i64_wrap() * (a.max - a.min)).to_i128() * 1_000_000_000_000_000_000 // 63)
		}
	count = (bytes.len() // 4).min(4)
	chosen = FontBuild.counting(count).map(|k| Font.Variation.{ axes: axes.map_with_index(|a, i| { tag: a.tag, value: value(a, (bytes.get(4 * k + 1 + i) ?? 0).to_u64()) }) })
	corner = |f| Font.Variation.{ axes: axes.map_with_index(|a, i| { tag: a.tag, value: whole(f(a, i)) }) }
	chosen.concat([corner(|a, _| a.max), corner(|a, _| a.min)])
}

check! : Built, List(Font.Variation), List(U64), Str => Font
check! = |built, places, glyphs, text| {
	font = match Font.from_bytes(built.file, Font.ReadOptions.{ strict: True }) {
		Ok(f) => f
		Err(problems) => crash "a valid font with varied layout was rejected: ${Str.inspect(problems)}"
	}
	if !Font.dropped(font).is_empty() {
		crash "a valid font with varied layout lost tables: ${Str.inspect(Font.dropped(font))}"
	}
	n = text.to_utf8().len()
	first = places.first() ?? Font.Variation.{}
	if Str.inspect(Font.shape(Font.at(font, first), text, Font.ShapeOptions.{})) != Str.inspect(Font.shape(Font.at(font, first), text, Font.ShapeOptions.{})) {
		crash "shaping the same text twice at one location gave different runs"
	}
	for place in places.append(Font.Variation.{}) {
		moved = Font.at(font, place)
		coords = Font.coordinates(moved).map(|c| c.value.to_i64())
		run = Font.shape(moved, text, Font.ShapeOptions.{})
		count = run.glyphs.len()
		if count != glyphs.len() or run.advances.len() != count or run.offsets.len() != count or run.clusters.len() != count or run.flags.len() != count {
			crash "a run's lists are not index-aligned with the text's glyphs"
		}
		if run.clusters != FontBuild.counting(glyphs.len()).map(|k| 3 * k) or n != 3 * glyphs.len() {
			crash "clusters are not the text's characters"
		}
		want = model_run(built, glyphs, coords)
		if run.glyphs.map(|g| g.to_u64()) != want.glyphs {
			crash "at ${Str.inspect(coords)} the glyphs are ${Str.inspect(run.glyphs)}, but the recipe gives ${Str.inspect(want.glyphs)}"
		}
		got = run.advances.fold(0, |sum, a| sum + a.x.to_i64())
		if got != want.width {
			crash "at ${Str.inspect(coords)} the width is ${got.to_str()}, but the recipe gives ${want.width.to_str()}"
		}
		if !run.offsets.all(|o| o.x == 0 and o.y == 0) or !run.advances.all(|a| a.y == 0) {
			crash "kerning moved a glyph off its advance"
		}
		if Font.width(moved, text).to_i64() != got {
			crash "the width is not the sum of the advances"
		}
	}
	font
}

target = Fuzz.target_with!({
	name: "font-layout-var",
	generator: Fuzz.raw_bytes,
	test!,
	show: |bytes| Str.inspect(bytes.take_first(49)),
})
