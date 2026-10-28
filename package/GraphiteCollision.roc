import GraphiteSlots
import TableGraphite
import GraphiteSilf
import GraphiteAttributes
import TableVar
import Bytes
import GraphitePosition

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
	ShiftResult : { x : U32, y : U32, feasible : Bool, active : Bool, operations : U64, stopped : U64 }
	Group : { first : U64, last : U64 }
	Groups : { groups : List(Group), operations : U64, stopped : U64 }
	ShiftInput : { target : [Present(Octabox), Absent], obstacles : List(Octabox), current_x : U32, current_y : U32, limits : Rect, margin : U32, weight : U32, operations : U64, stopped : U64 }

	# A collision pass retains its initial offset separately from the shift
	# authored during that pass. Recovering one from the rounded sum changes
	# later positions; both components are required even between groups.
	Offset : { base_x : U32, base_y : U32, delta_x : U32, delta_y : U32 }
	Work : { state : GraphiteSlots, offsets : List(Offset), roots : List(U64), ranks : List(U64) }
	Worked : { work : Work, operations : U64, stopped : U64, movement : U32 }
	Prepared : { work : Work, operations : U64, stopped : U64 }

	prepare_work : GraphiteSlots, U64 -> Prepared
	prepare_work = |state, budget| {
		count = state.nodes.len()
		if count > budget {
			return { work: { state, offsets: [], roots: [], ranks: [] }, operations: 0, stopped: 2 }
		}
		var $offsets = List.with_capacity(count)
		for id in 0..<count {
			$offsets = $offsets.append({ base_x: GraphiteSlots.get_extra(state, id, 8).to_u32_wrap(), base_y: GraphiteSlots.get_extra(state, id, 9).to_u32_wrap(), delta_x: 0, delta_y: 0 })
		}
		var $roots = List.repeat(0, count)
		var $ranks = List.repeat(0, count)
		var $operations = count
		var $path = []
		for id in 1..<count {
			$path = $path.clear()
			var $cursor = id
			var $root = 0
			while $cursor != 0 {
				if $operations >= budget {
					return { work: { state, offsets: $offsets, roots: [], ranks: [] }, operations: $operations, stopped: 2 }
				}
				$operations = $operations + 1
				known = $roots.get($cursor) ?? 0
				if known != 0 {
					$root = known
					break
				}
				$path = $path.append($cursor)
				parent = (state.nodes.get($cursor) ?? GraphiteSlots.no_slot).parent
				if parent == 0 {
					$root = $cursor
					break
				}
				if $path.len() >= count {
					return { work: { state, offsets: $offsets, roots: [], ranks: [] }, operations: $operations, stopped: 4 }
				}
				$cursor = parent
			}
			for item in $path {
				$roots = $roots.set(item, $root) ?? []
			}
		}
		var $cursor = state.first
		var $rank = 0
		while $cursor != 0 and $rank < state.active {
			if $operations >= budget {
				return { work: { state, offsets: $offsets, roots: [], ranks: [] }, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			$ranks = $ranks.set($cursor, $rank) ?? []
			$cursor = (state.nodes.get($cursor) ?? GraphiteSlots.no_slot).next
			$rank = $rank + 1
		}
		{ work: { state, offsets: $offsets, roots: $roots, ranks: $ranks }, operations: $operations, stopped: 0 }
	}

	# Called only for an index covered by prepare_work's aligned pool.
	# The stored physical offset is rounded base + independently rounded delta.
	store_work_shift : Work, U64, U32, U32, Bool -> { work : Work, movement : U32 }
	store_work_shift = |work, id, x, y, feasible| {
		{ state, offsets, roots, ranks } = work
		old = offsets.get(id) ?? { base_x: 0, base_y: 0, delta_x: 0, delta_y: 0 }
		delta_x = TableVar.f32_sub(x, old.base_x)
		delta_y = TableVar.f32_sub(y, old.base_y)
		change_x = TableVar.f32_sub(delta_x, old.delta_x)
		change_y = TableVar.f32_sub(delta_y, old.delta_y)
		movement = TableVar.f32_add(TableVar.f32_mul(change_x, change_x), TableVar.f32_mul(change_y, change_y))
		stored = { ..old, delta_x, delta_y }
		# The aligned pool and slot were checked by the pass walk.
		updated = offsets.set(id, stored) ?? []
		{ work: { state: GraphiteCollision.store_shift(state, id, TableVar.f32_add(old.base_x, delta_x), TableVar.f32_add(old.base_y, delta_y), feasible), offsets: updated, roots, ranks }, movement }
	}

	store_shift : GraphiteSlots, U64, U32, U32, Bool -> GraphiteSlots
	store_shift = |state, id, x, y, feasible| {
		{ nodes, users, user_count, justification_levels, feature_changes, first, last, active, positioned, advance_x, advance_y } = state
		at = (nodes.get(id) ?? GraphiteSlots.no_slot).user_start + user_count
		changed = (users.get(at + 8) ?? 0).to_u32_wrap() != x or (users.get(at + 9) ?? 0).to_u32_wrap() != y
		flags = (users.get(at + 3) ?? 0).bitwise_or(64)
		stored_flags = if (feasible) flags.bitwise_and(-33) else flags.bitwise_or(32)
		var $users = users
		$users = $users.set(at + 3, stored_flags) ?? []
		$users = $users.set(at + 8, x.to_i32_wrap()) ?? []
		$users = $users.set(at + 9, y.to_i32_wrap()) ?? []
		{ nodes, users: $users, user_count, justification_levels, feature_changes, first, last, active, positioned: positioned and !changed, advance_x, advance_y }
	}

	collect_sequence : Work, Context, U64, Group, Bool, Bool, ShiftInput, U64, (U64, U64, I32 -> I32) -> { regions : List(Region), operations : U64, stopped : U64 }
	collect_sequence = |work, context, id, group, reverse, retry, input, budget, base_metric| {
		if work.roots.is_empty() or GraphiteSlots.get_extra(work.state, id, 15) == 0 {
			return { regions: [], operations: 0, stopped: 0 }
		}
		target = match input.target {
			Absent => return { regions: [], operations: 0, stopped: 0 }
			Present(box) => box
		}
		offset = work.offsets.get(id) ?? { base_x: 0, base_y: 0, delta_x: 0, delta_y: 0 }
		slot = GraphiteSlots.get(work.state, id)
		origin_x = TableVar.f32_sub(TableVar.f32_sub(slot.position_x, offset.delta_x), offset.base_x)
		origin_y = TableVar.f32_sub(TableVar.f32_sub(slot.position_y, offset.delta_y), offset.base_y)
		root = work.roots.get(id) ?? 0
		rank = work.ranks.get(id) ?? 0
		var $cursor = group.first
		var $operations = 0
		var $walked = 0
		var $regions = []
		while $cursor != 0 and $walked < work.state.active {
			if $operations >= budget {
				return { regions: $regions, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			$walked = $walked + 1
			neighbor = GraphiteSlots.get(work.state, $cursor)
			flags = GraphiteSlots.get_extra(work.state, $cursor, 3)
			if $cursor != id and (work.roots.get($cursor) ?? 0) == root and flags.bitwise_and(18) == 0 and !(retry and flags.bitwise_and(33) == 1) {
				match GraphiteCollision.load_box(context.table.attributes, neighbor.glyph, 0, base_metric) {
					Absent => {}
					Present(box) => {
						before = if (reverse) (work.ranks.get($cursor) ?? 0) > rank else (work.ranks.get($cursor) ?? 0) < rank
						regions = GraphiteCollision.sequence_regions(work.state, id, $cursor, target, box, TableVar.f32_sub(neighbor.position_x, origin_x), TableVar.f32_sub(neighbor.position_y, origin_y), input.limits, before)
						for region in regions {
							$regions = $regions.append(region)
						}
					}
				}
			}
			if $cursor == group.last {
				break
			}
			$cursor = if (reverse) neighbor.previous else neighbor.next
		}
		{ regions: $regions, operations: $operations, stopped: 0 }
	}

	# Mode zero is the initial forward sweep, one the reverse bad-target
	# retry, and two the forward good-target refinement. A pass's Work is
	# retained across all sweeps and overlapping groups.
	shift_work_once : Work, Context, Group, Bool, U64, U64, (U64, U64, I32 -> I32) -> Worked
	shift_work_once = |initial, context, group, reverse, mode, budget, base_metric| {
		var $work = initial
		backward = mode == 1
		var $id = if (backward) group.last else group.first
		end = if (backward) group.first else group.last
		walk_reverse = reverse != backward
		var $walked = 0
		var $operations = 0
		var $movement = 0
		while $id != 0 and $walked < $work.state.active {
			if $operations >= budget {
				return { work: $work, operations: $operations, stopped: 2, movement: $movement }
			}
			$operations = $operations + 1
			$walked = $walked + 1
			flags = GraphiteSlots.get_extra($work.state, $id, 3)
			bad = flags.bitwise_and(32) != 0
			eligible = flags.bitwise_and(17) == 1 and (mode == 0 or (mode == 1 and bad) or (mode == 2 and !bad))
			locked = mode == 2 and flags.bitwise_and(256) != 0
			if eligible and locked {
				$work = { ..$work, state: GraphiteSlots.set_extra($work.state, $id, 3, flags.bitwise_and(-257)) }
			} else if eligible {
				if backward {
					$work = { ..$work, state: GraphiteSlots.set_extra($work.state, $id, 3, flags.bitwise_or(256)) }
				}
				prepared = GraphitePosition.position_for_font($work.state, context.rtl, context.sub.direction.bitwise_and(1) == 0, budget - $operations)
				$work = { ..$work, state: prepared.state }
				$operations = $operations + prepared.operations
				if prepared.stopped != 0 {
					return { work: $work, operations: $operations, stopped: prepared.stopped, movement: $movement }
				}
				offset = $work.offsets.get($id) ?? { base_x: 0, base_y: 0, delta_x: 0, delta_y: 0 }
				input = GraphiteCollision.collect_ink_at($work.state, context, $id, group, reverse, offset, backward, budget - $operations, base_metric)
				$operations = $operations + input.operations
				if input.stopped != 0 {
					return { work: $work, operations: $operations, stopped: input.stopped, movement: $movement }
				}
				match input.target {
					Absent => {}
					Present(box) => {
						sequence = GraphiteCollision.collect_sequence($work, context, $id, group, reverse, backward, input, budget - $operations, base_metric)
						$operations = $operations + sequence.operations
						if sequence.stopped != 0 {
							return { work: $work, operations: $operations, stopped: sequence.stopped, movement: $movement }
						}
						frame = GraphiteCollision.sequence_frame(box, input.current_x, input.current_y)
						solved = GraphiteCollision.solve_shift_regions(input.limits, input.current_x, input.current_y, input.obstacles, input.margin, input.weight, sequence.regions, frame, budget - $operations)
						$operations = $operations + solved.operations
						if solved.stopped != 0 {
							return { work: $work, operations: $operations, stopped: solved.stopped, movement: $movement }
						}
						if solved.active {
							stored = GraphiteCollision.store_work_shift($work, $id, solved.x, solved.y, solved.feasible)
							$work = stored.work
							$movement = TableVar.f32_max($movement, stored.movement)
						} else {
							$work = { ..$work, state: GraphiteCollision.store_shift($work.state, $id, input.current_x, input.current_y, True) }
						}
					}
				}
			}
			if $id == end {
				break
			}
			slot = GraphiteSlots.get($work.state, $id)
			$id = if (walk_reverse) slot.previous else slot.next
		}
		positioned = GraphitePosition.position_for_font($work.state, context.rtl, context.sub.direction.bitwise_and(1) == 0, budget - $operations)
		{ work: { ..$work, state: positioned.state }, operations: $operations + positioned.operations, stopped: positioned.stopped, movement: $movement }
	}

	# One group traversal, the ordinary ink/exclusion correction phase.
	# Retry scheduling and sequencing constraints are composed separately.
	# A parent's move is positioned before the next target is considered.
	shift_once : GraphiteSlots, Context, Group, Bool, U64, (U64, U64, I32 -> I32) -> Applied
	shift_once = |initial, context, group, reverse, budget, base_metric| {
		prepared = GraphiteCollision.prepare_work(initial, budget)
		if prepared.stopped != 0 {
			return { state: prepared.work.state, operations: prepared.operations, stopped: prepared.stopped }
		}
		result = GraphiteCollision.shift_work_once(prepared.work, context, group, reverse, 0, budget - prepared.operations, base_metric)
		{ state: result.work.state, operations: prepared.operations + result.operations, stopped: result.stopped }
	}

	shift_groups_once : GraphiteSlots, Context, Bool, U64, (U64, U64, I32 -> I32) -> Applied
	shift_groups_once = |initial, context, reverse, budget, base_metric| {
		grouped = GraphiteCollision.groups(initial, reverse, budget)
		var $operations = grouped.operations
		var $state = initial
		if grouped.stopped != 0 {
			return { state: $state, operations: $operations, stopped: grouped.stopped }
		}
		for group in grouped.groups {
			result = GraphiteCollision.shift_once($state, context, group, reverse, budget - $operations, base_metric)
			$state = result.state
			$operations = $operations + result.operations
			if result.stopped != 0 {
				return { state: $state, operations: $operations, stopped: result.stopped }
			}
		}
		{ state: $state, operations: $operations, stopped: 0 }
	}

	bad_in_group : GraphiteSlots, Group, Bool, U64 -> { bad : Bool, operations : U64, stopped : U64 }
	bad_in_group = |state, group, reverse, budget| {
		var $id = group.first
		var $operations = 0
		var $bad = False
		while $id != 0 and $operations < state.active {
			if $operations >= budget {
				return { bad: $bad, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			flags = GraphiteSlots.get_extra(state, $id, 3)
			if flags.bitwise_and(49) == 33 {
				$bad = True
			}
			if $id == group.last {
				break
			}
			slot = GraphiteSlots.get(state, $id)
			$id = if (reverse) slot.previous else slot.next
		}
		{ bad: $bad, operations: $operations, stopped: 0 }
	}

	# Complete shifting rounds within one group before starting the next.
	# Only a preceding forward sweep contributes to the refinement threshold;
	# reverse rescue work neither resets nor increases that measured movement.
	shifting : GraphiteSlots, Context, U64, U64, U64, (U64, U64, I32 -> I32) -> Applied
	shifting = |initial, context, pass_flags, encoded_threshold, budget, base_metric| {
		rounds = pass_flags.bitwise_and(7)
		if rounds == 0 {
			return { state: initial, operations: 0, stopped: 0 }
		}
		reverse = (context.rtl != (context.sub.direction.bitwise_and(1) == 0)) != (pass_flags.bitwise_and(32) != 0)
		grouped = GraphiteCollision.groups(initial, reverse, budget)
		if grouped.stopped != 0 {
			return { state: initial, operations: grouped.operations, stopped: grouped.stopped }
		}
		prepared = GraphiteCollision.prepare_work(initial, budget - grouped.operations)
		var $operations = grouped.operations + prepared.operations
		var $work = prepared.work
		if prepared.stopped != 0 {
			return { state: $work.state, operations: $operations, stopped: prepared.stopped }
		}
		threshold = TableVar.f32_from_int((if (encoded_threshold == 0) 10 else encoded_threshold).to_i64_wrap())
		threshold_squared = TableVar.f32_mul(threshold, threshold)
		for group in grouped.groups {
			first = GraphiteCollision.shift_work_once($work, context, group, reverse, 0, budget - $operations, base_metric)
			$work = first.work
			$operations = $operations + first.operations
			if first.stopped != 0 {
				return { state: $work.state, operations: $operations, stopped: first.stopped }
			}
			var $movement = first.movement
			for _ in 1..<rounds {
				bad = GraphiteCollision.bad_in_group($work.state, group, reverse, budget - $operations)
				$operations = $operations + bad.operations
				if bad.stopped != 0 {
					return { state: $work.state, operations: $operations, stopped: bad.stopped }
				}
				refine = $movement != 0 and !TableVar.f32_lt($movement, threshold_squared)
				if !bad.bad and !refine {
					break
				}
				rescued = GraphiteCollision.shift_work_once($work, context, group, reverse, 1, budget - $operations, base_metric)
				$work = rescued.work
				$operations = $operations + rescued.operations
				if rescued.stopped != 0 {
					return { state: $work.state, operations: $operations, stopped: rescued.stopped }
				}
				$movement = 0
				if refine {
					forward = GraphiteCollision.shift_work_once($work, context, group, reverse, 2, budget - $operations, base_metric)
					$work = forward.work
					$operations = $operations + forward.operations
					if forward.stopped != 0 {
						return { state: $work.state, operations: $operations, stopped: forward.stopped }
					}
					$movement = forward.movement
				}
			}
		}
		{ state: $work.state, operations: $operations, stopped: 0 }
	}

	# Collect the glyph ink and optional exclusion shapes in one group.
	# Sequencing is a separate addition to this constraint pool. Origins
	# have already been positioned; subtracting only the target's OWN offset
	# retains inherited parent movement and the reference's rounded recovery.
	collect_ink : GraphiteSlots, Context, U64, Group, Bool, U64, (U64, U64, I32 -> I32) -> ShiftInput
	collect_ink = |state, context, id, group, reverse, budget, base_metric| {
		offset = { base_x: GraphiteSlots.get_extra(state, id, 8).to_u32_wrap(), base_y: GraphiteSlots.get_extra(state, id, 9).to_u32_wrap(), delta_x: 0, delta_y: 0 }
		GraphiteCollision.collect_ink_at(state, context, id, group, reverse, offset, False, budget, base_metric)
	}

	collect_ink_at : GraphiteSlots, Context, U64, Group, Bool, Offset, Bool, U64, (U64, U64, I32 -> I32) -> ShiftInput
	collect_ink_at = |state, context, id, group, reverse, offset, retry, budget, base_metric| {
		slot = GraphiteSlots.get(state, id)
		current_x = GraphiteSlots.get_extra(state, id, 8).to_u32_wrap()
		current_y = GraphiteSlots.get_extra(state, id, 9).to_u32_wrap()
		number = |field| TableVar.f32_from_int(GraphiteSlots.get_extra(state, id, field).to_i64())
		input = { target: GraphiteCollision.load_box(context.table.attributes, slot.glyph, 0, base_metric), obstacles: [], current_x, current_y, limits: { x_min: number(4), y_min: number(5), x_max: number(6), y_max: number(7) }, margin: number(10), weight: number(11), operations: 0, stopped: 0 }
		target = match input.target {
			Absent => return input
			Present(box) => box
		}
		origin_x = TableVar.f32_sub(TableVar.f32_sub(slot.position_x, offset.delta_x), offset.base_x)
		origin_y = TableVar.f32_sub(TableVar.f32_sub(slot.position_y, offset.delta_y), offset.base_y)
		var $obstacles = []
		var $operations = 0
		var $walked = 0
		var $neighbor_id = group.first
		while $neighbor_id != 0 and $walked < state.active {
			if $operations >= budget {
				return { ..input, obstacles: $obstacles, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			$walked = $walked + 1
			neighbor = GraphiteSlots.get(state, $neighbor_id)
			neighbor_flags = GraphiteSlots.get_extra(state, $neighbor_id, 3)
			if $neighbor_id != id and neighbor_flags.bitwise_and(18) == 0 and !(retry and neighbor_flags.bitwise_and(33) == 1) {
				# Source zero is the glyph itself. Source one is its optional
				# exclusion glyph; zero means none, and an out-of-range dynamic
				# glyph is explicitly absent, as the language oracle observes.
				for source in 0..<2 {
					excluded = GraphiteSlots.get_extra(state, $neighbor_id, 12).to_u64_wrap()
					glyph = if (source == 0) neighbor.glyph else excluded
					if source == 0 or glyph != 0 {
						world_x = if (source == 0) neighbor.position_x else TableVar.f32_add(neighbor.position_x, TableVar.f32_from_int(GraphiteSlots.get_extra(state, $neighbor_id, 13).to_i64()))
						world_y = if (source == 0) neighbor.position_y else TableVar.f32_add(neighbor.position_y, TableVar.f32_from_int(GraphiteSlots.get_extra(state, $neighbor_id, 14).to_i64()))
						var $parts = 0
						match context.table.attributes.box_starts.get(glyph) {
							Err(_) => {}
							Ok(start) => {
								bitmap = Bytes.u16(context.table.attributes.bytes, start)
								for bit in 0..<16 {
									if bitmap.bitwise_and((1.U64).shl_wrap(bit.to_u8_wrap())) != 0 {
										$parts = $parts + 1
									}
								}
							}
						}
						first_part = if ($parts == 0) 0 else 1
						for part in first_part..<($parts + 1) {
							if $operations >= budget {
								return { ..input, obstacles: $obstacles, operations: $operations, stopped: 2 }
							}
							$operations = $operations + 1
							match GraphiteCollision.load_box(context.table.attributes, glyph, part, base_metric) {
								Absent => {}
								Present(box) => {
									dx = TableVar.f32_sub(origin_x, world_x)
									dy = TableVar.f32_sub(origin_y, world_y)
									$obstacles = $obstacles.append(GraphiteCollision.forbidden(target, box, dx, dy))
								}
							}
						}
					}
				}
			}
			if $neighbor_id == group.last {
				break
			}
			$neighbor_id = if (reverse) neighbor.previous else neighbor.next
		}
		{ ..input, obstacles: $obstacles, operations: $operations, stopped: 0 }
	}

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
		frame = { center_x: 0, center_y: 0, half_width: 0, half_height: 0, offset_x: current_x, offset_y: current_y }
		GraphiteCollision.solve_shift_regions(limits, current_x, current_y, obstacles, margin, weight, [], frame, budget)
	}

	solve_shift_regions : Rect, U32, U32, List(Octabox), U32, U32, List(Region), SequenceFrame, U64 -> ShiftResult
	solve_shift_regions = |limits, current_x, current_y, obstacles, margin, weight, regions, frame, budget| {
		if !TableVar.f32_lt(limits.x_min, limits.x_max) or !TableVar.f32_lt(limits.y_min, limits.y_max) {
			return { x: current_x, y: current_y, feasible: True, active: False, operations: 0, stopped: 0 }
		}
		var $operations = 0
		var $active = False
		var $constraints = []
		var $best = Absent
		for axis in 0..<4 {
			$constraints = $constraints.clear()
			for obstacle in obstacles {
				if $operations >= budget {
					return { x: current_x, y: current_y, feasible: False, active: $active, operations: $operations, stopped: 2 }
				}
				$operations = $operations + 1
				projection = GraphiteCollision.project(obstacle, axis, current_x, current_y)
				$constraints = GraphiteCollision.add_projected($constraints, projection, axis, margin, weight)
			}
			for region in regions {
				if $operations >= budget {
					return { x: current_x, y: current_y, feasible: False, active: $active, operations: $operations, stopped: 2 }
				}
				$operations = $operations + 1
				match GraphiteCollision.sequence_projection(region, axis, frame) {
					Absent => {}
					Present(projected) => {
						$constraints = $constraints.append(projected)
					}
				}
			}
			bounds = GraphiteCollision.axis_limits(limits, axis, current_x, current_y)
			for constraint in $constraints {
				if TableVar.f32_lt(constraint.low, bounds.high) and TableVar.f32_lt(bounds.low, constraint.high) {
					$active = True
				}
			}
			solved = GraphiteCollision.solve_axis(bounds.low, bounds.high, bounds.constant, bounds.coefficient, $constraints, budget - $operations)
			$operations = $operations + solved.operations
			if solved.stopped != 0 {
				return { x: current_x, y: current_y, feasible: False, active: $active, operations: $operations, stopped: solved.stopped }
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
			Absent => { x: current_x, y: current_y, feasible: False, active: $active, operations: $operations, stopped: 0 }
			Present(best) => { x: best.x, y: best.y, feasible: True, active: $active, operations: $operations, stopped: 0 }
		}
	}

	# Sequencing regions are authored in translation space. The four
	# projections have independently measured coefficients; in particular
	# their orthogonal constants are not a conventional rotated polynomial.
	Penalty : [Hard, SquareX({ weight : U32, center : U32 }), SquareY({ weight : U32, center : U32 }), Radial(U32), RadialY({ radial : U32, weight : U32, center : U32 })]
	Region : { bounds : Rect, penalty : Penalty }
	SequenceFrame : { center_x : U32, center_y : U32, half_width : U32, half_height : U32, offset_x : U32, offset_y : U32 }
	Coefficients : { a : U32, b : U32, c : U32 }

	sequence_frame : Octabox, U32, U32 -> SequenceFrame
	sequence_frame = |box, offset_x, offset_y| {
		half = TableVar.f32_half
		{ center_x: TableVar.f32_mul(TableVar.f32_add(box.x_min, box.x_max), half), center_y: TableVar.f32_mul(TableVar.f32_add(box.y_min, box.y_max), half), half_width: TableVar.f32_mul(TableVar.f32_sub(box.x_max, box.x_min), half), half_height: TableVar.f32_mul(TableVar.f32_sub(box.y_max, box.y_min), half), offset_x, offset_y }
	}

	# Caller proves a common attachment root and supplies the relation in
	# this pass's traversal order. Only the four exact order values activate.
	sequence_regions : GraphiteSlots, U64, U64, Octabox, Octabox, U32, U32, Rect, Bool -> List(Region)
	sequence_regions = |state, id, neighbor_id, target, neighbor, dx, dy, limits, neighbor_before| {
		target_class = GraphiteSlots.get_extra(state, id, 15)
		prox = GraphiteSlots.get_extra(state, id, 16)
		if target_class == 0 or GraphiteSlots.get_extra(state, neighbor_id, 15) != (if (prox == 0) target_class else prox) {
			return []
		}
		order = GraphiteSlots.get_extra(state, id, 17)
		left_down = (neighbor_before and order == 1) or (!neighbor_before and order == 2)
		diagonal = order == 1 or order == 2
		above = (neighbor_before and order == 4) or (!neighbor_before and order == 8)
		below = (neighbor_before and order == 8) or (!neighbor_before and order == 4)
		if !diagonal and !above and !below {
			return []
		}
		add = TableVar.f32_add
		sub = TableVar.f32_sub
		number = |field| TableVar.f32_from_int(GraphiteSlots.get_extra(state, neighbor_id, field).to_i64())
		t = GraphiteCollision.sequence_frame(target, 0, 0)
		n = GraphiteCollision.sequence_frame(neighbor, 0, 0)
		outer = { x_min: sub(limits.x_min, t.half_width), y_min: sub(limits.y_min, t.half_height), x_max: add(limits.x_max, t.half_width), y_max: add(limits.y_max, t.half_height) }
		if diagonal {
			a = add(sub(add(dx, n.center_x), t.center_x), number(18))
			b = if (left_down) sub(sub(add(dx, neighbor.x_min), target.x_max), number(20)) else add(sub(add(dx, neighbor.x_max), target.x_min), number(20))
			c = sub(add(dy, n.center_y), t.center_y)
			e = sub(add(dx, if (left_down) neighbor.x_max else neighbor.x_min), t.center_x)
			h = number(22)
			[
				{ bounds: if (left_down) { x_min: a, y_min: outer.y_min, x_max: outer.x_max, y_max: c } else { x_min: outer.x_min, y_min: c, x_max: a, y_max: outer.y_max }, penalty: SquareX({ weight: number(19), center: a }) },
				{ bounds: if (left_down) { x_min: b, y_min: c, x_max: outer.x_max, y_max: outer.y_max } else { x_min: outer.x_min, y_min: outer.y_min, x_max: b, y_max: c }, penalty: Hard },
				{ bounds: if (left_down) { x_min: outer.x_min, y_min: sub(c, h), x_max: b, y_max: outer.y_max } else { x_min: b, y_min: outer.y_min, x_max: outer.x_max, y_max: add(c, h) }, penalty: Radial(number(21)) },
				{ bounds: { x_min: if (left_down) outer.x_min else e, y_min: c, x_max: if (left_down) e else outer.x_max, y_max: add(c, h) }, penalty: SquareY({ weight: number(23), center: add(c, h) }) },
				{ bounds: { x_min: if (left_down) outer.x_min else e, y_min: sub(c, h), x_max: if (left_down) e else outer.x_max, y_max: c }, penalty: RadialY({ radial: number(21), weight: number(23), center: sub(c, h) }) },
			]
		} else {
			left = sub(sub(add(dx, neighbor.x_min), target.x_max), t.center_x)
			right = sub(sub(add(dx, neighbor.x_max), target.x_min), t.center_x)
			[{ bounds: { x_min: left, x_max: right, y_min: if (above) sub(add(dy, neighbor.y_max), t.center_y) else outer.y_min, y_max: if (below) sub(add(dy, neighbor.y_min), t.center_y) else outer.y_max }, penalty: Hard }]
		}
	}

	sequence_coefficients : Penalty, U64, SequenceFrame -> Coefficients
	sequence_coefficients = |penalty, axis, frame| {
		add = TableVar.f32_add
		sub = TableVar.f32_sub
		mul = TableVar.f32_mul
		fx = add(frame.center_x, frame.offset_x)
		fy = add(frame.center_y, frame.offset_y)
		difference = sub(fx, fy)
		sum = add(fx, fy)
		two = TableVar.f32_from_int(2)
		quarter = TableVar.f32_from_ratio(1, 4)
		eighth = TableVar.f32_from_ratio(1, 8)
		match penalty {
			Hard => { a: 0, b: 0, c: 0 }
			SquareX(p) => {
				if axis == 0 {
					{ a: p.weight, b: mul(p.weight, p.center), c: mul(p.weight, mul(p.center, p.center)) }
				} else if axis == 1 {
					{ a: 0, b: 0, c: mul(p.weight, add(mul(fx, fx), mul(p.center, p.center))) }
				} else {
					a = mul(p.weight, eighth)
					k = sub(add(mul(two, p.center), mul(two, frame.center_x)), if (axis == 2) difference else sum)
					{ a, b: mul(a, k), c: mul(a, mul(k, k)) }
				}
			}
			SquareY(p) => {
				if axis == 0 {
					{ a: 0, b: 0, c: mul(p.weight, add(mul(fy, fy), mul(p.center, p.center))) }
				} else if axis == 1 {
					{ a: p.weight, b: mul(p.weight, p.center), c: mul(p.weight, mul(p.center, p.center)) }
				} else {
					a = mul(p.weight, eighth)
					k = add(add(mul(two, p.center), mul(two, frame.center_y)), if (axis == 2) difference else sum)
					{ a, b: mul(a, k), c: mul(a, mul(k, k)) }
				}
			}
			Radial(weight) => match axis {
				0 => { a: weight, b: 0, c: mul(weight, mul(fy, fy)) }
				1 => { a: weight, b: 0, c: mul(weight, mul(fx, fx)) }
				_ => {
					a = mul(weight, quarter)
					orth = if (axis == 2) difference else sum
					{ a, b: 0, c: mul(a, mul(orth, orth)) }
				}
			}
			RadialY(p) => {
				x = GraphiteCollision.sequence_coefficients(Radial(p.radial), axis, frame)
				y = GraphiteCollision.sequence_coefficients(SquareY({ weight: p.weight, center: p.center }), axis, frame)
				{ a: add(x.a, y.a), b: add(x.b, y.b), c: add(x.c, y.c) }
			}
		}
	}

	sequence_projection : Region, U64, SequenceFrame -> [Present(Interval), Absent]
	sequence_projection = |region, axis, frame| {
		add = TableVar.f32_add
		sub = TableVar.f32_sub
		mul = TableVar.f32_mul
		min = TableVar.f32_min
		max = TableVar.f32_max
		lt = TableVar.f32_lt
		two = TableVar.f32_from_int(2)
		r = region.bounds
		hard = match region.penalty {
			Hard => True
			_ => False
		}
		d = sub(frame.offset_x, frame.offset_y)
		s = add(frame.offset_x, frame.offset_y)
		padding = add(frame.half_width, frame.half_height)
		interval = match axis {
			0 => {
				if !lt(sub(frame.offset_y, frame.half_height), r.y_max) or !lt(r.y_min, add(frame.offset_y, frame.half_height)) {
					return Absent
				}
				{ low: r.x_min, high: r.x_max }
			}
			1 => {
				if !lt(sub(frame.offset_x, frame.half_width), r.x_max) or !lt(r.x_min, add(frame.offset_x, frame.half_width)) {
					return Absent
				}
				{ low: r.y_min, high: r.y_max }
			}
			2 => {
				lo_x = sub(mul(two, r.x_min), d)
				lo_y = add(mul(two, r.y_min), d)
				hi_x = sub(mul(two, r.x_max), d)
				hi_y = add(mul(two, r.y_max), d)
				if hard {
					{ low: max(add(r.x_min, r.y_min), max(sub(lo_x, padding), sub(lo_y, padding))), high: min(add(r.x_max, r.y_max), min(add(hi_x, padding), add(hi_y, padding))) }
				} else {
					{ low: max(lo_x, lo_y), high: min(hi_x, hi_y) }
				}
			}
			_ => {
				lo_x = sub(mul(two, r.x_min), s)
				lo_y = sub(s, mul(two, r.y_max))
				hi_x = sub(mul(two, r.x_max), s)
				hi_y = sub(s, mul(two, r.y_min))
				if hard {
					{ low: max(sub(r.x_min, r.y_max), max(sub(lo_x, padding), sub(lo_y, padding))), high: min(sub(r.x_max, r.y_min), min(add(hi_x, padding), add(hi_y, padding))) }
				} else {
					{ low: max(lo_x, lo_y), high: min(hi_x, hi_y) }
				}
			}
		}
		if !lt(interval.low, interval.high) {
			return Absent
		}
		coefficient = GraphiteCollision.sequence_coefficients(region.penalty, axis, frame)
		Present({ low: interval.low, high: interval.high, hard, a: coefficient.a, b: coefficient.b, c: coefficient.c })
	}

	ClusterBoxes : { boxes : List(Octabox), operations : U64, stopped : U64 }
	cluster_boxes : Work, Context, U64, U64, (U64, U64, I32 -> I32) -> ClusterBoxes
	cluster_boxes = |work, context, root, budget, base_metric| {
		var $boxes = []
		var $id = work.state.first
		var $operations = 0
		while $id != 0 and $operations < work.state.active {
			if $operations >= budget {
				return { boxes: $boxes, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			slot = GraphiteSlots.get(work.state, $id)
			if (work.roots.get($id) ?? 0) == root {
				match GraphiteCollision.load_box(context.table.attributes, slot.glyph, 0, base_metric) {
					Absent => {}
					Present(box) => {
						$boxes = $boxes.append(GraphiteCollision.translate_box(box, slot.position_x, slot.position_y))
					}
				}
			}
			$id = slot.next
		}
		{ boxes: $boxes, operations: $operations, stopped: 0 }
	}

	# Apply one root's advance correction. The target cluster's occupied
	# bins share one vertical origin; external spaces reserve their advance
	# independently of ink. No floating-derived array capacity is allocated.
	kern_cluster : Work, Context, U64, Group, Bool, U64, (U64, U64, I32 -> I32) -> Worked
	kern_cluster = |initial, context, id, group, reverse, budget, base_metric| {
		if id == group.last {
			return { work: initial, operations: 0, stopped: 0, movement: 0 }
		}
		positioned = GraphitePosition.position_for_font(initial.state, context.rtl, context.sub.direction.bitwise_and(1) == 0, budget)
		var $operations = positioned.operations
		var $work = { ..initial, state: positioned.state }
		if positioned.stopped != 0 {
			return { work: $work, operations: $operations, stopped: positioned.stopped, movement: 0 }
		}
		cluster = GraphiteCollision.cluster_boxes($work, context, id, budget - $operations, base_metric)
		$operations = $operations + cluster.operations
		if cluster.stopped != 0 {
			return { work: $work, operations: $operations, stopped: cluster.stopped, movement: 0 }
		}
		if cluster.boxes.is_empty() {
			return { work: $work, operations: $operations, stopped: 0, movement: 0 }
		}
		margin = TableVar.f32_from_int(GraphiteSlots.get_extra($work.state, id, 10).to_i64())
		m = TableVar.f32_max(margin, TableVar.f32_from_int(10))
		var $min_y = (cluster.boxes.first() ?? { x_min: 0, y_min: 0, x_max: 0, y_max: 0, sum_min: 0, sum_max: 0, diff_min: 0, diff_max: 0 }).y_min
		for box in cluster.boxes {
			$min_y = TableVar.f32_min($min_y, box.y_min)
		}
		cache_min_y = TableVar.f32_sub($min_y, m)
		slot = GraphiteSlots.get($work.state, id)
		var $cursor = if (reverse) slot.previous else slot.next
		var $walked = 0
		var $space = 0
		var $gap = 0x7CF0BDC2
		var $external = False
		while $cursor != 0 and $walked < $work.state.active {
			if $operations >= budget {
				return { work: $work, operations: $operations, stopped: 2, movement: 0 }
			}
			$operations = $operations + 1
			$walked = $walked + 1
			neighbor = GraphiteSlots.get($work.state, $cursor)
			flags = GraphiteSlots.get_extra($work.state, $cursor, 3)
			if (initial.roots.get($cursor) ?? 0) != id and flags.bitwise_and(2) == 0 {
				if flags.bitwise_and(128) != 0 {
					$space = TableVar.f32_add($space, TableVar.f32_mul(TableVar.f32_from_int(2), neighbor.advance_x))
				} else {
					match GraphiteCollision.load_box(context.table.attributes, neighbor.glyph, 0, base_metric) {
						Absent => {}
						Present(box) => {
							if box.x_min != box.x_max or box.y_min != box.y_max {
								$external = True
								world = GraphiteCollision.translate_box(box, neighbor.position_x, neighbor.position_y)
								for target in cluster.boxes {
									pair = GraphiteCollision.kern_gap(target, world, m, cache_min_y, context.sub.direction.bitwise_and(1) == 0, budget - $operations)
									$operations = $operations + pair.operations
									if pair.stopped != 0 {
										return { work: $work, operations: $operations, stopped: pair.stopped, movement: 0 }
									}
									$gap = TableVar.f32_min($gap, TableVar.f32_sub(pair.gap, $space))
								}
							}
						}
					}
				}
			}
			if $cursor == group.last {
				break
			}
			$cursor = if (reverse) neighbor.previous else neighbor.next
		}
		if !$external {
			return { work: $work, operations: $operations, stopped: 0, movement: 0 }
		}
		needed = if (context.sub.direction.bitwise_and(1) == 0) $gap.bitwise_xor(0x80000000) else $gap
		previous = GraphiteSlots.get_extra($work.state, id, 8).to_u32_wrap()
		low = TableVar.f32_sub(TableVar.f32_from_int(GraphiteSlots.get_extra($work.state, id, 4).to_i64()), previous)
		high = TableVar.f32_sub(TableVar.f32_from_int(GraphiteSlots.get_extra($work.state, id, 6).to_i64()), previous)
		increment = TableVar.f32_min(high, TableVar.f32_max(low, needed))
		flags = GraphiteSlots.get_extra($work.state, id, 3)
		new_flags = if (increment == needed) flags.bitwise_and(-33) else flags.bitwise_or(32)
		var $state = GraphiteSlots.set_extra($work.state, id, 3, new_flags)
		$state = GraphiteSlots.set_extra($state, id, 8, TableVar.f32_add(previous, increment).to_i32_wrap())
		$state = GraphiteSlots.set($state, id, { ..slot, advance_x: TableVar.f32_add(slot.advance_x, increment) })
		$state = { ..$state, positioned: False }
		$work = { ..$work, state: $state }
		{ work: $work, operations: $operations, stopped: 0, movement: TableVar.f32_mul(increment, increment) }
	}

	kerning : GraphiteSlots, Context, U64, U64, (U64, U64, I32 -> I32) -> Applied
	kerning = |initial, context, pass_flags, budget, base_metric| {
		if pass_flags.bitwise_and(8) == 0 {
			return { state: initial, operations: 0, stopped: 0 }
		}
		reverse = (context.rtl != (context.sub.direction.bitwise_and(1) == 0)) != (pass_flags.bitwise_and(32) != 0)
		grouped = GraphiteCollision.groups(initial, reverse, budget)
		if grouped.stopped != 0 {
			return { state: initial, operations: grouped.operations, stopped: grouped.stopped }
		}
		prepared = GraphiteCollision.prepare_work(initial, budget - grouped.operations)
		var $work = prepared.work
		var $operations = grouped.operations + prepared.operations
		if prepared.stopped != 0 {
			return { state: $work.state, operations: $operations, stopped: prepared.stopped }
		}
		for group in grouped.groups {
			var $id = group.first
			var $walked = 0
			while $id != 0 and $walked < $work.state.active {
				if $operations >= budget {
					return { state: $work.state, operations: $operations, stopped: 2 }
				}
				$operations = $operations + 1
				$walked = $walked + 1
				slot = GraphiteSlots.get($work.state, $id)
				flags = GraphiteSlots.get_extra($work.state, $id, 3)
				if flags.bitwise_and(17) == 17 {
					if slot.parent != 0 {
						# Promotion follows the scan. An already visited parent
						# does not retroactively become a kerning target.
						parent_flags = GraphiteSlots.get_extra($work.state, slot.parent, 3)
						promoted = GraphiteSlots.set_extra($work.state, slot.parent, 3, parent_flags.bitwise_or(17))
						$work = { ..$work, state: { ..promoted, positioned: promoted.positioned and parent_flags.bitwise_and(16) != 0 } }
					} else {
						result = GraphiteCollision.kern_cluster($work, context, $id, group, reverse, budget - $operations, base_metric)
						$work = result.work
						$operations = $operations + result.operations
						if result.stopped != 0 {
							return { state: $work.state, operations: $operations, stopped: result.stopped }
						}
					}
				}
				if $id == group.last {
					break
				}
				$id = if (reverse) slot.previous else slot.next
			}
		}
		positioned = GraphitePosition.position_for_font($work.state, context.rtl, context.sub.direction.bitwise_and(1) == 0, budget - $operations)
		{ state: positioned.state, operations: $operations + positioned.operations, stopped: positioned.stopped }
	}

	# A positioning pass first resolves shifting/sequencing within each
	# group, then adjusts cluster advances through the kerning phase.
	collisions : GraphiteSlots, Context, U64, U64, U64, (U64, U64, I32 -> I32) -> Applied
	collisions = |initial, context, pass_flags, threshold, budget, base_metric| {
		shifted = GraphiteCollision.shifting(initial, context, pass_flags, threshold, budget, base_metric)
		if shifted.stopped != 0 {
			return shifted
		}
		kerned = GraphiteCollision.kerning(shifted.state, context, pass_flags, budget - shifted.operations, base_metric)
		{ state: kerned.state, operations: shifted.operations + kerned.operations, stopped: kerned.stopped }
	}

	translate_box : Octabox, U32, U32 -> Octabox
	translate_box = |box, x, y| {
		add = TableVar.f32_add
		sum = add(x, y)
		diff = TableVar.f32_sub(x, y)
		{ x_min: add(box.x_min, x), x_max: add(box.x_max, x), y_min: add(box.y_min, y), y_max: add(box.y_max, y), sum_min: add(box.sum_min, sum), sum_max: add(box.sum_max, sum), diff_min: add(box.diff_min, diff), diff_max: add(box.diff_max, diff) }
	}

	# Public logging's occupied bins sample their top edge. The left-side
	# difference bound additionally spans one bin width; the other three
	# diagonal bounds do not. Translate the octabox before these operations.
	kern_edge : Octabox, U32, U32, U32, Bool -> U32
	kern_edge = |box, low_y, sample_y, margin, left| {
		if box.x_min == box.x_max and box.y_min == box.y_max {
			return if (left) TableVar.f32_sub(box.x_min, margin) else TableVar.f32_add(box.x_max, margin)
		}
		if left {
			TableVar.f32_max(TableVar.f32_sub(box.x_min, margin), TableVar.f32_max(TableVar.f32_sub(TableVar.f32_sub(box.sum_min, sample_y), margin), TableVar.f32_add(box.diff_min, TableVar.f32_sub(low_y, margin))))
		} else {
			TableVar.f32_min(TableVar.f32_add(box.x_max, margin), TableVar.f32_min(TableVar.f32_add(TableVar.f32_sub(box.sum_max, sample_y), margin), TableVar.f32_add(TableVar.f32_add(box.diff_max, sample_y), margin)))
		}
	}

	KernGap : { gap : U32, operations : U64, stopped : U64 }
	kern_gap : Octabox, Octabox, U32, U32, Bool, U64 -> KernGap
	kern_gap = |target, neighbor, margin, cache_min_y, rtl, budget| {
		# An empty obstacle has no occupied bins; an empty target retains
		# a margin-expanded point, matching the distinct public witnesses.
		if target.x_min == target.x_max and target.y_min == target.y_max and neighbor.x_min == neighbor.x_max and neighbor.y_min == neighbor.y_max {
			return { gap: 0x7CF0BDC2, operations: 0, stopped: 0 }
		}
		if neighbor.x_min == neighbor.x_max and neighbor.y_min == neighbor.y_max {
			return { gap: 0x7CF0BDC2, operations: 0, stopped: 0 }
		}
		mul = TableVar.f32_mul
		add = TableVar.f32_add
		sub = TableVar.f32_sub
		width = TableVar.f32_div(mul(TableVar.f32_from_int(2), margin), TableVar.f32_from_int(3))
		index = |y| TableVar.f32_floor(TableVar.f32_div(add(sub(y, cache_min_y), TableVar.f32_one), width))
		target_first = index(target.y_min)
		neighbor_first = index(neighbor.y_min)
		first = if (target_first > neighbor_first) target_first else neighbor_first
		target_last = index(target.y_max) + 1
		neighbor_last = index(neighbor.y_max)
		last = if (target_last < neighbor_last) target_last else neighbor_last
		var $gap = 0x7CF0BDC2
		var $operations = 0
		if last < first {
			return { gap: $gap, operations: 0, stopped: 0 }
		}
		# Count before walking; no allocation is sized by a floating value.
		count = (last - first).to_u64_wrap() + 1
		for offset in 0..<count {
			if $operations >= budget {
				return { gap: $gap, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			i = first + offset.to_i64_wrap()
			low = sub(add(cache_min_y, mul(TableVar.f32_from_int(i), width)), TableVar.f32_one)
			sample = add(low, width)
			target_edge = GraphiteCollision.kern_edge(target, low, sample, margin, rtl)
			near_edge = GraphiteCollision.kern_edge(neighbor, low, sample, 0, !rtl)
			gap = if (rtl) sub(target_edge, near_edge) else sub(near_edge, target_edge)
			$gap = TableVar.f32_min($gap, gap)
		}
		{ gap: $gap, operations: $operations, stopped: 0 }
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
		slice = match axis {
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
		# The pinned interval constructor retains an initially empty
		# diagonal slice as its lower-endpoint point candidate. This is a
		# derived search rule, not a repair of the font's stored bounds.
		{ ..slice, high: TableVar.f32_max(slice.low, slice.high) }
	}

	# An independently derived interval optimizer. Each permitted range has
	# cost a*x*x - 2*b*x + c. An obstacle removes an open interval; a margin
	# or sequencing region adds a quadratic only over its own interval.
	# Flat alternating buffers retain table order and avoid a recursive sort.
	solve_axis : U32, U32, U32, U32, List(Interval), U64 -> AxisResult
	solve_axis = |low, high, constant, coefficient, constraints, budget| {
		if TableVar.f32_lt(high, low) {
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
			# A non-finite cost cannot improve a finite solution. Keep this
			# explicit: the integer binary32 helpers intentionally do not
			# implement NaN arithmetic for an overflowed quadratic.
			if GraphiteCollision.finite(range.a) and GraphiteCollision.finite(range.b) and GraphiteCollision.finite(range.c) {
				value = TableVar.f32_min(range.high, TableVar.f32_max(range.low, TableVar.f32_div(range.b, range.a)))
				linear = TableVar.f32_mul(TableVar.f32_mul(TableVar.f32_from_int(2), range.b), value)
				cost = TableVar.f32_add(TableVar.f32_sub(TableVar.f32_mul(range.a, TableVar.f32_mul(value, value)), linear), range.c)
				better = match $best {
					Absent => True
					Present(previous) => !TableVar.f32_lt(previous.cost, cost)
				}
				if better and GraphiteCollision.finite(cost) {
					$best = Present({ value, cost })
				}
			}
		}
		{ best: $best, operations: $operations, stopped: 0 }
	}

	finite : U32 -> Bool
	finite = |bits| bits.bitwise_and(0x7F800000) != 0x7F800000

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

collision_ink_state = {
	n = TableVar.f32_from_int
	a = GraphiteSlots.append(GraphiteSlots.make(0, 2), { ..GraphiteSlots.no_slot, glyph: 1, advance_x: n(100) })
	b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, glyph: 2, advance_x: n(602) })
	var $state = b.state
	for id in [a.id, b.id] {
		for pair in [(31, 1), (4, -1000), (5, -1000), (6, 1000), (7, 1000), (11, 10)] {
			$state = GraphiteSlots.set_extra($state, id, pair.0, pair.1)
		}
	}
	GraphitePosition.position(GraphiteSlots.set_extra($state, b.id, 3, 1), False, 100).state
}
expect {
	match collision_prepared {
		Err(_) => False
		Ok(table) => match table.program.subtables.first() {
			Err(_) => False
			Ok(sub) => {
				attrs = { ..GraphiteAttributes.none, box_starts: [0, 6, 12], bytes: [0, 0, 0, 255, 0, 255, 0, 0, 0, 255, 0, 255, 0, 0, 0, 255, 0, 255] }
				context = { table: { ..table, attributes: attrs }, sub, rtl: False }
				metric = |_, wanted, _| match wanted {
					2 => 600
					5 => 300
					_ => 0
				}
				state = GraphiteSlots.set_extra(GraphiteSlots.set_extra(collision_ink_state, 1, 12, 65535), 1, 13, 500)
				input = GraphiteCollision.collect_ink(state, context, 2, { first: 1, last: 2 }, False, 100, metric)
				solved = GraphiteCollision.solve_shift(input.limits, input.current_x, input.current_y, input.obstacles, input.margin, input.weight, 1000)
				input.obstacles.len() == 1 and solved.x == TableVar.f32_from_int(200)
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
				attrs = { ..GraphiteAttributes.none, box_starts: [0, 6, 12], bytes: [0, 0, 0, 255, 0, 255, 0, 0, 0, 255, 0, 255, 0, 0, 0, 255, 0, 255] }
				context = { table: { ..table, attributes: attrs }, sub, rtl: False }
				metric = |_, wanted, _| match wanted {
					2 => 600
					5 => 300
					_ => 0
				}
				actual = GraphiteCollision.shift_groups_once(collision_ink_state, context, False, 1000, metric)
				actual.stopped == 0 and GraphiteSlots.get(actual.state, 2).position_x == TableVar.f32_from_int(300) and actual.state.advance_x == TableVar.f32_from_int(702) and GraphiteSlots.get_extra(actual.state, 2, 3) == 65
			}
		}
	}
}

expect {
	# An initially degenerate diagonal slice remains a point candidate.
	# The public reference retains it even inside a removed open interval;
	# this differs from zero-length pieces produced by interval subtraction.
	n = TableVar.f32_from_int
	result = GraphiteCollision.solve_axis(n(200), n(200), 0, TableVar.f32_half, [{ low: n(-400), high: n(800), hard: True, a: 0, b: 0, c: 0 }], 100)
	match result.best {
		Absent => False
		Present(best) => best.value == n(200)
	}
}

expect {
	n = TableVar.f32_from_int
	limits = { x_min: n(101), y_min: n(-100), x_max: n(201), y_max: n(100) }
	forbidden = GraphiteCollision.forbidden(collision_square, collision_square, n(-100), 0)
	result = GraphiteCollision.solve_shift(limits, 0, 0, [forbidden], 0, n(10), 1000)
	result.feasible and result.x == n(101) and result.y == n(101)
}

expect {
	# Original trace R4/R5 difference coefficients, including the measured
	# positive offset-sum term in the Y-square projection.
	n = TableVar.f32_from_int
	frame = { center_x: n(150), center_y: n(300), half_width: n(150), half_height: n(300), offset_x: 0, offset_y: 0 }
	r4 = GraphiteCollision.sequence_coefficients(SquareY({ weight: n(500), center: n(320) }), 3, frame)
	r5 = GraphiteCollision.sequence_coefficients(RadialY({ radial: n(100), weight: n(500), center: n(20) }), 3, frame)
	r4.a == TableVar.f32_from_ratio(125, 2) and r4.b == n(105625) and r4.c == n(178506250) and r5.a == TableVar.f32_from_ratio(175, 2) and r5.b == n(68125) and r5.c == n(79318750)
}

expect {
	n = TableVar.f32_from_int
	frame = { center_x: n(150), center_y: n(300), half_width: n(150), half_height: n(300), offset_x: 0, offset_y: 0 }
	region = { bounds: { x_min: n(-170), y_min: n(170), x_max: n(1150), y_max: n(1300) }, penalty: Hard }
	match (GraphiteCollision.sequence_projection(region, 2, frame), GraphiteCollision.sequence_projection(region, 3, frame)) {
		(Present(sum), Present(diff)) => sum.low == 0 and sum.high == n(2450) and diff.low == n(-790) and diff.high == n(110)
		_ => False
	}
}

expect {
	n = TableVar.f32_from_int
	frame = { center_x: n(150), center_y: n(300), half_width: n(150), half_height: n(300), offset_x: n(-220), offset_y: n(-220) }
	x = GraphiteCollision.sequence_coefficients(Radial(n(100)), 0, frame)
	y = GraphiteCollision.sequence_coefficients(SquareX({ weight: n(300), center: n(-140) }), 1, frame)
	x.c == n(640000) and y.c == n(7350000)
}

expect {
	n = TableVar.f32_from_int
	world = GraphiteCollision.translate_box(collision_square, n(100), 0)
	rtl = GraphiteCollision.kern_gap(world, collision_square, n(10), n(-10), True, 1000)
	ltr = GraphiteCollision.kern_gap(collision_square, world, n(10), n(-10), False, 1000)
	rtl.stopped == 0 and ltr.stopped == 0 and rtl.gap == n(-210) and ltr.gap == n(-210)
}

expect {
	n = TableVar.f32_from_int
	world = GraphiteCollision.translate_box(collision_square, 0, n(609))
	gap = GraphiteCollision.kern_gap(collision_square, world, n(10), n(-10), True, 100)
	gap.operations == 0 and gap.stopped == 0 and gap.gap == 0x7CF0BDC2
}

expect {
	# Independent public-C-API base kerning witness: LTR retains the root
	# origin while reducing its advance and the following glyph's origin.
	n = TableVar.f32_from_int
	match collision_prepared {
		Err(_) => False
		Ok(table) => match table.program.subtables.first() {
			Err(_) => False
			Ok(sub) => {
				attrs = { ..GraphiteAttributes.none, box_starts: [0, 6, 12], bytes: [0, 0, 0, 255, 0, 255, 0, 0, 0, 255, 0, 255, 0, 0, 0, 255, 0, 255] }
				context = { table: { ..table, attributes: attrs }, sub, rtl: False }
				metric = |_, wanted, _| match wanted {
					2 => 600
					5 => 300
					_ => 0
				}
				state = GraphiteSlots.set_extra(GraphiteSlots.set_extra(collision_ink_state, 1, 3, 17), 2, 3, 0)
				result = GraphiteCollision.collisions(state, context, 9, 0, 10000, metric)
				result.stopped == 0 and GraphiteSlots.get(result.state, 1).position_x == 0 and GraphiteSlots.get(result.state, 1).advance_x == n(-110) and GraphiteSlots.get(result.state, 2).position_x == n(-110) and GraphiteSlots.get_extra(result.state, 1, 8).to_u32_wrap() == n(-210)
			}
		}
	}
}

expect {
	# Empty target ink is a margin-expanded point for cluster kerning;
	# collapsed diagonal facets do not trim its occupied-bin edge.
	n = TableVar.f32_from_int
	point = { x_min: 0, y_min: 0, x_max: 0, y_max: 0, sum_min: 0, sum_max: 0, diff_min: 0, diff_max: 0 }
	neighbor = GraphiteCollision.translate_box(collision_square, n(100), 0)
	result = GraphiteCollision.kern_gap(point, neighbor, n(10), n(-10), False, 100)
	result.stopped == 0 and result.gap == n(90)
}

expect {
	# Cached original RIGHTUP trace: the opposite diagonal order emits
	# its own five regions, rather than disabling sequencing constraints.
	n = TableVar.f32_from_int
	var $state = GraphiteSlots.set_extra(GraphiteSlots.set_extra(collision_ink_state, 1, 15, 1), 2, 15, 1)
	$state = GraphiteSlots.set_extra($state, 2, 17, 2)
	for pair in [{ field: 18, value: 100 }, { field: 19, value: 300 }, { field: 20, value: -50 }, { field: 21, value: 100 }, { field: 22, value: 150 }, { field: 23, value: 500 }] {
		$state = GraphiteSlots.set_extra($state, 1, pair.field, pair.value)
	}
	limits = { x_min: n(-1000), y_min: n(-1000), x_max: n(1000), y_max: n(1000) }
	regions = GraphiteCollision.sequence_regions($state, 2, 1, collision_square, collision_square, n(80), n(170), limits, True)
	frame = GraphiteCollision.sequence_frame(collision_square, 0, 0)
	ink = GraphiteCollision.forbidden(collision_square, collision_square, n(-80), n(-170))
	result = GraphiteCollision.solve_shift_regions(limits, 0, 0, [ink], 0, n(10), regions, frame, 10000)
	regions.len() == 5 and result.feasible and result.x == n(380) and result.y == n(380)
}
