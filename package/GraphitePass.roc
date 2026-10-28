import Bytes

## Checked Graphite finite-state pass views. Scalar offsets address the
## shared Silf bytes; no transition/rule table is copied or sorted.
GraphitePass :: {}.{

	Pass : {
		programs : U64,
		flags : U64,
		max_loop : U64,
		max_context : U64,
		max_backup : U64,
		rule_count : U64,
		rows : U64,
		transitional : U64,
		success : U64,
		columns : U64,
		ranges : U64,
		range_count : U64,
		rule_map_offsets : U64,
		rule_map : U64,
		min_pre : U64,
		max_pre : U64,
		starts : U64,
		sort_keys : U64,
		pre_contexts : U64,
		collision_threshold : U64,
		constraint_ends : U64,
		constraint_offsets : U64,
		action_offsets : U64,
		transitions : U64,
		pass_constraint : U64,
		pass_constraint_end : U64,
		constraints : U64,
		actions : U64,
		end : U64,
	}

	read : List(U8), U64, U64, U64, U64, U64 -> Try({ pass : Pass, endings : List(U64) }, [Bad(U64)])
	read = |bytes, start, end, subtable, version, max_glyph| {
		if end > bytes.len() or !Bytes.fits(start, 24, end) {
			return Err(Bad(start))
		}
		rules = Bytes.u16(bytes, start + 4)
		fsm = start + (if (version >= 0x00030000) Bytes.u16(bytes, start + 6) else 24)
		if fsm < start + 24 or !Bytes.fits(fsm, 16, end) {
			return Err(Bad(start + 6))
		}
		rows = Bytes.u16(bytes, fsm)
		transitional = Bytes.u16(bytes, fsm + 2)
		success = Bytes.u16(bytes, fsm + 4)
		columns = Bytes.u16(bytes, fsm + 6)
		range_count = Bytes.u16(bytes, fsm + 8)
		if transitional > rows or success > rows or transitional + success < rows {
			return Err(Bad(fsm))
		}
		ranges = fsm + 16
		if !Bytes.fits(ranges, range_count * 6, end) {
			return Err(Bad(fsm + 8))
		}
		var $previous = 0
		for i in 0..<range_count {
			at = ranges + 6 * i
			first = Bytes.u16(bytes, at)
			last = Bytes.u16(bytes, at + 2)
			if first > last or last > max_glyph or (i != 0 and first <= $previous) or Bytes.u16(bytes, at + 4) >= columns {
				return Err(Bad(at))
			}
			$previous = last
		}
		rule_map_offsets = ranges + 6 * range_count
		if !Bytes.fits(rule_map_offsets, 2 * (success + 1), end) {
			return Err(Bad(rule_map_offsets))
		}
		var $map_count = 0
		for i in 0..<(success + 1) {
			next = Bytes.u16(bytes, rule_map_offsets + 2 * i)
			if next < $map_count {
				return Err(Bad(rule_map_offsets + 2 * i))
			}
			$map_count = next
		}
		rule_map = rule_map_offsets + 2 * (success + 1)
		if !Bytes.fits(rule_map, $map_count * 2 + 2, end) {
			return Err(Bad(rule_map))
		}
		for i in 0..<$map_count {
			if Bytes.u16(bytes, rule_map + 2 * i) >= rules {
				return Err(Bad(rule_map + 2 * i))
			}
		}
		pre = rule_map + $map_count * 2
		min_pre = Bytes.u8(bytes, pre)
		max_pre = Bytes.u8(bytes, pre + 1)
		if max_pre < min_pre {
			return Err(Bad(pre))
		}
		starts = pre + 2
		start_count = max_pre - min_pre + 1
		if !Bytes.fits(starts, start_count * 2, end) {
			return Err(Bad(starts))
		}
		for i in 0..<start_count {
			if Bytes.u16(bytes, starts + 2 * i) >= rows and rows != 0 {
				return Err(Bad(starts + 2 * i))
			}
		}
		sort_keys = starts + start_count * 2
		pre_contexts = sort_keys + rules * 2
		lengths = pre_contexts + rules
		if !Bytes.fits(sort_keys, rules * 3 + 3, end) {
			return Err(Bad(sort_keys))
		}
		for i in 0..<rules {
			if Bytes.u8(bytes, pre_contexts + i) < min_pre or Bytes.u8(bytes, pre_contexts + i) > max_pre {
				return Err(Bad(pre_contexts + i))
			}
		}
		pass_length = Bytes.u16(bytes, lengths + 1)
		constraint_offsets = lengths + 3
		action_offsets = constraint_offsets + (rules + 1) * 2
		transitions = action_offsets + (rules + 1) * 2
		if !Bytes.fits(constraint_offsets, (rules + 1) * 4 + transitional * columns * 2 + 1, end) {
			return Err(Bad(constraint_offsets))
		}
		for i in 0..<(transitional * columns) {
			if Bytes.u16(bytes, transitions + i * 2) >= rows {
				return Err(Bad(transitions + i * 2))
			}
		}
		pass_constraint = subtable + Bytes.u32(bytes, start + 8)
		constraints = subtable + Bytes.u32(bytes, start + 12)
		actions = subtable + Bytes.u32(bytes, start + 16)
		minimum_code = transitions + transitional * columns * 2 + 1
		if pass_constraint < minimum_code or !Bytes.fits(pass_constraint, pass_length, end) or constraints < pass_constraint + pass_length or actions < constraints or actions > end {
			return Err(Bad(start + 8))
		}
		var $last_constraint = 0
		var $last_action = 0
		for i in 0..<(rules + 1) {
			c = Bytes.u16(bytes, constraint_offsets + 2 * i)
			a = Bytes.u16(bytes, action_offsets + 2 * i)
			if (c != 0 and c < $last_constraint) or !Bytes.fits(constraints, c, actions) {
				return Err(Bad(constraint_offsets + 2 * i))
			}
			if a < $last_action or !Bytes.fits(actions, a, end) {
				return Err(Bad(action_offsets + 2 * i))
			}
			$last_constraint = if (c != 0) c else $last_constraint
			$last_action = a
		}
		if Bytes.u16(bytes, constraint_offsets + 2 * rules) < $last_constraint {
			return Err(Bad(constraint_offsets + 2 * rules))
		}
		var $endings = List.repeat(0.U64, rules)
		var $next = Bytes.u16(bytes, constraint_offsets + 2 * rules)
		var $i = rules
		while $i > 0 {
			$i = $i - 1
			current = Bytes.u16(bytes, constraint_offsets + 2 * $i)
			$endings = $endings.set($i, $next) ?? []
			if current != 0 {
				$next = current
			}
		}
		Ok({ endings: $endings, pass: { programs: 0, constraint_ends: 0, flags: Bytes.u8(bytes, start), max_loop: Bytes.u8(bytes, start + 1), max_context: Bytes.u8(bytes, start + 2), max_backup: Bytes.u8(bytes, start + 3), rule_count: rules, rows, transitional, success, columns, ranges, range_count, rule_map_offsets, rule_map, min_pre, max_pre, starts, sort_keys, pre_contexts, collision_threshold: Bytes.u8(bytes, lengths), constraint_offsets, action_offsets, transitions, pass_constraint, pass_constraint_end: pass_constraint + pass_length, constraints, actions, end } })
	}

	column : List(U8), Pass, U64 -> [Found(U64), Missing]
	column = |bytes, pass, glyph| {
		var $lo = 0
		var $hi = pass.range_count
		while $lo < $hi {
			mid = $lo + ($hi - $lo) // 2
			at = pass.ranges + 6 * mid
			if glyph < Bytes.u16(bytes, at) {
				$hi = mid
			} else if glyph > Bytes.u16(bytes, at + 2) {
				$lo = mid + 1
			} else {
				return Found(Bytes.u16(bytes, at + 4))
			}
		}
		Missing
	}

	transition : List(U8), Pass, U64, U64 -> U64
	transition = |bytes, pass, row, col| if (row < pass.transitional and col < pass.columns) Bytes.u16(bytes, pass.transitions + 2 * (row * pass.columns + col)) else 0

	rules : List(U8), Pass, U64 -> { start : U64, end : U64 }
	rules = |bytes, pass, state| {
		if state >= pass.rows or state < pass.rows - pass.success {
			return { start: 0, end: 0 }
		}
		index = state - (pass.rows - pass.success)
		{ start: Bytes.u16(bytes, pass.rule_map_offsets + 2 * index), end: Bytes.u16(bytes, pass.rule_map_offsets + 2 * (index + 1)) }
	}

	code : List(U8), List(U64), Pass, U64, Bool -> { start : U64, end : U64 }
	code = |bytes, endings, pass, rule, constraint| {
		if rule >= pass.rule_count {
			return { start: 0, end: 0 }
		}
		offsets = if (constraint) pass.constraint_offsets else pass.action_offsets
		base = if (constraint) pass.constraints else pass.actions
		start = Bytes.u16(bytes, offsets + rule * 2)
		if constraint and start == 0 {
			return { start: base, end: base }
		}
		{ start: base + start, end: base + (if (constraint) endings.get(pass.constraint_ends + rule) ?? start else Bytes.u16(bytes, offsets + (rule + 1) * 2)) }
	}
}

expect GraphitePass.read([], 0, 0, 0, 0x00030000, 1).is_err()

# Original single-rule pass, independently accepted by Graphite2 1.3.14.
fixture = [0, 10, 1, 0, 0, 1, 0, 24, 0, 0, 0, 73, 0, 0, 0, 73, 0, 0, 0, 73, 0, 0, 0, 0, 0, 2, 0, 1, 0, 1, 0, 1, 0, 1, 0, 6, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 1, 0, 28, 0, 25, 49]
expect {
	match GraphitePass.read(fixture, 0, fixture.len(), 0, 0x00030000, 2) {
		Ok(prepared) => {
			p = prepared.pass
			GraphitePass.column(fixture, p, 1) == Found(0) and GraphitePass.column(fixture, p, 2) == Missing and GraphitePass.transition(fixture, p, 0, 0) == 1 and GraphitePass.rules(fixture, p, 1) == { start: 0, end: 1 } and GraphitePass.code(fixture, prepared.endings, p, 0, False) == { start: 73, end: 77 }
		}
		Err(_) => False
	}
}
expect GraphitePass.read(fixture.drop_last(1), 0, fixture.len() - 1, 0, 0x00030000, 2).is_err()
