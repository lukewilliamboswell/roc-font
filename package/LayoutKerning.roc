import Bytes

## Pair kerning: the `kern` feature's pair adjustment lookups in `GPOS`
## (lookup type 2, directly or through an extension), or the horizontal
## format 0 subtables of a TrueType `kern` table for a font without `GPOS`.
##
## Reading checks every offset and count a kerning query will follow and
## keeps the table's bytes; queries read coverage, class definitions, pair
## sets and value records in place. Reading therefore allocates a few lists
## per table, not per pair, pair set or glyph. The checked subtables are one
## flat list in lookup order; `ends` holds, for each lookup, the end of its
## subtables in that list.
##
## `Kern` is a `kern` format 0 subtable: `count` pairs of six bytes from
## `at`, sorted by their first and second glyph. `Sets` is GPOS pair format
## 1 and `Classes` pair format 2; their fields are offsets into the table
## and the subtable's value formats. Only the x advance of each value record
## is used.
LayoutKerning := {
	data : List(U8),
	subtables : List(
		[
			Kern({ at : U64, count : U64 }),
			Sets({ at : U64, coverage : U64, set_count : U64, format1 : U64, format2 : U64, size1 : U64, size2 : U64 }),
			Classes({ at : U64, coverage : U64, rows : U64, columns : U64, width : U64, height : U64, format1 : U64, format2 : U64, size1 : U64, size2 : U64 }),
		],
	),
	ends : List(U64),
	digests : List({ a : U64, b : U64, c : U64 }),
}.{

	## No kerning.
	none : LayoutKerning
	none = { data: [], subtables: [], ends: [], digests: [] }

	## How many subtables reading kept, for tests of reading costs.
	stored_size : LayoutKerning -> U64
	stored_size = |kerning| kerning.subtables.len() + kerning.ends.len()

	# ------------------------------------------------------------ applying

	## Kerning for a run of glyphs, as the change to each glyph's advance.
	## Each lookup runs over the whole run in order and its adjustments add
	## up. A first glyph at or past `glyph_count` is never kerned by `GPOS`;
	## a second one there is in class 0.
	adjust : LayoutKerning, List(U64), U64 -> List(F64)
	adjust = |kerning, glyphs, glyph_count| {
		count = glyphs.len()
		var $adjust = List.repeat(0.0, count)
		var $start = 0
		for end in kerning.ends {
			var $i = 0
			while $i + 1 < count {
				left = glyphs.get($i) ?? 0
				right = glyphs.get($i + 1) ?? 0
				match LayoutKerning.pair(kerning, $start, end, left, right, glyph_count) {
					Applied(found) => {
						# `$i + 1 < count`, so both indices are in bounds.
						a = ($adjust.get($i) ?? 0.0) + found.first.to_f64()
						$adjust = $adjust.set($i, a) ?? []
						b = ($adjust.get($i + 1) ?? 0.0) + found.second.to_f64()
						$adjust = $adjust.set($i + 1, b) ?? []
						$i = if (found.skips) $i + 2 else $i + 1
					}
					NotApplied => {
						$i = $i + 1
					}
				}
			}
			$start = end
		}
		$adjust
	}

	# The first subtable of a lookup that has the pair decides it.
	pair : LayoutKerning, U64, U64, U64, U64, U64 -> [Applied({ first : I64, second : I64, skips : Bool }), NotApplied]
	pair = |kerning, start, end, left, right, glyph_count| {
		data = kerning.data
		var $result = NotApplied
		var $k = start
		while $k < end {
			# The digest rules out most first glyphs without a search.
			may = LayoutKerning.may_have(kerning.digests.get($k) ?? LayoutKerning.full, left)
			outcome = if !may {
				NotApplied
			} else match kerning.subtables.get($k) {
				Ok(Kern(k)) => LayoutKerning.kern_pair(data, k.at, k.count, left, right)
				Ok(Sets(s)) if left < glyph_count => LayoutKerning.set_pair(data, s, left, right)
				Ok(Classes(c)) if left < glyph_count => LayoutKerning.class_pair(data, c, left, right, glyph_count)
				_ => NotApplied
			}
			match outcome {
				Applied(found) => {
					$result = Applied(found)
					$k = end
				}
				NotApplied => {
					$k = $k + 1
				}
			}
		}
		$result
	}

	kern_pair : List(U8), U64, U64, U64, U64 -> [Applied({ first : I64, second : I64, skips : Bool }), NotApplied]
	kern_pair = |data, at, count, left, right|
		if left > 0xFFFF or right > 0xFFFF {
			NotApplied
		} else {
			key = left * 65536 + right
			var $low = 0
			var $high = count
			var $result = NotApplied
			while $low < $high {
				mid = ($low + $high) // 2
				r = at + 6 * mid
				probe = Bytes.u32(data, r)
				if key < probe {
					$high = mid
				} else if key > probe {
					$low = mid + 1
				} else {
					$result = Applied({ first: Bytes.i16(data, r + 4), second: 0, skips: False })
					$low = $high
				}
			}
			$result
		}

	# Pair format 1: the first glyph's coverage index picks a pair set, in
	# which the second glyph is looked up.
	set_pair : List(U8), { at : U64, coverage : U64, set_count : U64, format1 : U64, format2 : U64, size1 : U64, size2 : U64 }, U64, U64 -> [Applied({ first : I64, second : I64, skips : Bool }), NotApplied]
	set_pair = |data, s, left, right|
		match LayoutKerning.covered(data, s.coverage, left) {
			Ok(index) if index < s.set_count => {
				set = s.at + Bytes.u16(data, s.at + 10 + 2 * index)
				record = 2 + s.size1 + s.size2
				var $low = 0
				var $high = Bytes.u16(data, set)
				var $result = NotApplied
				while $low < $high {
					mid = ($low + $high) // 2
					r = set + 2 + record * mid
					probe = Bytes.u16(data, r)
					if right < probe {
						$high = mid
					} else if right > probe {
						$low = mid + 1
					} else {
						$result = Applied({ first: LayoutKerning.x_advance(data, r + 2, s.format1), second: LayoutKerning.x_advance(data, r + 2 + s.size1, s.format2), skips: s.format2 != 0 })
						$low = $high
					}
				}
				$result
			}
			_ => NotApplied
		}

	# Pair format 2: a grid of first classes by second classes. A class past
	# the grid matches nothing.
	class_pair : List(U8), { at : U64, coverage : U64, rows : U64, columns : U64, width : U64, height : U64, format1 : U64, format2 : U64, size1 : U64, size2 : U64 }, U64, U64, U64 -> [Applied({ first : I64, second : I64, skips : Bool }), NotApplied]
	class_pair = |data, c, left, right, glyph_count|
		if LayoutKerning.covered(data, c.coverage, left).is_err() {
			NotApplied
		} else {
			row = LayoutKerning.class_of(data, c.rows, left)
			column = if (right < glyph_count) LayoutKerning.class_of(data, c.columns, right) else 0
			if row >= c.height or column >= c.width {
				NotApplied
			} else {
				r = c.at + 16 + (c.size1 + c.size2) * (row * c.width + column)
				Applied({ first: LayoutKerning.x_advance(data, r, c.format1), second: LayoutKerning.x_advance(data, r + c.size1, c.format2), skips: c.format2 != 0 })
			}
		}

	## The coverage index of a glyph in a checked coverage table: a sorted
	## glyph array (format 1) or ranges with their first index (format 2).
	## Ranges are searched as stored; one whose last glyph comes before its
	## first matches nothing.
	covered : List(U8), U64, U64 -> Try(U64, [NotCovered])
	covered = |data, at, glyph| {
		count = Bytes.u16(data, at + 2)
		var $low = 0
		var $high = count
		var $result = Err(NotCovered)
		if Bytes.u16(data, at) == 1 {
			while $low < $high {
				mid = ($low + $high) // 2
				probe = Bytes.u16(data, at + 4 + 2 * mid)
				if glyph < probe {
					$high = mid
				} else if glyph > probe {
					$low = mid + 1
				} else {
					$result = Ok(mid)
					$low = $high
				}
			}
		} else {
			while $low < $high {
				mid = ($low + $high) // 2
				r = at + 4 + 6 * mid
				if glyph < Bytes.u16(data, r) {
					$high = mid
				} else if glyph > Bytes.u16(data, r + 2) {
					$low = mid + 1
				} else {
					$result = Ok(Bytes.u16(data, r + 4) + glyph - Bytes.u16(data, r))
					$low = $high
				}
			}
		}
		$result
	}

	## A glyph's class in a checked class definition: an array of classes
	## from a start glyph (format 1) or ranges (format 2). Other glyphs are
	## in class 0.
	class_of : List(U8), U64, U64 -> U64
	class_of = |data, at, glyph|
		if Bytes.u16(data, at) == 1 {
			start = Bytes.u16(data, at + 2)
			if (glyph >= start and glyph - start < Bytes.u16(data, at + 4)) Bytes.u16(data, at + 6 + 2 * (glyph - start)) else 0
		} else {
			var $low = 0
			var $high = Bytes.u16(data, at + 2)
			var $result = 0
			while $low < $high {
				mid = ($low + $high) // 2
				r = at + 4 + 6 * mid
				if glyph < Bytes.u16(data, r) {
					$high = mid
				} else if glyph > Bytes.u16(data, r + 2) {
					$low = mid + 1
				} else {
					$result = Bytes.u16(data, r + 4)
					$low = $high
				}
			}
			$result
		}

	# Size in bytes of a value record, and its x advance.
	value_size : U64 -> U64
	value_size = |format| 2 * format.bitwise_and(0xFF).to_u8_wrap().count_one_bits().to_u64()

	x_advance : List(U8), U64, U64 -> I64
	x_advance = |data, at, format|
		if format.bitwise_and(4) == 0 {
			0
		} else {
			skip = 2 * format.bitwise_and(3).to_u8_wrap().count_one_bits().to_u64()
			Bytes.i16(data, at + skip)
		}

	# ------------------------------------------------------------ digests

	## A digest of a subtable's first glyphs, as HarfBuzz keeps for coverage:
	## three 64-bit masks of the glyph index's bits 0-5, 4-9 and 9-14. A
	## glyph whose three bits are not all set is certainly not covered, so
	## the subtable is skipped without searching it; one whose bits are set
	## may be covered and is searched. Built in one pass over each coverage
	## table (or `kern` pair list) when reading. On Inter's kerning bench this
	## skips most coverage searches (see `scripts/bench.py --ops kerning`).
	digests : List(U8), List([Kern({ at : U64, count : U64 }), Sets({ at : U64, coverage : U64, set_count : U64, format1 : U64, format2 : U64, size1 : U64, size2 : U64 }), Classes({ at : U64, coverage : U64, rows : U64, columns : U64, width : U64, height : U64, format1 : U64, format2 : U64, size1 : U64, size2 : U64 })]) -> List({ a : U64, b : U64, c : U64 })
	digests = |data, subtables| {
		var $out = List.with_capacity(subtables.len())
		for subtable in subtables {
			var $d = LayoutKerning.empty_digest
			match subtable {
				Kern(k) => {
					for p in 0..<k.count {
						left = Bytes.u16(data, k.at + 6 * p)
						$d = LayoutKerning.add_range($d, left, left)
					}
				}
				Sets(t) => {
					$d = LayoutKerning.coverage_digest(data, t.coverage)
				}
				Classes(t) => {
					$d = LayoutKerning.coverage_digest(data, t.coverage)
				}
			}
			$out = $out.append($d)
		}
		$out
	}

	empty_digest : { a : U64, b : U64, c : U64 }
	empty_digest = { a: 0, b: 0, c: 0 }

	full : { a : U64, b : U64, c : U64 }
	full = { a: 0xFFFFFFFFFFFFFFFF, b: 0xFFFFFFFFFFFFFFFF, c: 0xFFFFFFFFFFFFFFFF }

	coverage_digest : List(U8), U64 -> { a : U64, b : U64, c : U64 }
	coverage_digest = |data, at| {
		count = Bytes.u16(data, at + 2)
		var $d = LayoutKerning.empty_digest
		if Bytes.u16(data, at) == 1 {
			for i in 0..<count {
				g = Bytes.u16(data, at + 4 + 2 * i)
				$d = LayoutKerning.add_range($d, g, g)
			}
		} else {
			for i in 0..<count {
				r = at + 4 + 6 * i
				first = Bytes.u16(data, r)
				last = Bytes.u16(data, r + 2)
				if first <= last {
					$d = LayoutKerning.add_range($d, first, last)
				}
			}
		}
		$d
	}

	add_range : { a : U64, b : U64, c : U64 }, U64, U64 -> { a : U64, b : U64, c : U64 }
	add_range = |d, first, last| {
		a: d.a.bitwise_or(LayoutKerning.mask(first, last, 0)),
		b: d.b.bitwise_or(LayoutKerning.mask(first, last, 4)),
		c: d.c.bitwise_or(LayoutKerning.mask(first, last, 9)),
	}

	# The bits of `first >> shift` up to `last >> shift`, modulo 64.
	mask : U64, U64, U8 -> U64
	mask = |first, last, shift| {
		low = first.shr_zf_wrap(shift)
		high = last.shr_zf_wrap(shift)
		one : U64
		one = 1
		all : U64
		all = 0xFFFFFFFFFFFFFFFF
		if high - low >= 63 {
			all
		} else {
			lb = low.bitwise_and(63).to_u8_wrap()
			hb = high.bitwise_and(63).to_u8_wrap()
			if lb <= hb {
				(one.shl_wrap(hb - lb + 1) - 1).shl_wrap(lb)
			} else {
				all.shl_wrap(lb).bitwise_or(one.shl_wrap(hb + 1) - 1)
			}
		}
	}

	may_have : { a : U64, b : U64, c : U64 }, U64 -> Bool
	may_have = |d, g|
		d.a.shr_zf_wrap(g.bitwise_and(63).to_u8_wrap()).bitwise_and(1) == 1
			and d.b.shr_zf_wrap(g.shr_zf_wrap(4).bitwise_and(63).to_u8_wrap()).bitwise_and(1) == 1
			and d.c.shr_zf_wrap(g.shr_zf_wrap(9).bitwise_and(63).to_u8_wrap()).bitwise_and(1) == 1

	# ------------------------------------------------------------ reading

	## Reading work is counted in steps: one per table visited and one per
	## entry checked. Offsets may point many times at the same data, so a few
	## bytes could otherwise describe billions of entries; a table that takes
	## more than eight steps per byte (plus a fixed allowance) is refused.
	## `spend` adds a visit costing `cost` entries to `steps`, failing when
	## the table's allowance is exceeded, before the entries are visited.
	spend : List(U8), U64, U64 -> Try(U64, [Bad])
	spend = |data, steps, cost| {
		total = steps + cost + 1
		if (total > 8 * data.len() + 16384) Err(Bad) else Ok(total)
	}

	tag_of : Str -> U64
	tag_of = |name| name.to_utf8().fold(0, |acc, b| acc * 256 + b.to_u64())

	## The pair adjustment lookups of every `kern` feature of a `GPOS` table,
	## each lookup once, in lookup list order.
	read_gpos : List(U8), U64 -> Try(LayoutKerning, [Bad])
	read_gpos = |gpos, glyph_count| {
		size = gpos.len()
		features = Bytes.u16(gpos, 6)
		lookups = Bytes.u16(gpos, 8)
		feature_count = Bytes.u16(gpos, features)
		lookup_count = Bytes.u16(gpos, lookups)
		if !Bytes.fits(0, 10, size) or !Bytes.fits(features, 2 + 6 * feature_count, size) or !Bytes.fits(lookups, 2 + 2 * lookup_count, size) {
			Err(Bad)
		} else {
			var $steps = LayoutKerning.spend(gpos, 0, feature_count)?
			var $wanted = List.repeat(False, lookup_count)
			kern = LayoutKerning.tag_of("kern")
			for f in 0..<feature_count {
				record = features + 2 + 6 * f
				if Bytes.u32(gpos, record) == kern {
					feature = features + Bytes.u16(gpos, record + 4)
					count = Bytes.u16(gpos, feature + 2)
					if !Bytes.fits(feature, 4 + 2 * count, size) {
						return Err(Bad)
					}
					$steps = LayoutKerning.spend(gpos, $steps, count)?
					for j in 0..<count {
						index = Bytes.u16(gpos, feature + 4 + 2 * j)
						if index >= lookup_count {
							return Err(Bad)
						}
						# `index < lookup_count`, the length of `$wanted`.
						$wanted = $wanted.set(index, True) ?? []
					}
				}
			}
			var $subtables = []
			var $ends = []
			for index in 0..<lookup_count {
				if $wanted.get(index) ?? False {
					lookup = lookups + Bytes.u16(gpos, lookups + 2 + 2 * index)
					kind = Bytes.u16(gpos, lookup)
					count = Bytes.u16(gpos, lookup + 4)
					if !Bytes.fits(lookup, 6 + 2 * count, size) {
						return Err(Bad)
					}
					$steps = LayoutKerning.spend(gpos, $steps, count)?
					for s in 0..<count {
						at = lookup + Bytes.u16(gpos, lookup + 6 + 2 * s)
						# An extension subtable points at the real one; one of
						# another lookup type is not kerning.
						target = if kind == 9 and Bytes.fits(at, 8, size) and Bytes.u16(gpos, at + 2) == 2 {
							Some(at + Bytes.u32(gpos, at + 4))
						} else if kind == 2 {
							Some(at)
						} else {
							None
						}
						match target {
							Some(start) => {
								done = LayoutKerning.read_pair(gpos, start, glyph_count, $steps)?
								$steps = done.steps
								$subtables = $subtables.append(done.value)
							}
							None => {}
						}
					}
					$ends = $ends.append($subtables.len())
				}
			}
			Ok({ data: gpos, subtables: $subtables, ends: $ends, digests: LayoutKerning.digests(gpos, $subtables) })
		}
	}

	read_pair : List(U8), U64, U64, U64 -> Try({ value : [Kern({ at : U64, count : U64 }), Sets({ at : U64, coverage : U64, set_count : U64, format1 : U64, format2 : U64, size1 : U64, size2 : U64 }), Classes({ at : U64, coverage : U64, rows : U64, columns : U64, width : U64, height : U64, format1 : U64, format2 : U64, size1 : U64, size2 : U64 })], steps : U64 }, [Bad])
	read_pair = |data, at, glyph_count, steps| {
		size = data.len()
		if !Bytes.fits(at, 10, size) {
			Err(Bad)
		} else {
			format = Bytes.u16(data, at)
			coverage = at + Bytes.u16(data, at + 2)
			after_coverage = LayoutKerning.check_coverage(data, coverage, steps)?
			format1 = Bytes.u16(data, at + 4)
			format2 = Bytes.u16(data, at + 6)
			size1 = LayoutKerning.value_size(format1)
			size2 = LayoutKerning.value_size(format2)
			if format == 1 {
				set_count = Bytes.u16(data, at + 8)
				if !Bytes.fits(at + 10, 2 * set_count, size) {
					Err(Bad)
				} else {
					after = LayoutKerning.check_sets(data, at, coverage, set_count, 2 + size1 + size2, glyph_count, after_coverage)?
					Ok({ value: Sets({ at, coverage, set_count, format1, format2, size1, size2 }), steps: after })
				}
			} else if format == 2 {
				if !Bytes.fits(at, 16, size) {
					Err(Bad)
				} else {
					height = Bytes.u16(data, at + 12)
					width = Bytes.u16(data, at + 14)
					if !Bytes.fits(at + 16, (size1 + size2) * width * height, size) {
						Err(Bad)
					} else {
						rows = at + Bytes.u16(data, at + 8)
						columns = at + Bytes.u16(data, at + 10)
						after_rows = LayoutKerning.check_classes(data, rows, after_coverage)?
						after = LayoutKerning.check_classes(data, columns, after_rows)?
						Ok({ value: Classes({ at, coverage, rows, columns, width, height, format1, format2, size1, size2 }), steps: after })
					}
				}
			} else {
				Err(Bad)
			}
		}
	}

	check_coverage : List(U8), U64, U64 -> Try(U64, [Bad])
	check_coverage = |data, at, steps| {
		format = Bytes.u16(data, at)
		count = Bytes.u16(data, at + 2)
		if format == 1 and Bytes.fits(at, 4 + 2 * count, data.len()) {
			LayoutKerning.spend(data, steps, count)
		} else if format == 2 and Bytes.fits(at, 4 + 6 * count, data.len()) {
			LayoutKerning.spend(data, steps, count)
		} else {
			Err(Bad)
		}
	}

	check_classes : List(U8), U64, U64 -> Try(U64, [Bad])
	check_classes = |data, at, steps| {
		format = Bytes.u16(data, at)
		if format == 1 and Bytes.fits(at, 6, data.len()) {
			count = Bytes.u16(data, at + 4)
			if (Bytes.fits(at + 6, 2 * count, data.len())) LayoutKerning.spend(data, steps, count) else Err(Bad)
		} else if format == 2 and Bytes.fits(at, 4, data.len()) {
			count = Bytes.u16(data, at + 2)
			if (Bytes.fits(at + 4, 6 * count, data.len())) LayoutKerning.spend(data, steps, count) else Err(Bad)
		} else {
			Err(Bad)
		}
	}

	# Pair format 1: the pair set of every coverage index a query can reach
	# (one whose glyph the font has) lies inside the table. Sets of glyphs
	# past the font are never looked at, so they are not checked.
	check_sets : List(U8), U64, U64, U64, U64, U64, U64 -> Try(U64, [Bad])
	check_sets = |data, at, coverage, set_count, record, glyph_count, steps| {
		size = data.len()
		count = Bytes.u16(data, coverage + 2)
		var $steps = LayoutKerning.spend(data, steps, set_count)?
		var $ok = True
		if Bytes.u16(data, coverage) == 1 {
			for i in 0..<count {
				if i < set_count and Bytes.u16(data, coverage + 4 + 2 * i) < glyph_count {
					$ok = $ok and LayoutKerning.set_fits(data, at, i, record, size)
				}
			}
		} else {
			for i in 0..<count {
				r = coverage + 4 + 6 * i
				first = Bytes.u16(data, r)
				last = Bytes.u16(data, r + 2)
				index = Bytes.u16(data, r + 4)
				if first <= last and first < glyph_count and index < set_count {
					span = (last.min(glyph_count - 1) - first + 1).min(set_count - index)
					$steps = LayoutKerning.spend(data, $steps, span)?
					for k in 0..<span {
						$ok = $ok and LayoutKerning.set_fits(data, at, index + k, record, size)
					}
				}
			}
		}
		if ($ok) Ok($steps) else Err(Bad)
	}

	set_fits : List(U8), U64, U64, U64, U64 -> Bool
	set_fits = |data, at, index, record, size| {
		set = at + Bytes.u16(data, at + 10 + 2 * index)
		Bytes.fits(set, 2 + record * Bytes.u16(data, set), size)
	}

	## A TrueType `kern` table: each horizontal format 0 subtable is a
	## lookup. Apple's version 1.0 layout of the table is read too, as
	## browsers do.
	read_kern : List(U8) -> Try(LayoutKerning, [Bad])
	read_kern = |kern| {
		version = Bytes.u16(kern, 0)
		if version == 1 {
			LayoutKerning.read_apple_kern(kern)
		} else if version != 0 {
			Err(Bad)
		} else {
			count = Bytes.u16(kern, 2)
			var $at = 4
			var $subtables = []
			var $ends = []
			for _ in 0..<count {
				if !Bytes.fits($at, 14, kern.len()) {
					return Err(Bad)
				}
				length = Bytes.u16(kern, $at + 2)
				coverage = Bytes.u16(kern, $at + 4)
				pairs = Bytes.u16(kern, $at + 6)
				if coverage == 0x0001 {
					if !Bytes.fits($at + 14, 6 * pairs, kern.len()) {
						return Err(Bad)
					}
					$subtables = $subtables.append(Kern({ at: $at + 14, count: pairs }))
					$ends = $ends.append($subtables.len())
				}
				$at = $at + length.max(6)
			}
			Ok({ data: kern, subtables: $subtables, ends: $ends, digests: LayoutKerning.digests(kern, $subtables) })
		}
	}

	# Apple's layout: a 32-bit version and count, and subtables with a 32-bit
	# length and an 8-bit coverage (vertical, cross-stream and variation
	# flags) followed by the format.
	read_apple_kern : List(U8) -> Try(LayoutKerning, [Bad])
	read_apple_kern = |kern| {
		count = Bytes.u32(kern, 4)
		if Bytes.u16(kern, 2) != 0 or !Bytes.fits(8, 0, kern.len()) {
			Err(Bad)
		} else {
			var $at = 8
			var $subtables = []
			var $ends = []
			var $k = 0
			while $k < count {
				length = Bytes.u32(kern, $at)
				if length < 16 or !Bytes.fits($at, length, kern.len()) {
					return Err(Bad)
				}
				coverage = Bytes.u8(kern, $at + 4)
				format = Bytes.u8(kern, $at + 5)
				if coverage.bitwise_and(0xE0) == 0 and format == 0 {
					pairs = Bytes.u16(kern, $at + 8)
					if !Bytes.fits($at + 16, 6 * pairs, kern.len()) {
						return Err(Bad)
					}
					$subtables = $subtables.append(Kern({ at: $at + 16, count: pairs }))
					$ends = $ends.append($subtables.len())
				}
				$at = $at + length
				$k = $k + 1
			}
			Ok({ data: kern, subtables: $subtables, ends: $ends, digests: LayoutKerning.digests(kern, $subtables) })
		}
	}
}
