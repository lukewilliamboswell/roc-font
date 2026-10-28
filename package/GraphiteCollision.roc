import GraphiteSlots
import TableGraphite
import GraphiteSilf
import GraphiteAttributes
import TableVar
import Bytes

## Original Graphite collision state. The selected rendering description
## controls whether collision attributes exist; glyph attributes provide
## their documented initial values, independently of the Glat box format.
GraphiteCollision :: {}.{

	Context : { table : TableGraphite, sub : GraphiteSilf.Subtable, rtl : Bool }
	Applied : { state : GraphiteSlots, operations : U64, stopped : U64 }
	Interval : { low : U32, high : U32, hard : Bool, a : U32, b : U32, c : U32 }
	Piece : { low : U32, high : U32, a : U32, b : U32, c : U32 }
	AxisResult : { best : [Present({ value : U32, cost : U32 }), Absent], operations : U64, stopped : U64 }
	Octabox : { x_min : U32, y_min : U32, x_max : U32, y_max : U32, sum_min : U32, sum_max : U32, diff_min : U32, diff_max : U32 }
	Rect : { x_min : U32, y_min : U32, x_max : U32, y_max : U32 }
	Projection : { low : U32, high : U32, gap : U32, inside : Bool }
	ShiftResult : { x : U32, y : U32, feasible : Bool, operations : U64, stopped : U64 }
	Group : { first : U64, last : U64 }
	Groups : { groups : List(Group), operations : U64, stopped : U64 }

	# START records the start of a following group; END closes the current
	# one. They can deliberately overlap. An END on the first slot does not
	# create a singleton boundary. The scan cursor always advances, including
	# when a just-closed group is also the start of the next group.
	groups : GraphiteSlots, Bool, U64 -> Groups
	groups = |state, reverse, budget| {
		var $id = if (reverse) state.last else state.first
		final = if (reverse) state.first else state.last
		var $start = $id
		var $next_start = 0
		var $last_end = 0
		var $operations = 0
		var $walked = 0
		var $groups = []
		while $id != 0 and $walked < state.active {
			if $operations >= budget {
				return { groups: $groups, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			$walked = $walked + 1
			slot = GraphiteSlots.get(state, $id)
			next = if (reverse) slot.previous else slot.next
			flags = GraphiteSlots.get_extra(state, $id, 3)
			if flags.bitwise_and(4) != 0 {
				$next_start = $id
			}
			if flags.bitwise_and(8) != 0 and $id != $start {
				$groups = $groups.append({ first: $start, last: $id })
				$last_end = $id
				$start = if ($next_start != 0) $next_start else next
				$next_start = 0
			}
			$id = next
		}
		if $start != 0 and $last_end != final {
			$groups = $groups.append({ first: $start, last: final })
		}
		{ groups: $groups, operations: $operations, stopped: 0 }
	}

	# Solve a movable glyph's four directional slices. Obstacle octagons
	# are already expressed as forbidden translations of this glyph, so
	# this phase is independent of font parsing, slot order and VM actions.
	solve_shift : Rect, U32, U32, List(Octabox), U32, U32, U64 -> ShiftResult
	solve_shift = |limits, current_x, current_y, obstacles, margin, weight, budget| {
		if !TableVar.f32_lt(limits.x_min, limits.x_max) or !TableVar.f32_lt(limits.y_min, limits.y_max) {
			return { x: current_x, y: current_y, feasible: True, operations: 0, stopped: 0 }
		}
		var $operations = 0
		var $constraints = []
		var $best = Absent
		for axis in 0..<4 {
			$constraints = $constraints.clear()
			for obstacle in obstacles {
				if $operations >= budget {
					return { x: current_x, y: current_y, feasible: False, operations: $operations, stopped: 2 }
				}
				$operations = $operations + 1
				projection = GraphiteCollision.project(obstacle, axis, current_x, current_y)
				$constraints = GraphiteCollision.add_projected($constraints, projection, axis, margin, weight)
			}
			bounds = GraphiteCollision.axis_limits(limits, axis, current_x, current_y)
			solved = GraphiteCollision.solve_axis(bounds.low, bounds.high, bounds.constant, bounds.coefficient, $constraints, budget - $operations)
			$operations = $operations + solved.operations
			if solved.stopped != 0 {
				return { x: current_x, y: current_y, feasible: False, operations: $operations, stopped: solved.stopped }
			}
			match solved.best {
				Absent => {}
				Present(candidate) => {
					better = match $best {
						Absent => True
						Present(previous) => TableVar.f32_lt(candidate.cost, previous.cost)
					}
					if better {
						point = match axis {
							0 => { x: candidate.value, y: current_y }
							1 => { x: current_x, y: candidate.value }
							2 => {
								old = TableVar.f32_add(current_x, current_y)
								delta = TableVar.f32_mul(TableVar.f32_sub(candidate.value, old), TableVar.f32_half)
								{ x: TableVar.f32_add(current_x, delta), y: TableVar.f32_add(current_y, delta) }
							}
							_ => {
								old = TableVar.f32_sub(current_x, current_y)
								delta = TableVar.f32_mul(TableVar.f32_sub(candidate.value, old), TableVar.f32_half)
								{ x: TableVar.f32_add(current_x, delta), y: TableVar.f32_sub(current_y, delta) }
							}
						}
						$best = Present({ x: point.x, y: point.y, cost: candidate.cost })
					}
					{}
				}
			}
		}
		match $best {
			Absent => { x: current_x, y: current_y, feasible: False, operations: $operations, stopped: 0 }
			Present(best) => { x: best.x, y: best.y, feasible: True, operations: $operations, stopped: 0 }
		}
	}

	# Glat's byte coordinates are normalized against the complete glyph's
	# bounding box, including the diagonal coordinates of a sub-box. The
	# multiply followed by divide keeps the reference's binary32 rounding.
	coordinate : U32, U32, U64 -> U32
	coordinate = |minimum, span, byte| TableVar.f32_add(minimum, TableVar.f32_div(TableVar.f32_mul(span, TableVar.f32_from_int(byte.to_i64_wrap())), TableVar.f32_from_int(255)))

	# Part zero is the complete glyph. Parts 1..N follow the checked bitmap
	# in ascending bit order. An absent part is explicitly absent geometry.
	load_box : GraphiteAttributes, U64, U64, (U64, U64, I32 -> I32) -> [Present(Octabox), Absent]
	load_box = |attributes, glyph, part, base_metric| {
		start = match attributes.box_starts.get(glyph) {
			Err(_) => return Absent
			Ok(at) => at
		}
		x_min = TableVar.f32_from_int(base_metric(glyph, 4, 0).to_i64())
		x_max = TableVar.f32_from_int(base_metric(glyph, 5, 0).to_i64())
		y_min = TableVar.f32_from_int(base_metric(glyph, 3, 0).to_i64())
		y_max = TableVar.f32_from_int(base_metric(glyph, 2, 0).to_i64())
		x_span = TableVar.f32_sub(x_max, x_min)
		y_span = TableVar.f32_sub(y_max, y_min)
		sum_base = TableVar.f32_add(x_min, y_min)
		diff_base = TableVar.f32_sub(x_min, y_max)
		diagonal_span = TableVar.f32_add(x_span, y_span)
		var $at = start + 2
		var $x_min = x_min
		var $x_max = x_max
		var $y_min = y_min
		var $y_max = y_max
		if part != 0 {
			bitmap = Bytes.u16(attributes.bytes, start)
			var $count = 0
			for bit in 0..<16 {
				if bitmap.bitwise_and((1.U64).shl_wrap(bit.to_u8_wrap())) != 0 {
					$count = $count + 1
				}
			}
			if part > $count {
				return Absent
			}
			at = start + 6 + 8 * (part - 1)
			$x_min = GraphiteCollision.coordinate(x_min, x_span, Bytes.u8(attributes.bytes, at))
			$x_max = GraphiteCollision.coordinate(x_min, x_span, Bytes.u8(attributes.bytes, at + 1))
			$y_min = GraphiteCollision.coordinate(y_min, y_span, Bytes.u8(attributes.bytes, at + 2))
			$y_max = GraphiteCollision.coordinate(y_min, y_span, Bytes.u8(attributes.bytes, at + 3))
			$at = at + 4
		}
		Present({ x_min: $x_min, y_min: $y_min, x_max: $x_max, y_max: $y_max, sum_min: GraphiteCollision.coordinate(sum_base, diagonal_span, Bytes.u8(attributes.bytes, $at)), sum_max: GraphiteCollision.coordinate(sum_base, diagonal_span, Bytes.u8(attributes.bytes, $at + 1)), diff_min: GraphiteCollision.coordinate(diff_base, diagonal_span, Bytes.u8(attributes.bytes, $at + 2)), diff_max: GraphiteCollision.coordinate(diff_base, diagonal_span, Bytes.u8(attributes.bytes, $at + 3)) })
	}

	# The forbidden translation is the Minkowski difference of two octagons
	# with the same four edge normals. dx/dy locate the target's unshifted
	# origin relative to the already shifted obstacle.
	forbidden : Octabox, Octabox, U32, U32 -> Octabox
	forbidden = |target, obstacle, dx, dy| {
		sum = TableVar.f32_add(dx, dy)
		diff = TableVar.f32_sub(dx, dy)
		{
			x_min: TableVar.f32_sub(TableVar.f32_sub(obstacle.x_min, target.x_max), dx),
			x_max: TableVar.f32_sub(TableVar.f32_sub(obstacle.x_max, target.x_min), dx),
			y_min: TableVar.f32_sub(TableVar.f32_sub(obstacle.y_min, target.y_max), dy),
			y_max: TableVar.f32_sub(TableVar.f32_sub(obstacle.y_max, target.y_min), dy),
			sum_min: TableVar.f32_sub(TableVar.f32_sub(obstacle.sum_min, target.sum_max), sum),
			sum_max: TableVar.f32_sub(TableVar.f32_sub(obstacle.sum_max, target.sum_min), sum),
			diff_min: TableVar.f32_sub(TableVar.f32_sub(obstacle.diff_min, target.diff_max), diff),
			diff_max: TableVar.f32_sub(TableVar.f32_sub(obstacle.diff_max, target.diff_min), diff),
		}
	}

	# Slice along X, Y, X+Y or X-Y, holding the orthogonal coordinate at
	# the current offset. For a margin-only near miss, project at the
	# nearest point in the orthogonal interval and retain the gap separately.
	project : Octabox, U64, U32, U32 -> Projection
	project = |box, axis, current_x, current_y| {
		n2 = TableVar.f32_from_int(2)
		orthogonal = match axis {
			0 => { value: current_y, low: box.y_min, high: box.y_max }
			1 => { value: current_x, low: box.x_min, high: box.x_max }
			2 => { value: TableVar.f32_sub(current_x, current_y), low: box.diff_min, high: box.diff_max }
			_ => { value: TableVar.f32_add(current_x, current_y), low: box.sum_min, high: box.sum_max }
		}
		orth = TableVar.f32_min(orthogonal.high, TableVar.f32_max(orthogonal.low, orthogonal.value))
		gap = TableVar.f32_max(TableVar.f32_sub(orthogonal.value, orth), TableVar.f32_sub(orth, orthogonal.value))
		limits = match axis {
			0 => { low: TableVar.f32_max(box.x_min, TableVar.f32_max(TableVar.f32_sub(box.sum_min, orth), TableVar.f32_add(box.diff_min, orth))), high: TableVar.f32_min(box.x_max, TableVar.f32_min(TableVar.f32_sub(box.sum_max, orth), TableVar.f32_add(box.diff_max, orth))) }
			1 => { low: TableVar.f32_max(box.y_min, TableVar.f32_max(TableVar.f32_sub(box.sum_min, orth), TableVar.f32_sub(orth, box.diff_max))), high: TableVar.f32_min(box.y_max, TableVar.f32_min(TableVar.f32_sub(box.sum_max, orth), TableVar.f32_sub(orth, box.diff_min))) }
			2 => { low: TableVar.f32_max(box.sum_min, TableVar.f32_max(TableVar.f32_sub(TableVar.f32_mul(n2, box.x_min), orth), TableVar.f32_add(TableVar.f32_mul(n2, box.y_min), orth))), high: TableVar.f32_min(box.sum_max, TableVar.f32_min(TableVar.f32_sub(TableVar.f32_mul(n2, box.x_max), orth), TableVar.f32_add(TableVar.f32_mul(n2, box.y_max), orth))) }
			_ => { low: TableVar.f32_max(box.diff_min, TableVar.f32_max(TableVar.f32_sub(TableVar.f32_mul(n2, box.x_min), orth), TableVar.f32_sub(orth, TableVar.f32_mul(n2, box.y_max)))), high: TableVar.f32_min(box.diff_max, TableVar.f32_min(TableVar.f32_sub(TableVar.f32_mul(n2, box.x_max), orth), TableVar.f32_sub(orth, TableVar.f32_mul(n2, box.y_min)))) }
		}
		{ low: limits.low, high: limits.high, gap: if (axis < 2) gap else TableVar.f32_mul(gap, 0x3F3504F3), inside: TableVar.f32_lt(orthogonal.low, orthogonal.value) and TableVar.f32_lt(orthogonal.value, orthogonal.high) }
	}

	add_projected : List(Interval), Projection, U64, U32, U32 -> List(Interval)
	add_projected = |pool, projection, axis, margin, weight| {
		if TableVar.f32_lt(projection.high, projection.low) {
			return pool
		}
		var $pool = pool
		if projection.inside and TableVar.f32_lt(projection.low, projection.high) {
			$pool = $pool.append({ low: projection.low, high: projection.high, hard: True, a: 0, b: 0, c: 0 })
		}
		if TableVar.f32_lt(projection.gap, margin) {
			remaining = TableVar.f32_sub(margin, projection.gap)
			padding = if (axis < 2) remaining else TableVar.f32_mul(remaining, 0x3FB504F3)
			low = TableVar.f32_sub(projection.low, padding)
			high = TableVar.f32_add(projection.high, padding)
			if projection.inside {
				coefficient = if (axis < 2) weight else TableVar.f32_mul(weight, 0x3E800000)
				$pool = $pool.append(GraphiteCollision.soft(low, projection.low, coefficient, low))
				$pool = $pool.append(GraphiteCollision.soft(projection.high, high, coefficient, high))
			} else {
				penalty = TableVar.f32_mul(weight, TableVar.f32_mul(remaining, remaining))
				$pool = $pool.append({ low, high, hard: False, a: 0, b: 0, c: if (axis < 2) penalty else TableVar.f32_mul(penalty, TableVar.f32_half) })
			}
		}
		$pool
	}

	axis_limits : Rect, U64, U32, U32 -> { low : U32, high : U32, constant : U32, coefficient : U32 }
	axis_limits = |limits, axis, current_x, current_y| {
		one = TableVar.f32_one
		two = TableVar.f32_from_int(2)
		match axis {
			0 => { low: limits.x_min, high: limits.x_max, constant: TableVar.f32_mul(current_y, current_y), coefficient: one }
			1 => { low: limits.y_min, high: limits.y_max, constant: TableVar.f32_mul(current_x, current_x), coefficient: one }
			2 => {
				orth = TableVar.f32_sub(current_x, current_y)
				{ low: TableVar.f32_max(TableVar.f32_sub(TableVar.f32_mul(two, limits.x_min), orth), TableVar.f32_add(TableVar.f32_mul(two, limits.y_min), orth)), high: TableVar.f32_min(TableVar.f32_sub(TableVar.f32_mul(two, limits.x_max), orth), TableVar.f32_add(TableVar.f32_mul(two, limits.y_max), orth)), constant: TableVar.f32_mul(TableVar.f32_mul(orth, orth), TableVar.f32_half), coefficient: TableVar.f32_half }
			}
			_ => {
				orth = TableVar.f32_add(current_x, current_y)
				{ low: TableVar.f32_max(TableVar.f32_sub(TableVar.f32_mul(two, limits.x_min), orth), TableVar.f32_sub(orth, TableVar.f32_mul(two, limits.y_max))), high: TableVar.f32_min(TableVar.f32_sub(TableVar.f32_mul(two, limits.x_max), orth), TableVar.f32_sub(orth, TableVar.f32_mul(two, limits.y_min))), constant: TableVar.f32_mul(TableVar.f32_mul(orth, orth), TableVar.f32_half), coefficient: TableVar.f32_half }
			}
		}
	}

	# An independently derived interval optimizer. Each permitted range has
	# cost a*x*x - 2*b*x + c. An obstacle removes an open interval; a margin
	# or sequencing region adds a quadratic only over its own interval.
	# Flat alternating buffers retain table order and avoid a recursive sort.
	solve_axis : U32, U32, U32, U32, List(Interval), U64 -> AxisResult
	solve_axis = |low, high, constant, coefficient, constraints, budget| {
		if !TableVar.f32_lt(low, high) {
			return { best: Absent, operations: 0, stopped: 0 }
		}
		var $ranges = [{ low, high, a: coefficient, b: 0, c: constant }]
		var $spare = []
		var $operations = 0
		for constraint in constraints {
			var $next = $spare.clear()
			for range in $ranges {
				if $operations >= budget {
					return { best: Absent, operations: $operations, stopped: 2 }
				}
				$operations = $operations + 1
				start = TableVar.f32_max(range.low, constraint.low)
				end = TableVar.f32_min(range.high, constraint.high)
				if !TableVar.f32_lt(start, end) {
					$next = $next.append(range)
				} else {
					if TableVar.f32_lt(range.low, start) {
						$next = $next.append({ ..range, high: start })
					}
					if !constraint.hard {
						$next = $next.append({ low: start, high: end, a: TableVar.f32_add(range.a, constraint.a), b: TableVar.f32_add(range.b, constraint.b), c: TableVar.f32_add(range.c, constraint.c) })
					}
					if TableVar.f32_lt(end, range.high) {
						$next = $next.append({ ..range, low: end })
					}
				}
			}
			$spare = $ranges
			$ranges = $next
		}
		var $best = Absent
		for range in $ranges {
			if $operations >= budget {
				return { best: $best, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			value = TableVar.f32_min(range.high, TableVar.f32_max(range.low, TableVar.f32_div(range.b, range.a)))
			linear = TableVar.f32_mul(TableVar.f32_mul(TableVar.f32_from_int(2), range.b), value)
			cost = TableVar.f32_add(TableVar.f32_sub(TableVar.f32_mul(range.a, TableVar.f32_mul(value, value)), linear), range.c)
			better = match $best {
				Absent => True
				Present(previous) => !TableVar.f32_lt(previous.cost, cost)
			}
			if better {
				$best = Present({ value, cost })
			}
		}
		{ best: $best, operations: $operations, stopped: 0 }
	}

	soft : U32, U32, U32, U32 -> Interval
	soft = |low, high, weight, preferred| { low, high, hard: False, a: weight, b: TableVar.f32_mul(weight, preferred), c: TableVar.f32_mul(weight, TableVar.f32_mul(preferred, preferred)) }

	# Order in the font's sixteen consecutive collision glyph attributes.
	# Offset coordinates are signed; flags, classes and weights are U16.
	defaults : List({ extra : U64, signed : Bool })
	defaults = [
		{ extra: 3, signed: False },
		{ extra: 4, signed: True },
		{ extra: 5, signed: True },
		{ extra: 6, signed: True },
		{ extra: 7, signed: True },
		{ extra: 10, signed: False },
		{ extra: 11, signed: False },
		{ extra: 15, signed: False },
		{ extra: 16, signed: False },
		{ extra: 17, signed: False },
		{ extra: 18, signed: True },
		{ extra: 19, signed: False },
		{ extra: 20, signed: True },
		{ extra: 21, signed: False },
		{ extra: 22, signed: False },
		{ extra: 23, signed: False },
	]

	prepare : GraphiteSlots, Context, U64 -> Applied
	prepare = |state, context, budget| {
		{ nodes, users, user_count, justification_levels, feature_changes, first, last, active, positioned, advance_x, advance_y } = state
		var $users = users
		var $id = first
		var $walked = 0
		var $operations = 0
		var $stopped = 0
		enabled = context.sub.flags.bitwise_and(32) != 0
		while $id != 0 and $walked < active {
			if $operations >= budget {
				$stopped = 2
				break
			}
			$operations = $operations + 1
			$walked = $walked + 1
			slot = nodes.get($id) ?? GraphiteSlots.no_slot
			$id = slot.next
			at = slot.user_start + user_count
			# Every initialized slot owns its checked complete extra span.
			$users = $users.set(at + 31, if (enabled) 1 else 0) ?? []
			if enabled {
				for index in 3..<24 {
					$users = $users.set(at + index, 0) ?? []
				}
				for i in 0..<GraphiteCollision.defaults.len() {
					field = GraphiteCollision.defaults.get(i) ?? { extra: 3, signed: False }
					value = GraphiteAttributes.get(context.table.attributes, slot.glyph, context.sub.collision_attribute + i)
					stored = if (field.signed) value else value.to_u16_wrap().to_i32()
					$users = $users.set(at + field.extra, stored) ?? []
				}
			}
		}
		{ state: { nodes, users: $users, user_count, justification_levels, feature_changes, first, last, active, positioned, advance_x, advance_y }, operations: $operations, stopped: $stopped }
	}
}

# Generated from `tests/fonts/graphite-geometry/collision-default-negative-ltr.ttf` by `tests/fonts/inline_tables.py`.

# The `Silf` table, 170 bytes.
collision_silf : List(U8)
collision_silf = [
	[0x00, 0x03, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10],
	[0x00, 0x03, 0x00, 0x00, 0x00, 0x2A, 0x00, 0x32, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00],
	[0x00, 0x01, 0xFF, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01],
	[0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x44, 0x00, 0x00],
	[0x00, 0x9A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x08],
	[0x00, 0x0A, 0x00, 0x02, 0x00, 0x0A, 0x02, 0x00, 0x00, 0x01, 0x00, 0x18, 0x00, 0x00, 0x00, 0x99],
	[0x00, 0x00, 0x00, 0x99, 0x00, 0x00, 0x00, 0x99, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x02],
	[0x00, 0x01, 0x00, 0x02, 0x00, 0x02, 0x00, 0x0C, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01],
	[0x00, 0x00, 0x00, 0x02, 0x00, 0x02, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00],
	[0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01],
	[0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x32],
].join_map(|row| row)

# The `Glat` table, 106 bytes.
collision_glat : List(U8)
collision_glat = [
	[0x00, 0x01, 0x00, 0x00, 0x01, 0x10, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],
	[0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],
	[0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x10, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],
	[0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],
	[0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x10, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],
	[0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],
	[0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],
].join_map(|row| row)

# The `Gloc` table, 16 bytes.
collision_gloc : List(U8)
collision_gloc = [
	[0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x11, 0x00, 0x04, 0x00, 0x26, 0x00, 0x48, 0x00, 0x6A],
].join_map(|row| row)

collision_prepared = TableGraphite.read({ silf: collision_silf, glat: collision_glat, gloc: collision_gloc, feat: Absent, sill: Absent, glyph_count: 3 }, 1048576)

expect {
	match collision_prepared {
		Err(_) => False
		Ok(table) => match table.program.subtables.first() {
			Err(_) => False
			Ok(sub) => {
				input = GraphiteSlots.append(GraphiteSlots.make(0, 1), { ..GraphiteSlots.no_slot, glyph: 1 })
				output = GraphiteCollision.prepare(input.state, { table, sub, rtl: False }, 100)
				GraphiteSlots.get_extra(output.state, 1, 31) == 1 and GraphiteSlots.get_extra(output.state, 1, 3) == 65535 and GraphiteSlots.get_extra(output.state, 1, 4) == -1 and GraphiteSlots.get_extra(output.state, 1, 10) == 65535 and GraphiteSlots.get_extra(output.state, 1, 18) == -1 and GraphiteSlots.get_extra(output.state, 1, 22) == 65535 and GraphiteSlots.get_extra(output.state, 1, 8) == 0 and output.stopped == 0
			}
		}
	}
}
expect {
	match collision_prepared {
		Err(_) => False
		Ok(table) => match table.program.subtables.first() {
			Err(_) => False
			Ok(sub) => {
				input = GraphiteSlots.append(GraphiteSlots.make(0, 1), { ..GraphiteSlots.no_slot, glyph: 1 })
				output = GraphiteCollision.prepare(input.state, { table, sub, rtl: False }, 0)
				output.stopped == 2 and GraphiteSlots.get_extra(output.state, 1, 31) == 0
			}
		}
	}
}

expect {
	n = TableVar.f32_from_int
	constraints = [
		{ low: n(-400), high: n(200), hard: True, a: 0, b: 0, c: 0 },
		GraphiteCollision.soft(n(-450), n(-400), n(10), n(-450)),
		GraphiteCollision.soft(n(200), n(250), n(10), n(250)),
	]
	result = GraphiteCollision.solve_axis(n(-1000), n(1000), 0, n(1), constraints, 100)
	match result.best {
		Absent => False
		Present(best) => best.value == TableVar.f32_from_ratio(2500, 11) and result.stopped == 0
	}
}
expect {
	n = TableVar.f32_from_int
	blocked = [{ low: n(-400), high: n(200), hard: True, a: 0, b: 0, c: 0 }]
	a = GraphiteCollision.solve_axis(n(-200), n(200), 0, n(1), blocked, 100)
	b = GraphiteCollision.solve_axis(n(-201), n(201), 0, n(1), blocked, 100)
	match (a.best, b.best) {
		(Absent, Present(best)) => best.value == n(200)
		_ => False
	}
}

expect {
	n = TableVar.f32_from_int
	result = GraphiteCollision.solve_axis(n(-1000), n(1000), 0, n(1), [{ low: n(-300), high: n(300), hard: True, a: 0, b: 0, c: 0 }], 100)
	match result.best {
		Absent => False
		Present(best) => best.value == n(300)
	}
}

collision_square = {
	n = TableVar.f32_from_int
	{ x_min: n(0), y_min: n(0), x_max: n(300), y_max: n(600), sum_min: n(0), sum_max: n(900), diff_min: n(-600), diff_max: n(300) }
}
expect {
	n = TableVar.f32_from_int
	box = GraphiteCollision.forbidden(collision_square, collision_square, n(100), 0)
	p = GraphiteCollision.project(box, 2, 0, 0)
	p.low == n(-800) and p.high == n(400) and p.inside
}
expect {
	n = TableVar.f32_from_int
	box = GraphiteCollision.forbidden(collision_square, collision_square, n(100), 0)
	offset = TableVar.f32_from_ratio(2500, 11)
	p = GraphiteCollision.project(box, 1, offset, 0)
	p.low == n(-600) and p.high == n(600) and !p.inside and p.gap == TableVar.f32_sub(offset, n(200))
}
expect {
	n = TableVar.f32_from_int
	attributes = { ..GraphiteAttributes.none, box_starts: [0], bytes: [0, 1, 0, 255, 0, 255, 0, 127, 0, 127, 0, 255, 0, 255] }
	query = |_, metric, _| match metric {
		2 => 600
		5 => 300
		_ => 0
	}
	match GraphiteCollision.load_box(attributes, 0, 1, query) {
		Absent => False
		Present(box) => box.x_max == TableVar.f32_div(n(38100), n(255)) and box.y_max == TableVar.f32_div(n(76200), n(255)) and box.sum_max == n(900)
	}
}

expect {
	n = TableVar.f32_from_int
	limits = { x_min: n(-1000), y_min: n(-1000), x_max: n(1000), y_max: n(1000) }
	obstacle = GraphiteCollision.forbidden(collision_square, collision_square, n(100), 0)
	result = GraphiteCollision.solve_shift(limits, 0, 0, [obstacle], n(50), n(10), 1000)
	result.feasible and result.x == TableVar.f32_from_ratio(2500, 11) and result.y == 0 and result.stopped == 0
}
expect {
	# Two-pass public-C-API witness. The reference recovers its unshifted
	# origin from the rounded displayed origin, rather than the mathematical
	# base 100; preserving that operation changes the resulting Y by 8 ulps.
	n = TableVar.f32_from_int
	old = TableVar.f32_from_ratio(2500, 11)
	base = TableVar.f32_sub(TableVar.f32_add(n(100), old), old)
	limits = { x_min: n(-1000), y_min: n(-1000), x_max: n(1000), y_max: n(1000) }
	obstacle = GraphiteCollision.forbidden(collision_square, collision_square, base, 0)
	result = GraphiteCollision.solve_shift(limits, old, 0, [obstacle], n(50), n(10), 1000)
	result.feasible and TableVar.f32_add(n(100), result.x) == 0x439D88D0 and result.y == 0xC1434308
}

expect {
	var $state = GraphiteSlots.make(0, 4)
	for flag in [12, 13, 12, 8] {
		appended = GraphiteSlots.append($state, GraphiteSlots.no_slot)
		$state = GraphiteSlots.set_extra(appended.state, appended.id, 3, flag)
	}
	actual = GraphiteCollision.groups($state, False, 100)
	actual.groups == [{ first: 1, last: 2 }, { first: 2, last: 3 }, { first: 3, last: 4 }]
}
expect {
	var $state = GraphiteSlots.make(0, 4)
	for flag in [8, 5, 0, 0] {
		appended = GraphiteSlots.append($state, GraphiteSlots.no_slot)
		$state = GraphiteSlots.set_extra(appended.state, appended.id, 3, flag)
	}
	actual = GraphiteCollision.groups($state, False, 100)
	actual.groups == [{ first: 1, last: 4 }]
}
