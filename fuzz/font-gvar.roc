app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import fuzz.Fuzz
import font.Font
import build.FontBuild

## Glyph variations (`gvar`) of TrueType outlines, and glyph extents at
## fuzzed locations. The first input byte picks the shape of the font: 1
## to 3 axes (its value modulo 3), long `loca` offsets (bit 2), long `gvar`
## offsets (bit 3), short horizontal metrics for half the glyphs (bit 4)
## and side bearings that differ from the outlines' left edges (bit 5).
## The next 48 bytes choose 16 glyphs: an empty glyph, nine simple glyphs
## (one to three contours, on- and off-curve points, coordinates written
## as bytes, words and repeats), composites of them (offsets as bytes or
## words, sometimes an explicit scale of 1.0) and composites nested up to
## four deep, one using the empty glyph. They also choose each glyph's
## variations: up to three tuples, each with a shared or embedded peak
## (at 1, -1, 0.5 or -0.5 on each axis), sometimes an intermediate region,
## and the points it moves: the glyph's shared points, all of them, or
## private ones, some points of some contours (so the others are
## inferred) and the phantom points; one delta per contour or component.
## The rest chooses up to four locations, four bytes each (every axis at
## its minimum, default, maximum or a fraction between). The same choices
## build a font at two sizes: 16 and 128 glyphs, with 8 times the shared
## tuples, which only the extra glyphs use.
##
## Contract: both fonts read strictly with nothing dropped; `extents` is
## total and deterministic at every location, `Empty` for the empty glyph
## and past the font. At the default location it is the header-box rule:
## the left edge at the side bearing, the header's width and heights. At
## every location whose coordinates are all -1, 0 or 1 it equals a model
## of the recipe (each tuple there moves by its whole delta or not at all,
## and moves every point of a contour or component it touches); elsewhere
## a glyph without variations (itself and its components) has its default
## box, and every edge of any other lies within twice its deltas of the
## default. Every glyph of the smaller font measures the same in the
## larger at every location. Reading the larger font takes at most
## `10 × small + 256` allocations (linear); `at` and the extents of the
## smaller font's glyphs cost no more than 4 allocations more in the larger
## font (constant per query); nothing leaks.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = bytes.first() ?? 0
	picks = bytes.drop_first(1).take_first(48)
	small = recipe(choice, picks, 1)
	large = recipe(choice, picks, 8)
	places = locations(small.axes, bytes.drop_first(49))
	small_font = check!(small, places, FontBuild.counting(own_glyphs))
	# The larger font's last copy, which uses the last shared tuples (the
	# first copy is compared with the smaller font below).
	large_font = check!(large, places, FontBuild.counting(own_glyphs).map(|g| 7 * own_glyphs + g))
	for place in places {
		a = Font.at(small_font, place)
		b = Font.at(large_font, place)
		for g in 0..<own_glyphs {
			if Font.extents(a, g.to_u32_wrap()) != Font.extents(b, g.to_u32_wrap()) {
				crash "glyph ${g.to_str()} measures ${Str.inspect(Font.extents(a, g.to_u32_wrap()))} in the smaller font and ${Str.inspect(Font.extents(b, g.to_u32_wrap()))} in the larger at ${Str.inspect(Font.coordinates(a))}"
			}
		}
	}
	small_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(small.file, Font.ReadOptions.{}))
	large_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(large.file, Font.ReadOptions.{}))
	Fuzz.expect_no_leaks!(|{}| Font.from_bytes(large.file, Font.ReadOptions.{}))
	if large_read.allocations > 10 * small_read.allocations + 256 {
		crash "reading a font with 8 times the outlines and variations took ${large_read.allocations.to_str()} allocations, against ${small_read.allocations.to_str()}"
	}
	place = places.first() ?? Font.Variation.{}
	small_at = Fuzz.measure_allocs!(|{}| Font.at(small_font, place))
	large_at = Fuzz.measure_allocs!(|{}| Font.at(large_font, place))
	Fuzz.expect_no_leaks!(|{}| Font.at(large_font, place))
	if large_at.allocations > small_at.allocations + 4 {
		crash "moving a font with 8 times the shared tuples took ${large_at.allocations.to_str()} allocations, against ${small_at.allocations.to_str()}"
	}
	small_query = Fuzz.measure_allocs!(|{}| box_sum(small_at.value))
	large_query = Fuzz.measure_allocs!(|{}| box_sum(large_at.value))
	Fuzz.expect_no_leaks!(|{}| box_sum(large_at.value))
	if large_query.allocations > small_query.allocations + 4 {
		crash "measuring ${own_glyphs.to_str()} glyphs took ${large_query.allocations.to_str()} allocations in a font 8 times larger, against ${small_query.allocations.to_str()}"
	}
	Fuzz.keep
}

## Glyphs per copy of the recipe.
own_glyphs : U64
own_glyphs = 16

## Shared tuples per copy of the recipe.
own_shared : U64
own_shared = 3

Point : { x : I64, y : I64, on : Bool }

Bounds : { x_min : I64, y_min : I64, x_max : I64, y_max : I64 }

Ink : [Extents({ x_min : I32, y_min : I32, x_max : I32, y_max : I32 }), Empty, Unknown]

## A tuple as the model sees it: its region (peak, start and end per
## axis; start and end are the peak's implicit ones without an
## intermediate region) and, for every point of the glyph (its four
## phantom points last), whether the tuple touches it and its delta.
Tuple : { peak : List(I64), touched : List(Bool), dx : List(I64), dy : List(I64), spread : I64 }

## A glyph as the model sees it: 0 empty, 1 simple, 2 composite; its
## contours or components, its tuples, its side bearing and its header
## box (the box of its points at the default location).
Glyph : { kind : U64, contours : List(List(Point)), components : List({ glyph : U64, dx : I64, dy : I64, scale : Bool }), tuples : List(Tuple), bearing : I64, box : Bounds }

## The font a recipe builds: its file, glyphs and axes.
Built : { file : List(U8), glyphs : List(Glyph), axes : List({ tag : Str, min : I64, default : I64, max : I64 }) }

pick : List(U8), U64 -> U64
pick = |bytes, i| if (bytes.is_empty()) 0 else (bytes.get(i % bytes.len()) ?? 0).to_u64()

## A signed value from a byte, -128 to 127.
signed : U64 -> I64
signed = |b| b.to_i64_wrap() - 128

all_axes : List({ tag : Str, min : I64, default : I64, max : I64 })
all_axes = [{ tag: "wght", min: 100, default: 400, max: 900 }, { tag: "wdth", min: 50, default: 100, max: 200 }, { tag: "XTRA", min: -100, default: 0, max: 100 }]

peaks : List(I64)
peaks = [16384, -16384, 8192, -8192, 0, 16384]

## A peak for each axis from bytes, at least one not zero.
peak_of : U64, (U64 -> U64), U64 -> List(I64)
peak_of = |axes, byte, salt| {
	raw = FontBuild.counting(axes).map(|a| peaks.get(byte(a) % 6) ?? 0)
	if (raw.all(|p| p == 0)) raw.map_with_index(|_, a| if (a == salt % axes) 16384 else 0) else raw
}

## An intermediate region around a peak: start and end per axis, inside
## [-1, 1] and on the peak's side of zero.
region_of : List(I64), U64 -> { start : List(I64), end : List(I64) }
region_of = |peak, salt| {
	one = |p, a| {
		bit = salt.shr_zf_wrap(a.to_u8_wrap()).bitwise_and(1) == 1
		magnitude = p.abs()
		r =
			if magnitude == 16384 {
				{ s: if (bit) 8192 else 0, e: 16384 }
			} else if magnitude == 8192 {
				{ s: if (bit) 4096 else 0, e: if (salt % 3 == 0) 8192 else 16384 }
			} else {
				{ s: 0, e: 0 }
			}
		if (p < 0) { s: -r.e, e: -r.s } else r
	}
	ranges = peak.map_with_index(|p, a| one(p, a))
	{ start: ranges.map(|r| r.s), end: ranges.map(|r| r.e) }
}

## The default positions of a glyph's points (contour points of the glyph
## and its components), given the glyphs before it.
default_points : List(Glyph), Glyph -> List({ x : I64, y : I64 })
default_points = |earlier, glyph|
	match glyph.kind {
		1 => glyph.contours.join_map(|c| c.map(|p| { x: p.x, y: p.y }))
		2 =>
			glyph.components.join_map(
				|c| {
					child = earlier.get(c.glyph) ?? empty_glyph
					default_points(earlier, child).map(|p| { x: p.x + c.dx, y: p.y + c.dy })
				},
			)
		_ => []
	}

empty_glyph : Glyph
empty_glyph = { kind: 0, contours: [], components: [], tuples: [], bearing: 0, box: { x_min: 0, y_min: 0, x_max: 0, y_max: 0 } }

box_of : List({ x : I64, y : I64 }) -> Bounds
box_of = |points| {
	first = points.first() ?? { x: 0, y: 0 }
	{ x_min: points.fold(first.x, |m, p| m.min(p.x)), y_min: points.fold(first.y, |m, p| m.min(p.y)), x_max: points.fold(first.x, |m, p| m.max(p.x)), y_max: points.fold(first.y, |m, p| m.max(p.y)) }
}

## The point groups of a glyph: each contour of a simple glyph, each
## component of a composite (as `gvar` infers deltas within them), as a
## start and a length.
groups : Glyph -> List({ start : U64, len : U64 })
groups = |glyph|
	match glyph.kind {
		1 => {
			var $out = []
			var $at = 0
			for c in glyph.contours {
				$out = $out.append({ start: $at, len: c.len() })
				$at = $at + c.len()
			}
			$out
		}
		2 => glyph.components.map_with_index(|_, k| { start: k, len: 1 })
		_ => []
	}

## The points `gvar` numbers for a glyph, before its phantom points.
own_points : Glyph -> U64
own_points = |glyph|
	match glyph.kind {
		1 => glyph.contours.fold(0, |n, c| n + c.len())
		2 => glyph.components.len()
		_ => 0
	}

## Some points of some groups, and some phantom points, ascending.
subset : Glyph, (U64 -> U64) -> List(U64)
subset = |glyph, byte| {
	n = own_points(glyph)
	var $out = []
	for grp in groups(glyph) {
		k = grp.start
		if byte(k) % 3 != 0 {
			chosen = FontBuild.counting(grp.len).keep_if(|j| (byte(k + j + 7) + j) % 2 == 0)
			$out = $out.concat(if (chosen.is_empty()) [grp.start] else chosen.map(|j| grp.start + j))
		}
	}
	phantoms = FontBuild.counting(4).keep_if(|i| byte(n + i + 13) % 3 == 0).map(|i| n + i)
	$out.concat(phantoms)
}

recipe : U8, List(U8), U64 -> Built
recipe = |choice, picks, copies| {
	axis_count = 1 + choice.to_u64() % 3
	axes = all_axes.take_first(axis_count)
	long_loca = choice.bitwise_and(0x04) != 0
	long_gvar = choice.bitwise_and(0x08) != 0
	short_metrics = choice.bitwise_and(0x10) != 0
	shifted = choice.bitwise_and(0x20) != 0
	count = own_glyphs * copies
	shared = FontBuild.counting(own_shared * copies).map(|j| peak_of(axis_count, |a| pick(picks, 30 + 3 * j + a), j))
	# Shapes first: each glyph's contours or components, then its header
	# box, which composites take from their components.
	var $glyphs = []
	for g in 0..<count {
		q = g // own_glyphs
		l = g % own_glyphs
		base = q * own_glyphs
		at = |i| pick(picks, 11 * l + i + 5 * q)
		shape =
			if l == 0 {
				empty_glyph
			} else if l <= 9 {
				contours = FontBuild.counting(1 + at(0) % 3).map(
					|k| {
						cx = signed(at(2 + k)) * 3
						cy = signed(at(3 + k)) * 3
						w = 10 + (at(4 + k) * 2).to_i64_wrap()
						h = 10 + (at(5 + k) * 2).to_i64_wrap()
						FontBuild.counting(3 + at(1 + k) % 4).map(
							|j|
								if j == 0 {
									{ x: cx, y: cy, on: True }
								} else if j == 1 {
									{ x: cx + w, y: cy + h, on: at(k + j) % 3 != 0 }
								} else {
									{ x: cx + (at(6 + k + j) * 37).to_i64_wrap() % (w + 1), y: cy + (at(7 + k + j) * 53).to_i64_wrap() % (h + 1), on: at(k + j) % 3 != 0 }
								},
						)
					},
				)
				{ ..empty_glyph, kind: 1, contours }
			} else {
				children =
					if l <= 12 {
						FontBuild.counting(2 + at(0) % 2).map(|k| base + 1 + at(1 + k) % 9)
					} else if l == 13 {
						[base + 10 + at(0) % 3, base + 1 + at(1) % 9]
					} else if l == 14 {
						[base + 13, base, base + 1 + at(2) % 9]
					} else {
						[base + 14, base + 11]
					}
				components = children.map_with_index(
					|child, k| {
						scale = |i| if (at(i + k) % 5 == 0) 3 else 1
						{ glyph: child, dx: signed(at(2 + k)) * scale(3), dy: signed(at(4 + k)) * scale(5), scale: at(6 + k) % 4 == 0 }
					},
				)
				{ ..empty_glyph, kind: 2, components }
			}
		box = box_of(default_points($glyphs, shape))
		bearing = if (shape.kind == 0) 0 else box.x_min + (if (shifted) signed(at(9)) else 0)
		$glyphs = $glyphs.append({ ..shape, box, bearing })
	}
	shapes = $glyphs
	# Then variations: the model's tuples and their encoding.
	var $model = []
	var $encoded = []
	for g in 0..<count {
		glyph = shapes.get(g) ?? empty_glyph
		q = g // own_glyphs
		l = g % own_glyphs
		at = |i| pick(picks, 13 * l + i + 3 * q + 17)
		n = own_points(glyph)
		total = n + 4
		glyph_groups = groups(glyph)
		# The group of each of the glyph's own points.
		group_index = glyph_groups.map_with_index(|grp, j| List.repeat(j, grp.len)).join_map(|r| r)
		shared_points = if (at(0) % 2 == 0) Points(subset(glyph, |i| at(i + 40))) else None
		tuple_count = [0, 0, 1, 2, 3].get(at(1) % 5) ?? 0
		var $tuples = []
		var $specs = []
		for t in 0..<tuple_count {
			b = |i| at(2 + 5 * t + i)
			use_shared = b(0) % 3 == 0
			k = q * own_shared + b(0) // 3 % own_shared
			peak = if (use_shared) shared.get(k) ?? [] else peak_of(axis_count, |a| b(1 + a), b(4))
			between = if (b(2) % 3 == 0) Some(region_of(peak, b(3))) else None
			points_mode = b(3) % 4
			# The points it touches.
			touched_list =
				if points_mode == 0 {
					match shared_points {
						Points(list) if !list.is_empty() => list
						_ => FontBuild.counting(total)
					}
				} else if points_mode == 1 {
					FontBuild.counting(total)
				} else {
					# No point numbers would mean every point: name the left
					# phantom point instead.
					chosen = subset(glyph, |i| b(i + 20))
					if (chosen.is_empty()) [n] else chosen
				}
			touched = FontBuild.counting(total).map(|i| touched_list.contains(i))
			# One delta per group, and one per phantom point.
			big = |v, i| if (b(i) % 11 == 0) v * 5 else v
			group_dx = glyph_groups.map_with_index(|_, j| big(signed(b(6 + 2 * j)) // 2, 9 + j))
			group_dy = glyph_groups.map_with_index(|_, j| big(signed(b(7 + 2 * j)) // 2, 10 + j))
			delta = |i, axis|
				if i >= n {
					if (axis == 0) signed(b(11.U64 + i - n)) // 2 else signed(b(15.U64 + i - n)) // 4
				} else {
					j = group_index.get(i) ?? 0
					if (axis == 0) group_dx.get(j) ?? 0 else group_dy.get(j) ?? 0
				}
			dx = FontBuild.counting(total).map(|i| if (touched.get(i) ?? False) delta(i, 0) else 0)
			dy = FontBuild.counting(total).map(|i| if (touched.get(i) ?? False) delta(i, 1) else 0)
			spread = dx.concat(dy).fold(0, |m, v| m.max(v.abs()))
			$tuples = $tuples.append({ peak, touched, dx, dy, spread })
			points = if points_mode == 0 {
				# Without shared points, inheriting means every point.
				Inherit
			} else if points_mode == 1 {
				All
			} else {
				Own(touched_list)
			}
			written = |list| touched_list.map(|i| list.get(i) ?? 0)
			$specs = $specs.append({
				peak: if (use_shared) Shared(k) else Embedded(peak),
				between: match between {
					Some(r) => Range(r.start, r.end)
					None => Peak
				},
				points,
				xs: written(dx),
				ys: written(dy),
			})
		}
		$model = $model.append({ ..glyph, tuples: $tuples })
		$encoded = $encoded.append({ shared: shared_points, tuples: $specs })
	}
	glyphs = $model
	bytes = glyphs.map(
		|glyph|
			match glyph.kind {
				1 => FontBuild.simple_glyph(glyph.contours)
				2 => FontBuild.composite_glyph(glyph.components, glyph.box)
				_ => []
			},
	)
	long_metrics = if (short_metrics) count // 2 else count
	characters = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 0x41, last: 0x48, delta: 65536 - 0x40, glyphs: [] }]) }])
	extra = [{ tag: "fvar", data: FontBuild.fvar(axes) }, { tag: "gvar", data: FontBuild.gvar(axis_count, shared, $encoded, long_gvar) }]
	file = FontBuild.outline_font(bytes, FontBuild.counting(count).map(|g| 300 + g % 400), glyphs.map(|g| g.bearing), long_metrics, long_loca, characters, extra)
	{ file, glyphs, axes }
}

# ------------------------------------------------------------ the model

## Whether a tuple applies with its whole delta at coordinates that are
## all -1, 0 or 1: every axis of its peak is 0 or the coordinate.
active : Tuple, List(I64) -> Bool
active = |t, coords| t.peak.map_with_index(|p, a| (p, a)).all(|(p, a)| p == 0 or (coords.get(a) ?? 0) == p)

## A glyph's points at grid coordinates, as the model moves them: each
## active tuple moves every point of a group it touches by the group's
## delta, and composites add their moved component offsets.
model_points : List(Glyph), U64, List(I64) -> List({ x : I64, y : I64 })
model_points = |glyphs, g, coords| {
	glyph = glyphs.get(g) ?? empty_glyph
	live = glyph.tuples.keep_if(|t| active(t, coords))
	shift = |grp|
		live.fold(
			{ x: 0, y: 0 },
			|sum, t| {
				first = FontBuild.counting(grp.len).find_first(|j| t.touched.get(grp.start + j) ?? False)
				match first {
					Ok(j) => { x: sum.x + (t.dx.get(grp.start + j) ?? 0), y: sum.y + (t.dy.get(grp.start + j) ?? 0) }
					Err(_) => sum
				}
			},
		)
	match glyph.kind {
		1 =>
			groups(glyph).map_with_index(|grp, k| (grp, k)).join_map(
				|(grp, k)| {
					s = shift(grp)
					(glyph.contours.get(k) ?? []).map(|p| { x: p.x + s.x, y: p.y + s.y })
				},
			)
		2 =>
			glyph.components.map_with_index(|c, k| (c, k)).join_map(
				|(c, k)| {
					s = shift({ start: k, len: 1 })
					model_points(glyphs, c.glyph, coords).map(|p| { x: p.x + c.dx + s.x, y: p.y + c.dy + s.y })
				},
			)
		_ => []
	}
}

## The box the model gives a glyph at grid coordinates.
model_box : Built, U64, List(I64) -> Ink
model_box = |built, g, coords| {
	glyph = built.glyphs.get(g) ?? empty_glyph
	points = model_points(built.glyphs, g, coords)
	n = own_points(glyph)
	if points.is_empty() {
		Empty
	} else if coords.all(|c| c == 0) {
		header_box(glyph)
	} else {
		# Points are measured from the left phantom point, which sits at
		# the header's left edge minus the side bearing, moved by the
		# active tuples that touch it.
		moved = glyph.tuples.keep_if(|t| active(t, coords) and (t.touched.get(n) ?? False)).fold(0, |sum, t| sum + (t.dx.get(n) ?? 0))
		left = glyph.box.x_min - glyph.bearing + moved
		b = box_of(points)
		if b.x_min == b.x_max or b.y_min == b.y_max {
			Empty
		} else {
			Extents({ x_min: (b.x_min - left).to_i32_wrap(), y_min: b.y_min.to_i32_wrap(), x_max: (b.x_max - left).to_i32_wrap(), y_max: b.y_max.to_i32_wrap() })
		}
	}
}

## The header-box rule: the left edge at the side bearing, the header's
## width and heights.
header_box : Glyph -> Ink
header_box = |glyph|
	if glyph.kind == 0 {
		Empty
	} else {
		b = glyph.box
		Extents({ x_min: glyph.bearing.to_i32_wrap(), y_min: b.y_min.to_i32_wrap(), x_max: (glyph.bearing + b.x_max - b.x_min).to_i32_wrap(), y_max: b.y_max.to_i32_wrap() })
	}

## Whether a glyph and all its components have no tuples.
fixed : List(Glyph), U64 -> Bool
fixed = |glyphs, g| {
	glyph = glyphs.get(g) ?? empty_glyph
	glyph.tuples.is_empty() and glyph.components.all(|c| fixed(glyphs, c.glyph))
}

## The most a glyph's points (and its left phantom point) can move: the
## largest delta of each of its tuples, and of its components'.
reach : List(Glyph), U64 -> I64
reach = |glyphs, g| {
	glyph = glyphs.get(g) ?? empty_glyph
	glyph.tuples.fold(0, |sum, t| sum + t.spread) + glyph.components.fold(0, |sum, c| sum + reach(glyphs, c.glyph))
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

## The sum of the edges of glyphs `0 ..< own_glyphs` (no list of them).
box_sum : Font -> I64
box_sum = |font| {
	var $sum = 0
	var $g = 0
	while $g < own_glyphs {
		edges =
			match Font.extents(font, $g.to_u32_wrap()) {
				Extents(b) => b.x_min.to_i64() + b.y_min.to_i64() + b.x_max.to_i64() + b.y_max.to_i64()
				_ => 1
			}
		$sum = $sum + edges
		$g = $g + 1
	}
	$sum
}

## Check a font at every place, measuring the glyphs `measured`.
check! : Built, List(Font.Variation), List(U64) => Font
check! = |built, places, measured| {
	font = match Font.from_bytes(built.file, Font.ReadOptions.{ strict: True }) {
		Ok(f) => f
		Err(problems) => crash "a valid font with glyph variations was rejected: ${Str.inspect(problems)}"
	}
	if !Font.dropped(font).is_empty() {
		crash "a valid font with glyph variations lost tables: ${Str.inspect(Font.dropped(font))}"
	}
	count = built.glyphs.len()
	want_axes = built.axes.map(|a| { tag: a.tag, min: Dec.from_attos(a.min.to_i128() * 1_000_000_000_000_000_000), default: Dec.from_attos(a.default.to_i128() * 1_000_000_000_000_000_000), max: Dec.from_attos(a.max.to_i128() * 1_000_000_000_000_000_000) })
	if Str.inspect(Font.axes(font)) != Str.inspect(want_axes) {
		crash "the axes read are not the axes built: ${Str.inspect(Font.axes(font))}"
	}
	zero = built.axes.map(|_| 0)
	defaults = FontBuild.counting(count).map(|g| if (measured.contains(g)) model_box(built, g, zero) else Empty)
	# Determinism: every glyph twice at the first place.
	first = Font.at(font, places.first() ?? Font.Variation.{})
	twice = Font.at(font, places.first() ?? Font.Variation.{})
	for g in measured {
		if Font.extents(first, g.to_u32_wrap()) != Font.extents(twice, g.to_u32_wrap()) {
			crash "glyph ${g.to_str()} measures differently in two calls at ${Str.inspect(Font.coordinates(first))}"
		}
	}
	for place in places.append(Font.Variation.{}) {
		moved = Font.at(font, place)
		coords = Font.coordinates(moved).map(|c| c.value.to_i64())
		grid = coords.all(|c| c == 0 or c == 16384 or c == -16384)
		for g in measured {
			got = Font.extents(moved, g.to_u32_wrap())
			default = defaults.get(g) ?? Empty
			if grid {
				want = model_box(built, g, coords)
				if got != want {
					crash "glyph ${g.to_str()} measures ${Str.inspect(got)} at ${Str.inspect(coords)}, but the recipe gives ${Str.inspect(want)}"
				}
			} else if fixed(built.glyphs, g) {
				if got != default {
					crash "glyph ${g.to_str()}, without variations, measures ${Str.inspect(got)} at ${Str.inspect(coords)}, not its default ${Str.inspect(default)}"
				}
			} else {
				limit = 2 * reach(built.glyphs, g) + 1
				near = |a, b| (a.to_i64() - b.to_i64()).abs() <= limit
				ok =
					match (got, default) {
						(Extents(a), Extents(b)) => near(a.x_min, b.x_min) and near(a.y_min, b.y_min) and near(a.x_max, b.x_max) and near(a.y_max, b.y_max)
						(Empty, Empty) => True
						_ => False
					}
				if !ok {
					crash "glyph ${g.to_str()} measures ${Str.inspect(got)} at ${Str.inspect(coords)}, more than ${limit.to_str()} from its default ${Str.inspect(default)}"
				}
			}
		}
		for g in [count, count + 1, 0xFFFFFFFF] {
			if Font.extents(moved, g.to_u32_wrap()) != Empty {
				crash "a glyph past the font has a box"
			}
		}
	}
	# At the default location: the header-box rule.
	home = Font.at(font, Font.Variation.{ axes: built.axes.map(|a| { tag: a.tag, value: Dec.from_attos(a.default.to_i128() * 1_000_000_000_000_000_000) }) })
	for g in measured {
		want = header_box(built.glyphs.get(g) ?? empty_glyph)
		if Font.extents(home, g.to_u32_wrap()) != want or Font.extents(font, g.to_u32_wrap()) != want {
			crash "glyph ${g.to_str()} measures ${Str.inspect(Font.extents(home, g.to_u32_wrap()))} at the default location, not its header box ${Str.inspect(want)}"
		}
	}
	font
}

target = Fuzz.target_with!({
	name: "font-gvar",
	generator: Fuzz.raw_bytes,
	test!,
	show: |bytes| Str.inspect(bytes.take_first(49)),
})
