import Bytes
import AatLookup
import AatState

## AAT kerning tables prepared as scalar descriptors and flat pools.
## All encoded spans are validated at read. Dynamic state/stack operands
## have bounded runtime guards; missing references never select glyph0.
TableAatKern := { bytes : List(U8), subtables : List(Sub), lookups : List(AatLookup), states : List(AatState), pairs : List(Pair), values : List(I32) }.{
	Problem : { offset : U64 }
	Pair : { key : U64, value : I32 }
	Sub : { kind : U8, vertical : Bool, cross : Bool, backwards : Bool, variation : Bool, extended : Bool, at : U64, end : U64, start : U64, count : U64, left : U64, right : U64, array : U64, width : U64, vector : U64, tuples : U64, machine : U64, action : U64, action_type : U64 }
	no_sub : Sub
	no_sub = { kind: 255, vertical: False, cross: False, backwards: False, variation: False, extended: False, at: 0, end: 0, start: 0, count: 0, left: 0, right: 0, array: 0, width: 0, vector: 0, tuples: 0, machine: 0, action: 0, action_type: 0 }
	none : TableAatKern
	none = { bytes: [], subtables: [], lookups: [], states: [], pairs: [], values: [] }
	has_data : TableAatKern -> Bool
	has_data = |t| !t.subtables.is_empty()
	has_machine : TableAatKern -> Bool
	has_machine = |t| t.subtables.any(|s| s.kind == 1)
	has_cross_stream : TableAatKern -> Bool
	has_cross_stream = |t| t.subtables.any(|s| s.cross)
	read_kerx : List(U8), U64 -> Try(TableAatKern, List(Problem))
	read_kerx = |bytes, glyphs| TableAatKern.read(bytes, glyphs, True)
	read_kern : List(U8), U64 -> Try(TableAatKern, List(Problem))
	read_kern = |bytes, glyphs| TableAatKern.read(bytes, glyphs, False)
	read : List(U8), U64, Bool -> Try(TableAatKern, List(Problem))
	read = |bytes, glyphs, kerx| {
		bad = |at| Err([{ offset: at }])
		if glyphs > 65536 or !Bytes.fits(0, 4, bytes.len()) {
			return bad(0)
		}
		major = Bytes.u16(bytes, 0)
		apple = !kerx and major == 1
		if (kerx and (major < 2 or major > 4)) or (!kerx and major > 1) {
			return bad(0)
		}
		header = if (kerx or apple) 8 else 4
		if !Bytes.fits(0, header, bytes.len()) {
			return bad(0)
		}
		if (kerx or apple) and Bytes.u16(bytes, 2) != 0 {
			return bad(2)
		}
		count = if (kerx or apple) Bytes.u32(bytes, 4) else Bytes.u16(bytes, 2)
		sub_header = if (kerx) 12 else if (apple) 8 else 6
		# Every subtable needs its header before any count-sized preparation.
		if count > (bytes.len() - header) // sub_header {
			return bad(header)
		}
		var $t = { ..TableAatKern.none, bytes }
		var $at = header
		var $problems = []
		for index in 0..<count {
			if !Bytes.fits($at, sub_header, bytes.len()) {
				return bad($at)
			}
			length = if (kerx or apple) Bytes.u32(bytes, $at) else Bytes.u16(bytes, $at + 2)
			if length < sub_header or !Bytes.fits($at, length, bytes.len()) {
				return bad($at)
			}
			# HB uses the full table as the last subtable's sanitizer object. Old
			# OT kern lengths can truncate a valid final format0 array at64KiB.
			end = if (index + 1 == count) bytes.len() else $at + length
			coverage = if (kerx) Bytes.u32(bytes, $at + 4) else if (apple) Bytes.u8(bytes, $at + 4) else Bytes.u8(bytes, $at + 5)
			kind = if (kerx) coverage.bitwise_and(255) else Bytes.u8(bytes, $at + 5 - (if (apple) 0 else 1))
			vertical = if (kerx or apple) coverage.bitwise_and(if (kerx) 0x80000000 else 0x80) != 0 else coverage.bitwise_and(1) == 0
			cross = coverage.bitwise_and(if (kerx) 0x40000000 else if (apple) 0x40 else 4) != 0
			variation = (kerx or apple) and coverage.bitwise_and(if (kerx) 0x20000000 else 0x20) != 0
			backwards = kerx and coverage.bitwise_and(0x10000000) != 0
			tuples = if (kerx) Bytes.u32(bytes, $at + 8) else 0
			sub = { ..TableAatKern.no_sub, kind: kind.to_u8_wrap(), vertical, cross, variation, backwards, extended: kerx, at: $at, end, tuples }
			match TableAatKern.read_sub($t, sub, sub_header, glyphs) {
				Ok(next) => {
					$t = next
				}
				Err(ps) => {
					$problems = $problems.concat(ps)
				}
			}
			$at = $at + length
		}
		if kerx and major >= 3 {
			# Coverage is metadata only in pinned HB, but every bitmap is checked.
			if !Bytes.fits($at, count * 4, bytes.len()) {
				$problems = $problems.append({ offset: $at })
			} else {
				for index in 0..<count {
					field = $at + index * 4
					offset = Bytes.u32(bytes, field)
					target = $at + offset
					if offset != 0 and offset != 0xffffffff and !Bytes.fits(target, (glyphs + 7) // 8, bytes.len()) {
						$problems = $problems.append({ offset: field })
					}
				}
			}
		}
		if ($problems.is_empty()) Ok($t) else Err($problems)
	}
	read_sub : TableAatKern, Sub, U64, U64 -> Try(TableAatKern, List(Problem))
	read_sub = |t, s, header, glyphs| {
		if s.kind == 0 {
			return TableAatKern.read_pairs(t, s, header, glyphs)
		}
		if s.kind == 1 or (s.kind == 4 and s.extended) {
			return TableAatKern.read_machine(t, s, header, glyphs)
		}
		if s.kind == 2 or (s.kind == 6 and s.extended) {
			return TableAatKern.read_matrix(t, s, header, glyphs)
		}
		if s.kind == 3 and !s.extended {
			return TableAatKern.read_compact(t, s, header, glyphs)
		}
		# Unknown length-delimited formats are defined to be skipped.
		Ok({ ..t, subtables: t.subtables.append(s) })
	}
	tuple_value : List(U8), U64, U64, U64, U64, I64 -> Try(I32, List(Problem))
	tuple_value = |bytes, end, base, count, field, value| {
		if count == 0 {
			return Ok(value.to_i32_wrap())
		}
		# Pinned HB uses the first entry of a checked tuple vector. Its signed
		# source value is an unsigned byte offset, never a variation scalar.
		if value < 0 {
			return Err([{ offset: field }])
		}
		at = base + value.to_u64_wrap()
		if !Bytes.fits(at, count * 2, end) {
			return Err([{ offset: field }])
		}
		Ok(Bytes.i16(bytes, at).to_i32_wrap())
	}
	read_pairs : TableAatKern, Sub, U64, U64 -> Try(TableAatKern, List(Problem))
	read_pairs = |t, s, header, glyphs| {
		bad = |at| Err([{ offset: at }])
		size = if (s.extended) 4 else 2
		at = s.at + header
		if !Bytes.fits(at, size * 4, s.end) {
			return bad(at)
		}
		count = if (s.extended) Bytes.u32(t.bytes, at) else Bytes.u16(t.bytes, at)
		start = at + size * 4
		if !Bytes.fits(start, count * 6, s.end) {
			return bad(at)
		}
		var $pairs = t.pairs
		var $last = 0
		for index in 0..<count {
			p = start + index * 6
			left = Bytes.u16(t.bytes, p)
			right = Bytes.u16(t.bytes, p + 2)
			key = left * 65536 + right
			if index > 0 and key < $last {
				return bad(p)
			}
			# The conventional terminal pairFFFF/FFFF is harmless and valid.
			if (left >= glyphs or right >= glyphs) and key != 0xffffffff {
				return bad(p)
			}
			value = TableAatKern.tuple_value(t.bytes, s.end, s.at, s.tuples, p + 4, Bytes.i16(t.bytes, p + 4))?
			$pairs = $pairs.append({ key, value })
			$last = key
		}
		Ok({ ..t, pairs: $pairs, subtables: t.subtables.append({ ..s, start: t.pairs.len(), count }) })
	}
	read_machine : TableAatKern, Sub, U64, U64 -> Try(TableAatKern, List(Problem))
	read_machine = |t, s, header, glyphs| {
		bad = |at| Err([{ offset: at }])
		base = s.at + header
		size = if (s.extended) 4 else 2
		if !Bytes.fits(base, 5 * size, s.end) {
			return bad(base)
		}
		bounded = t.bytes.take_first(s.end)
		# State offsets are relative to the machine, including legacy kern.
		machine = match if (s.extended) AatState.read(bounded, base, glyphs, 1) else AatState.read_legacy(bounded, base, glyphs, 0) {
			Ok(m) => m
			Err(Bad(at)) => return bad(at)
		}
		field = base + 4 * size
		flags = if (s.extended) Bytes.u32(t.bytes, field) else Bytes.u16(t.bytes, field)
		action_type = if (s.kind == 4) flags.shr_zf_wrap(30) else 0
		action = base + (if (s.kind == 4) flags.bitwise_and(0xffffff) else flags)
		if action_type > 2 or (s.kind == 4 and flags.bitwise_and(0x3f000000) != 0) or !Bytes.fits(action, 0, s.end) {
			return bad(field)
		}
		var $problems = []
		for entry in AatState.entries(machine) {
			if s.kind == 4 {
				if (entry.a) != 65535 {
					width = if (action_type == 2) 8 else 4
					if !Bytes.fits(action + entry.a * width, width, s.end) {
						$problems = $problems.append({ offset: action + entry.a * width })
					}
				}
			} else {
				index = if (s.extended) entry.a else entry.flags.bitwise_and(0x3fff)
				active = if (s.extended) index != 65535 else index != 0
				if active {
					target = if (s.extended) action + index * 2 else base + index
					if (!s.extended and target < action) or !Bytes.fits(target, 2 * (s.tuples.max(1)), s.end) {
						$problems = $problems.append({ offset: target })
					}
				}
			}
		}
		if !$problems.is_empty() {
			return Err($problems)
		}
		Ok({ ..t, states: t.states.append(machine), subtables: t.subtables.append({ ..s, machine: t.states.len(), action, action_type, array: base }) })
	}
	read_class : List(U8), U64, U64, Bool, U64 -> Try(AatLookup, List(Problem))
	read_class = |bytes, at, glyphs, extended, width| {
		match if (extended) AatLookup.read(bytes, at, glyphs, width) else AatLookup.legacy_classes(bytes, at, width) {
			Ok(v) => Ok(v)
			Err(Bad(offset)) => Err([
				{
					offset: offset,
				},
			])
		}
	}
	# Distinct lookup values, in encoded order; no constant range expansion.
	class_values : AatLookup, U64 -> List(U64)
	class_values = |lookup, glyphs| {
		pool = AatLookup.value_pool(lookup)
		var $out = []
		for r in AatLookup.segments(lookup) {
			if r.first < glyphs {
				if r.array {
					for index in 0..<((r.last + 1).min(glyphs) - r.first) {
						$out = $out.append((pool.get(r.value + index) ?? 0).to_u64())
					}
				} else {
					$out = $out.append(r.value)
				}
			}
		}
		$out
	}
	read_matrix : TableAatKern, Sub, U64, U64 -> Try(TableAatKern, List(Problem))
	read_matrix = |t, s, header, glyphs| {
		bad = |at| Err([{ offset: at }])
		at = s.at + header
		six = s.kind == 6
		size = if (s.extended) 4 else 2
		need = if (six) 24 else 4 * size
		if !Bytes.fits(at, need, s.end) {
			return bad(at)
		}
		flags = if (six) Bytes.u32(t.bytes, at) else 0
		width = if (six and flags.bitwise_and(1) != 0) 4 else 2
		fields = at + (if (six) 8 else size)
		left_at = s.at + (if (s.extended) Bytes.u32(t.bytes, fields) else Bytes.u16(t.bytes, fields))
		right_at = s.at + (if (s.extended) Bytes.u32(t.bytes, fields + size) else Bytes.u16(t.bytes, fields + size))
		array = s.at + (if (s.extended) Bytes.u32(t.bytes, fields + 2 * size) else Bytes.u16(t.bytes, fields + 2 * size))
		vector = if (six) s.at + Bytes.u32(t.bytes, at + 20) else s.at
		if !Bytes.fits(array, 0, s.end) or (s.tuples > 0 and !Bytes.fits(vector, 0, s.end)) {
			return bad(fields + 2 * size)
		}
		bounded = t.bytes.take_first(s.end)
		left = TableAatKern.read_class(bounded, left_at, glyphs, s.extended, width)?
		right = TableAatKern.read_class(bounded, right_at, glyphs, s.extended, width)?
		lv = TableAatKern.class_values(left, glyphs)
		rv = TableAatKern.class_values(right, glyphs)
		# Encoded class arrays may alias the same matrix rows many times.
		# Extrema bound every possible sum without visiting their Cartesian
		# product. Tuple vectors belong to a dense matrix span and are checked
		# once per encoded cell, never once per glyph pair.
		var $problems = []
		if !lv.is_empty() and !rv.is_empty() {
			minimum = lv.fold(0xffffffff.U64, |a, b| a.min(b)) + rv.fold(0xffffffff.U64, |a, b| a.min(b))
			maximum = lv.fold(0.U64, |a, b| a.max(b)) + rv.fold(0.U64, |a, b| a.max(b))
			low = if (s.extended) array + minimum * (if (six) width else 2) else s.at + minimum
			high = if (s.extended) array + maximum * (if (six) width else 2) else s.at + maximum
			if maximum > 0xffffffff or low < array or !Bytes.fits(high, width, s.end) {
				return bad(fields)
			}
			if s.tuples > 0 {
				# Extended cells are word/long indexed. Legacy has no tuple vectors.
				for index in minimum..<(maximum + 1) {
					target = array + index * width
					value = if (width == 4) Bytes.u32(t.bytes, target).to_u32_wrap().to_i32_wrap().to_i64() else Bytes.i16(t.bytes, target)
					match TableAatKern.tuple_value(t.bytes, s.end, vector, s.tuples, target, value) {
						Ok(_) => {}
						Err(ps) => {
							$problems = $problems.concat(ps)
						}
					}
				}
			}
		}
		if !$problems.is_empty() {
			return Err($problems)
		}
		Ok({ ..t, lookups: t.lookups.append(left).append(right), subtables: t.subtables.append({ ..s, left: t.lookups.len(), right: t.lookups.len() + 1, array, width, vector }) })
	}
	read_compact : TableAatKern, Sub, U64, U64 -> Try(TableAatKern, List(Problem))
	read_compact = |t, s, header, glyphs| {
		bad = |at| Err([{ offset: at }])
		at = s.at + header
		if !Bytes.fits(at, 6, s.end) {
			return bad(at)
		}
		count = Bytes.u16(t.bytes, at)
		values = Bytes.u8(t.bytes, at + 2)
		left_count = Bytes.u8(t.bytes, at + 3)
		right_count = Bytes.u8(t.bytes, at + 4)
		start = at + 6
		if count != glyphs or !Bytes.fits(start, values * 2 + count * 2 + left_count * right_count, s.end) {
			return bad(at)
		}
		left = start + values * 2
		right = left + count
		matrix = right + count
		var $problems = []
		for glyph in 0..<count {
			if Bytes.u8(t.bytes, left + glyph) >= left_count {
				$problems = $problems.append({ offset: left + glyph })
			}
			if Bytes.u8(t.bytes, right + glyph) >= right_count {
				$problems = $problems.append({ offset: right + glyph })
			}
		}
		for index in 0..<(left_count * right_count) {
			if Bytes.u8(t.bytes, matrix + index) >= values {
				$problems = $problems.append({ offset: matrix + index })
			}
		}
		if !$problems.is_empty() {
			return Err($problems)
		}
		Ok({ ..t, subtables: t.subtables.append({ ..s, start, count, left, right, array: matrix, width: right_count }) })
	}
	pair_value : TableAatKern, Sub, U64, U64 -> [Value(I64), Missing]
	pair_value = |t, s, left, right| {
		if s.kind == 0 {
			key = left * 65536 + right
			var $low = 0
			var $high = s.count
			while $low < $high {
				mid = $low + ($high - $low) // 2
				pair = t.pairs.get(s.start + mid) ?? { key: 0, value: 0 }
				if key == pair.key {
					return Value(pair.value.to_i64())
				}
				if key < pair.key {
					$high = mid
				} else {
					$low = mid + 1
				}
			}
			Missing
		} else if s.kind == 2 or s.kind == 6 {
			l = match AatLookup.get(t.lookups.get(s.left) ?? AatLookup.empty, left) {
				Found(v) => v.to_u64()
				Missing => return Missing
			}
			r = match AatLookup.get(t.lookups.get(s.right) ?? AatLookup.empty, right) {
				Found(v) => v.to_u64()
				Missing => return Missing
			}
			sum = l + r
			# Obsolete class offsets are bytes relative to the subtable; the
			# reference floors their displacement to a complete FWORD.
			at = if (s.extended) s.array + sum * s.width else s.array + (s.at + sum - s.array) // 2 * 2
			value = if (s.width == 4) Bytes.u32(t.bytes, at).to_u32_wrap().to_i32_wrap().to_i64() else Bytes.i16(t.bytes, at)
			if s.tuples == 0 {
				Value(value)
			} else {
				Value(Bytes.i16(t.bytes, s.vector + value.to_u64_wrap()))
			}
		} else if s.kind == 3 {
			if left >= s.count or right >= s.count {
				return Missing
			}
			l = Bytes.u8(t.bytes, s.left + left)
			r = Bytes.u8(t.bytes, s.right + right)
			index = Bytes.u8(t.bytes, s.array + l * s.width + r)
			Value(Bytes.i16(t.bytes, s.start + index * 2))
		} else Missing
	}

}

# Original table bytes; helpers remain outside the namesake/API.
aat_u16 : U64 -> List(U8)
aat_u16 = |n| [n.shr_zf_wrap(8).to_u8_wrap(), n.to_u8_wrap()]

aat_u32 : U64 -> List(U8)
aat_u32 = |n| aat_u16(n.shr_zf_wrap(16)).concat(aat_u16(n))

aat_pair_table : List(U8)
aat_pair_table = [0, 2, 0, 0, 0, 0, 0, 1].concat(aat_u32(34)).concat([0, 0, 0, 0, 0, 0, 0, 0]).concat(aat_u32(1)).concat(List.repeat(0, 12)).concat([0, 1, 0, 2, 255, 206])
expect match TableAatKern.read_kerx([0, 2, 0, 0, 0, 0, 0, 0], 3) {
	Ok(t) => !TableAatKern.has_data(t)
	Err(_) => False
}
expect match TableAatKern.read_kerx(aat_pair_table, 3) {
	Ok(t) => TableAatKern.pair_value(t, t.subtables.get(0) ?? TableAatKern.no_sub, 1, 2) == Value(-50) and TableAatKern.pair_value(t, t.subtables.get(0) ?? TableAatKern.no_sub, 2, 1) == Missing
	Err(_) => False
}
expect [0.U64, 3, 7, 10, 41].all(
	|n| match TableAatKern.read_kerx(aat_pair_table.take_first(n), 3) {
		Err(_) => True
		Ok(_) => False
	},
)
