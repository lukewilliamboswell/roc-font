import LayoutGsub
import LayoutVar
import LayoutPosition
import TableAatAnchor
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
	has_data = |t| !t.bytes.is_empty() and Bytes.u32(t.bytes, 0) != 0
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
			reserved = if (kerx) 0x0fffff00 else if (apple) 0x1f else 0xf0
			if coverage.bitwise_and(reserved) != 0 {
				$problems = $problems.append({ offset: $at + (if (kerx or apple) 4 else 5) })
			}
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
		selector = if (s.extended) Bytes.u32(t.bytes, at + 2 * size) else Bytes.u16(t.bytes, at + 2 * size)
		var $power = 0.U64
		while (1.U64).shl_wrap(($power + 1).to_u8_wrap()) <= count {
			$power = $power + 1
		}
		if selector != $power {
			return bad(at + 2 * size)
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
					target = if (s.extended) action + (index // 2) * 2 else base + index
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
		var $problems = []
		if !Bytes.fits(array, 0, s.end) {
			$problems = $problems.append({ offset: fields + 2 * size })
		}
		if s.tuples > 0 and !Bytes.fits(vector, 0, s.end) {
			$problems = $problems.append({ offset: at + 20 })
		}
		bounded = t.bytes.take_first(s.end)
		left = if !Bytes.fits(left_at, 2, s.end) {
			$problems = $problems.append({ offset: fields })
			AatLookup.empty
		} else match TableAatKern.read_class(bounded, left_at, glyphs, s.extended, width) {
			Ok(v) => v
			Err(ps) => {
				$problems = $problems.concat(ps)
				AatLookup.empty
			}
		}
		right = if !Bytes.fits(right_at, 2, s.end) {
			$problems = $problems.append({ offset: fields + size })
			AatLookup.empty
		} else match TableAatKern.read_class(bounded, right_at, glyphs, s.extended, width) {
			Ok(v) => v
			Err(ps) => {
				$problems = $problems.concat(ps)
				AatLookup.empty
			}
		}
		if !$problems.is_empty() {
			return Err($problems)
		}
		lv = TableAatKern.class_values(left, glyphs)
		rv = TableAatKern.class_values(right, glyphs)
		# Encoded class arrays may alias the same matrix rows many times.
		# Extrema bound every possible sum without visiting their Cartesian
		# product. Tuple vectors belong to a dense matrix span and are checked
		# once per encoded cell, never once per glyph pair.
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

	PointQuery : U64, U64 -> [Present(TableAatAnchor.Point), Absent]
	Context : { vertical : Bool, backward : Bool, kern_mask : U64, budget : U64, point : PointQuery }
	Initial : { advances : List(I64), major : List(I64), cross : List(I64) }
	Applied : { items : List(LayoutGsub.Item), advances : List(I64), major : List(I64), cross : List(I64), operations : U64, stopped : U64 }
	Run : { items : List(LayoutGsub.Item), advances : List(I64), major : List(I64), cross : List(I64), parents : List(U64), attachments : List(U8), attachment_active : Bool, operations : U64, stopped : U64 }

	apply : TableAatKern, TableAatAnchor, List(LayoutGsub.Item), Initial, Context -> Applied
	apply = |table, anchors, items, initial, context| {
		count = items.len()
		var $run = { items, advances: initial.advances, major: initial.major, cross: initial.cross, parents: List.repeat(0.U64, count), attachments: List.repeat(0.U8, count), attachment_active: False, operations: 0, stopped: 0 }
		var $cross_seen = False
		for sub in table.subtables {
			if sub.vertical == context.vertical and (sub.extended or !sub.variation) and TableAatKern.intersects(table, sub, $run.items) {
				if !$cross_seen and sub.cross {
					$cross_seen = True
					var $parents = $run.parents
					for i in 0..<count {
						parent = i.to_i64_wrap() + (if (context.backward) 1 else -1)
						$parents = $parents.set(i, if (parent >= 0 and parent < count.to_i64_wrap()) parent.to_u64_wrap() + 1 else 0) ?? []
					}
					$run = { ..$run, parents: $parents, attachments: List.repeat(2.U8, count) }
				}
				reverse = sub.backwards != context.backward
				if sub.kind == 1 or sub.kind == 4 {
					if context.kern_mask != 0 or sub.cross or sub.kind == 4 {
						$run = TableAatKern.apply_machine(table, anchors, sub, $run, context, reverse)
					}
				} else if context.kern_mask != 0 and !sub.backwards and (sub.kind == 0 or sub.kind == 2 or sub.kind == 3 or sub.kind == 6) {
					$run = TableAatKern.apply_pairs(table, sub, $run, context, reverse)
				}
				if $run.stopped != 0 {
					break
				}
			}
		}
		resolved = TableAatKern.resolve($run, context.backward)
		{ items: resolved.items, advances: resolved.advances, major: resolved.major, cross: resolved.cross, operations: resolved.operations, stopped: resolved.stopped }
	}

	initiates : Sub, AatState.Entry -> Bool
	initiates = |_sub, entry| entry.flags.bitwise_and(0x8000) != 0
	actionable : Sub, AatState.Entry -> Bool
	actionable = |sub, entry| if (sub.extended) entry.a != 65535 else entry.flags.bitwise_and(0x3FFF) != 0

	intersects : TableAatKern, Sub, List(LayoutGsub.Item) -> Bool
	intersects = |table, sub, items| {
		if sub.kind == 0 {
			for item in items {
				var $low = 0
				var $high = sub.count
				while $low < $high {
					mid = $low + ($high - $low) // 2
					pair = table.pairs.get(sub.start + mid) ?? { key: 0, value: 0 }
					left = pair.key // 65536
					if left == item.glyph {
						return True
					}
					if left < item.glyph {
						$low = mid + 1
					} else {
						$high = mid
					}
				}
			}
		} else if sub.kind == 2 or sub.kind == 6 {
			lookup = table.lookups.get(sub.left) ?? AatLookup.empty
			for item in items {
				match AatLookup.get(lookup, item.glyph) {
					Found(_) => return True
					Missing => {}
				}
			}
		} else if sub.kind == 3 {
			return sub.count > 0 and !items.is_empty()
		} else if sub.kind == 1 or sub.kind == 4 {
			machine = table.states.get(sub.machine) ?? crash "validated AAT state index"
			lookup = AatState.class_lookup(machine)
			columns = AatState.column_count(machine)
			for item in items {
				found = if item.glyph == 65535 and columns <= 512 {
					Known(2.U64)
				} else match AatLookup.get(lookup, item.glyph) {
					Found(c) => Known(c.to_u64())
					Missing => Unknown
				}
				match found {
					Known(class) => {
						if columns > 512 {
							return True
						}
						entry = AatState.entry(machine, 0, class)
						if entry.next != 0 or TableAatKern.initiates(sub, entry) or TableAatKern.actionable(sub, entry) {
							return True
						}
					}
					Unknown => {}
				}
			}
		}
		False
	}

	physical : U64, U64, Bool -> U64
	physical = |index, count, reverse| if (reverse and index < count) count - 1 - index else index

	# Destructure before the helper consumes items. Keeping the old Run
	# in a record-spread expression aliases the complete glyph list and
	# copies it once per state action when setting unsafe-break flags.
	flag_run : Run, U64, U64 -> Run
	flag_run = |run, start, end| {
		{ items, advances, major, cross, parents, attachments, attachment_active, operations, stopped } = run
		flagged = TableAatKern.unsafe_range(items, start, end)
		{ items: flagged, advances, major, cross, parents, attachments, attachment_active, operations, stopped }
	}
	unsafe_range : List(LayoutGsub.Item), U64, U64 -> List(LayoutGsub.Item)
	unsafe_range = |items, start, end| {
		if end < start or end - start > 255 or end > items.len() {
			items
		} else LayoutGsub.flag_range(items, start, end, LayoutGsub.min_cluster(items, start, end, 0xFFFFFFFFFFFFFFFF))
	}

	apply_pairs : TableAatKern, Sub, Run, Context, Bool -> Run
	apply_pairs = |table, sub, run, context, reverse| {
		{ items, advances, major, cross, parents, attachments, attachment_active, operations, stopped } = run
		var $items = items
		var $advances = advances
		var $major = major
		var $cross = cross
		var $active = attachment_active
		var $operations = operations
		count = items.len()
		var $i = 0
		while $i < count {
			if $operations >= context.budget {
				return { items: $items, advances: $advances, major: $major, cross: $cross, parents, attachments, attachment_active: $active, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			i = TableAatKern.physical($i, count, reverse)
			first = $items.get(i) ?? LayoutGsub.no_item
			if !LayoutGsub.applies(first.mask, context.kern_mask) {
				$i = $i + 1
			} else {
				var $j = $i + 1
				var $found = False
				var $searching = True
				while $j < count and $searching {
					item = $items.get(TableAatKern.physical($j, count, reverse)) ?? LayoutGsub.no_item
					if LayoutGsub.is_mark_item(item) or LayoutGsub.is_default_ignorable(item) {
						$j = $j + 1
					} else {
						$found = LayoutGsub.applies(item.mask, context.kern_mask)
						$searching = False
					}
				}
				if $found {
					j = TableAatKern.physical($j, count, reverse)
					second = $items.get(j) ?? LayoutGsub.no_item
					match TableAatKern.pair_value(table, sub, first.glyph, second.glyph) {
						Value(value) if value != 0 => {
							if sub.cross {
								$cross = $cross.set(j, value) ?? []
								$active = True
							} else {
								left = value.shr_wrap(1)
								right = value - left
								$advances = $advances.set(i, LayoutVar.position_add($advances.get(i) ?? 0, left)) ?? []
								$advances = $advances.set(j, LayoutVar.position_add($advances.get(j) ?? 0, right)) ?? []
								$major = $major.set(j, LayoutVar.position_add($major.get(j) ?? 0, right)) ?? []
							}
							$items = TableAatKern.unsafe_range($items, i.min(j), i.max(j) + 1)
						}
						_ => {}
					}
					$i = $j
				} else {
					$i = if ($j < count) $j + 1 else count
				}
			}
		}
		{ items: $items, advances: $advances, major: $major, cross: $cross, parents, attachments, attachment_active: $active, operations: $operations, stopped }
	}

	apply_machine : TableAatKern, TableAatAnchor, Sub, Run, Context, Bool -> Run
	apply_machine = |table, anchors, sub, run, context, reverse| {
		machine = table.states.get(sub.machine) ?? crash "validated AAT state index"
		count = run.items.len()
		var $run = run
		var $state = 0
		var $cursor = 0
		var $stack = List.with_capacity(8)
		var $mark = count
		while $cursor <= count {
			if $run.operations >= context.budget {
				return { ..$run, stopped: 2 }
			}
			$run = { ..$run, operations: $run.operations + 1 }
			index = TableAatKern.physical($cursor, count, reverse)
			class = if ($cursor == count) 0 else AatState.class(machine, ($run.items.get(index) ?? LayoutGsub.no_item).glyph)
			entry = AatState.entry(machine, $state, class)
			from_start = AatState.entry(machine, 0, class)
			before_end = AatState.entry(machine, $state, 0)
			dont_advance = entry.flags.bitwise_and(0x4000) != 0
			safe = !TableAatKern.actionable(sub, entry) and ($state == 0 or (dont_advance and entry.next == 0) or (!TableAatKern.actionable(sub, from_start) and entry.next == from_start.next and dont_advance == (from_start.flags.bitwise_and(0x4000) != 0))) and !TableAatKern.actionable(sub, before_end)
			if !safe and $cursor > 0 and $cursor < count {
				previous = TableAatKern.physical($cursor - 1, count, reverse)
				$run = TableAatKern.flag_run($run, previous.min(index), previous.max(index) + 1)
			}
			if sub.kind == 1 {
				if sub.extended and entry.flags.bitwise_and(0x2000) != 0 {
					$stack = $stack.clear()
				}
				if entry.flags.bitwise_and(0x8000) != 0 {
					if $stack.len() < 8 {
						$stack = $stack.append(index)
					} else {
						$stack = $stack.clear()
					}
				}
				if TableAatKern.actionable(sub, entry) and !$stack.is_empty() {
					stride = sub.tuples.max(1) * 2
					encoded = if (sub.extended) sub.action + entry.a else sub.array + entry.flags.bitwise_and(0x3FFF)
					# Legacy action offsets floor relative to the value array.
					action = sub.action + (encoded - sub.action) // 2 * 2
					if !Bytes.fits(action, $stack.len() * stride, sub.end) {
						$stack = $stack.clear()
					} else {
						var $action = action
						var $last = False
						while !$last and !$stack.is_empty() {
							if $run.operations >= context.budget {
								return { ..$run, stopped: 2 }
							}
							$run = { ..$run, operations: $run.operations + 1 }
							at = $stack.last() ?? count
							$stack = $stack.drop_last(1)
							raw = Bytes.i16(table.bytes, $action)
							$action = $action + stride
							if at < count {
								$last = raw.bitwise_and(1) != 0
								value = raw.bitwise_and(-2)
								if sub.cross {
									if value == -32768 {
										$run = { ..$run, cross: $run.cross.set(at, 0) ?? [], parents: $run.parents.set(at, 0) ?? [], attachments: $run.attachments.set(at, 0) ?? [] }
									} else if ($run.attachments.get(at) ?? 0) != 0 {
										$run = { ..$run, cross: $run.cross.set(at, LayoutVar.position_add($run.cross.get(at) ?? 0, value)) ?? [], attachment_active: True }
									}
								} else if LayoutGsub.applies(($run.items.get(at) ?? LayoutGsub.no_item).mask, context.kern_mask) {
									$run = { ..$run, advances: $run.advances.set(at, LayoutVar.position_add($run.advances.get(at) ?? 0, value)) ?? [], major: $run.major.set(at, LayoutVar.position_add($run.major.get(at) ?? 0, value)) ?? [] }
								}
							}
						}
					}
				}
			} else {
				if $mark < count and entry.a != 65535 and index < count {
					$run = TableAatKern.attach(table, anchors, sub, $run, context, entry.a, $mark, index)
				}
				if entry.flags.bitwise_and(0x8000) != 0 {
					$mark = index
				}
			}
			$state = entry.next
			if $cursor == count {
				break
			}
			if !dont_advance {
				$cursor = $cursor + 1
			}
		}
		$run
	}

	attach : TableAatKern, TableAatAnchor, Sub, Run, Context, U64, U64, U64 -> Run
	attach = |table, anchors, sub, run, context, action, mark, current| {
		at = sub.action + action * (if (sub.action_type == 2) 8 else 4)
		mark_glyph = (run.items.get(mark) ?? LayoutGsub.no_item).glyph
		current_glyph = (run.items.get(current) ?? LayoutGsub.no_item).glyph
		pair = if sub.action_type == 2 {
			{ first: { x: Bytes.i16(table.bytes, at).to_i32_wrap(), y: Bytes.i16(table.bytes, at + 2).to_i32_wrap() }, second: { x: Bytes.i16(table.bytes, at + 4).to_i32_wrap(), y: Bytes.i16(table.bytes, at + 6).to_i32_wrap() } }
		} else {
			first_index = Bytes.u16(table.bytes, at)
			second_index = Bytes.u16(table.bytes, at + 2)
			point_of = context.point
			first = if (sub.action_type == 0) point_of(mark_glyph, first_index) else TableAatAnchor.anchor(anchors, mark_glyph, first_index)
			second = if (sub.action_type == 0) point_of(current_glyph, second_index) else TableAatAnchor.anchor(anchors, current_glyph, second_index)
			match (first, second) {
				(Present(a), Present(b)) => { first: a, second: b }
				_ => return run
			}
		}
		x = LayoutVar.position_sub(pair.first.x.to_i64(), pair.second.x.to_i64())
		y = LayoutVar.position_sub(pair.first.y.to_i64(), pair.second.y.to_i64())
		distance = (mark.to_i64_wrap() - current.to_i64_wrap()).to_i16_wrap().to_i64()
		parent = current.to_i64_wrap() + distance
		link = if (distance != 0 and parent >= 0 and parent < run.items.len().to_i64_wrap()) parent.to_u64_wrap() + 1 else 0
		{ ..run, major: run.major.set(current, if (context.vertical) y else x) ?? [], cross: run.cross.set(current, if (context.vertical) x else y) ?? [], parents: run.parents.set(current, link) ?? [], attachments: run.attachments.set(current, 1) ?? [], attachment_active: True }
	}

	resolve : Run, Bool -> Run
	resolve = |run, backward| {
		if !run.attachment_active {
			return run
		}
		# The reference propagates parent cross offsets for cursive edges;
		# mark edges propagate only the flow-axis offset. AAT format4 leaves
		# its cross-axis anchor difference unchanged at this final phase.
		state = { items: run.items, ax: run.advances, dx: run.major, dy: run.cross, parents: run.parents, attachments: run.attachments, stopped: run.stopped, operations: run.operations }
		resolved = LayoutPosition.resolve(state, backward)
		{ ..run, advances: resolved.ax, major: resolved.dx, cross: resolved.dy, parents: resolved.parents }
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
	Ok(t) => TableAatKern.has_data(t)
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

aat_runtime_context : TableAatKern.Context
aat_runtime_context = { vertical: False, backward: False, kern_mask: 16, budget: 65536, point: |_g, _i| Absent }

aat_runtime_items : List(LayoutGsub.Item)
aat_runtime_items = [{ glyph: 1, cluster: 0, mask: 16, props: 0 }, { glyph: 2, cluster: 1, mask: 16, props: 0 }]
expect match TableAatKern.read_kerx(aat_pair_table, 3) {
	Ok(t) => {
		r = TableAatKern.apply(t, TableAatAnchor.none, aat_runtime_items, { advances: [510, 520], major: [0, 0], cross: [0, 0] }, aat_runtime_context)
		r.advances == [485, 495] and r.major == [0, -25] and r.cross == [0, 0] and r.stopped == 0
	}
	Err(_) => False
}
expect match TableAatKern.read_kerx(aat_pair_table, 3) {
	Ok(t) => {
		r = TableAatKern.apply(t, TableAatAnchor.none, aat_runtime_items, { advances: [510, 520], major: [0, 0], cross: [0, 0] }, { ..aat_runtime_context, backward: True })
		r.advances == [510, 520] and r.major == [0, 0]
	}
	Err(_) => False
}
expect match TableAatKern.read_kerx(aat_pair_table, 3) {
	Ok(t) => TableAatKern.apply(t, TableAatAnchor.none, aat_runtime_items, { advances: [510, 520], major: [0, 0], cross: [0, 0] }, { ..aat_runtime_context, budget: 0 }).stopped == 2
	Err(_) => False
}

expect match TableAatKern.read_kern([0, 0, 0, 0], 3) {
	Ok(t) => !TableAatKern.has_data(t)
	Err(_) => False
}
expect {
	bytes = aat_pair_table.take_first(12).concat([0, 0, 1, 0]).concat(aat_pair_table.drop_first(16))
	match TableAatKern.read_kerx(bytes, 3) {
		Err(ps) => ps.any(|p| p.offset == 12)
		Ok(_) => False
	}
}
expect {
	bytes = aat_pair_table.take_first(28).concat([0, 0, 0, 1]).concat(aat_pair_table.drop_first(32))
	match TableAatKern.read_kerx(bytes, 3) {
		Err(ps) => ps.any(|p| p.offset == 28)
		Ok(_) => False
	}
}
