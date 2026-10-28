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
	ShiftResult : { x : U32, y : U32, feasible : Bool, operations : U64, stopped : U64 }
	Group : { first : U64, last : U64 }
	Groups : { groups : List(Group), operations : U64, stopped : U64 }
	ShiftInput : { target : [Present(Octabox), Absent], obstacles : List(Octabox), active : Bool, current_x : U32, current_y : U32, limits : Rect, margin : U32, weight : U32, operations : U64, stopped : U64 }

	# A collision pass retains its initial offset separately from the shift
	# authored during that pass. Recovering one from the rounded sum changes
	# later positions; both components are required even between groups.
	Offset : { base_x : U32, base_y : U32, delta_x : U32, delta_y : U32 }
	MemberSpan : { start : U64, length : U64 }
	Members : [Pending, Scan, Ready({ spans : List(MemberSpan), ids : List(U64) })]
	PositionCache : [Pending, Scan, Ready({ rtl : Bool, native_rtl : Bool })]
	Work : { state : GraphiteSlots, offsets : List(Offset), roots : List(U64), ranks : List(U64), members : Members, positions : PositionCache, prefixes : List(GraphitePosition.Prefix), dirty_root : U64 }
	Worked : { work : Work, operations : U64, stopped : U64, movement : U32 }
	Prepared : { work : Work, operations : U64, stopped : U64 }

	prepare_work : GraphiteSlots, U64 -> Prepared
	prepare_work = |state, budget| {
		count = state.nodes.len()
		if count > budget {
			return { work: { state, offsets: [], roots: [], ranks: [], members: Scan, positions: Pending, prefixes: [], dirty_root: 0 }, operations: 0, stopped: 2 }
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
					return { work: { state, offsets: $offsets, roots: [], ranks: [], members: Scan, positions: Pending, prefixes: [], dirty_root: 0 }, operations: $operations, stopped: 2 }
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
					return { work: { state, offsets: $offsets, roots: [], ranks: [], members: Scan, positions: Pending, prefixes: [], dirty_root: 0 }, operations: $operations, stopped: 4 }
				}
				$cursor = parent
			}
			for item in $path {
				$roots = $roots.set(item, $root) ?? []
			}
		}
		var $cursor = state.first
		var $rank = 0
		var $sequence = False
		while $cursor != 0 and $rank < state.active {
			if $operations >= budget {
				return { work: { state, offsets: $offsets, roots: [], ranks: [], members: Scan, positions: Pending, prefixes: [], dirty_root: 0 }, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			$ranks = $ranks.set($cursor, $rank) ?? []
			if GraphiteSlots.get_extra(state, $cursor, 3).bitwise_and(17) == 1 and GraphiteSlots.get_extra(state, $cursor, 15) != 0 {
				$sequence = True
			}
			$cursor = (state.nodes.get($cursor) ?? GraphiteSlots.no_slot).next
			$rank = $rank + 1
		}
		{ work: { state, offsets: $offsets, roots: $roots, ranks: $ranks, members: if ($sequence) Pending else Scan, positions: Pending, prefixes: [], dirty_root: 0 }, operations: $operations, stopped: 0 }
	}

	# Roots and ranks are fixed throughout a positioning pass: collision
	# corrections change coordinates, never active or attachment links.
	# Group root members once, in active-list order. A low-budget call keeps
	# the original scan instead of exhausting its work just to build a cache.
	prepare_members : Work, U64 -> Prepared
	prepare_members = |work, budget| {
		match work.members {
			Pending => {}
			_ => return { work, operations: 0, stopped: 0 }
		}
		count = work.state.nodes.len()
		active = work.state.active
		if count > budget or active > (budget - count) / 2 {
			return { work: { ..work, members: Scan }, operations: 0, stopped: 0 }
		}
		var $spans = List.repeat({ start: 0, length: 0 }, count)
		var $cursor = work.state.first
		var $walked = 0
		while $cursor != 0 and $walked < active {
			root = work.roots.get($cursor) ?? 0
			span = $spans.get(root) ?? { start: 0, length: 0 }
			# Prepared root IDs index the aligned node pool.
			$spans = $spans.set(root, { ..span, length: span.length + 1 }) ?? []
			$cursor = GraphiteSlots.get(work.state, $cursor).next
			$walked = $walked + 1
		}
		var $start = 0
		for root in 0..<count {
			span = $spans.get(root) ?? { start: 0, length: 0 }
			$spans = $spans.set(root, { start: $start, length: 0 }) ?? []
			$start = $start + span.length
		}
		var $ids = List.repeat(0, $start)
		$cursor = work.state.first
		$walked = 0
		while $cursor != 0 and $walked < active {
			root = work.roots.get($cursor) ?? 0
			span = $spans.get(root) ?? { start: 0, length: 0 }
			# The counting pass reserved exactly this root's active members.
			$ids = $ids.set(span.start + span.length, $cursor) ?? []
			$spans = $spans.set(root, { ..span, length: span.length + 1 }) ?? []
			$cursor = GraphiteSlots.get(work.state, $cursor).next
			$walked = $walked + 1
		}
		{ work: { ..work, members: Ready({ spans: $spans, ids: $ids }) }, operations: count + active * 2, stopped: 0 }
	}

	# The member pool is sorted by active rank within each root span.
	member_bound : List(U64), List(U64), MemberSpan, U64, U64 -> { index : U64, operations : U64, stopped : U64 }
	member_bound = |ids, ranks, span, rank, budget| {
		var $low = span.start
		var $high = span.start + span.length
		var $operations = 0
		while $low < $high {
			if $operations >= budget {
				return { index: $low, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			mid = $low + ($high - $low) / 2
			if (ranks.get(ids.get(mid) ?? 0) ?? 0) < rank {
				$low = mid + 1
			} else {
				$high = mid
			}
		}
		{ index: $low, operations: $operations, stopped: 0 }
	}

	# Called only for an index covered by prepare_work's aligned pool.
	# The stored physical offset is rounded base + independently rounded delta.
	store_work_shift : Work, U64, U32, U32, Bool, Bool, Bool, U64 -> { work : Work, movement : U32, operations : U64 }
	store_work_shift = |work, id, x, y, feasible, rtl, native_rtl, budget| {
		{ state, offsets, roots, ranks, members, positions, prefixes, dirty_root } = work
		old = offsets.get(id) ?? { base_x: 0, base_y: 0, delta_x: 0, delta_y: 0 }
		delta_x = TableVar.f32_sub(x, old.base_x)
		delta_y = TableVar.f32_sub(y, old.base_y)
		change_x = TableVar.f32_sub(delta_x, old.delta_x)
		change_y = TableVar.f32_sub(delta_y, old.delta_y)
		movement = TableVar.f32_add(TableVar.f32_mul(change_x, change_x), TableVar.f32_mul(change_y, change_y))
		stored = { ..old, delta_x, delta_y }
		# The aligned pool and slot were checked by the pass walk.
		updated = offsets.set(id, stored) ?? []
		physical_x = TableVar.f32_add(old.base_x, delta_x)
		physical_y = TableVar.f32_add(old.base_y, delta_y)
		changed = GraphiteSlots.get_extra(state, id, 8).to_u32_wrap() != physical_x or GraphiteSlots.get_extra(state, id, 9).to_u32_wrap() != physical_y
		var $positions = positions
		var $prefixes = prefixes
		var $operations = 0
		if changed {
			match $positions {
				Pending => {
					{ cache: prepared_cache, operations: preparation_operations } = GraphitePosition.prepare_cache(state, rtl, native_rtl, budget)
					$operations = preparation_operations
					match prepared_cache {
						Absent => {
							$positions = Scan
						}
						Present(cache) => {
							$positions = Ready({ rtl: cache.rtl, native_rtl: cache.native_rtl })
							$prefixes = cache.prefixes
						}
					}
				}
				Ready(_) => {
					# Multiple independently dirty roots require a complete pass.
					if !state.positioned {
						$positions = Scan
						$prefixes = []
					}
				}
				Scan => {}
			}
		}
		{ work: { state: GraphiteCollision.store_shift(state, id, physical_x, physical_y, feasible), offsets: updated, roots, ranks, members, positions: $positions, prefixes: $prefixes, dirty_root: if (changed) (roots.get(id) ?? 0) else dirty_root }, movement, operations: $operations }
	}

	# Only SHIFT uses the single-dirty-root cache. KERN changes authored
	# advances as well and keeps the ordinary complete traversal.
	position_work : Work, Context, U64 -> Prepared
	position_work = |{ state, offsets, roots, ranks, members, positions, prefixes, dirty_root }, context, budget| {
		if state.positioned {
			return { work: { state, offsets, roots, ranks, members, positions, prefixes, dirty_root: 0 }, operations: 0, stopped: 0 }
		}
		# The mutable pool is a direct Work field, not inside the tag payload
		# inspected to choose the path. No tagged cache owner spans mutation.
		match positions {
			Ready(flags) => {
				{ state: positioned, cache: updated_cache, operations, stopped } = GraphitePosition.position_from(state, { prefixes, rtl: flags.rtl, native_rtl: flags.native_rtl }, dirty_root, context.rtl, context.sub.direction.bitwise_and(1) == 0, budget)
				match updated_cache {
					Present({ prefixes: positioned_prefixes, rtl, native_rtl }) => { work: { state: positioned, offsets, roots, ranks, members, positions: Ready({ rtl, native_rtl }), prefixes: positioned_prefixes, dirty_root: 0 }, operations, stopped }
					Absent => { work: { state: positioned, offsets, roots, ranks, members, positions: Scan, prefixes: [], dirty_root: 0 }, operations, stopped }
				}
			}
			other => {
				{ state: positioned, operations, stopped } = GraphitePosition.position_for_font(state, context.rtl, context.sub.direction.bitwise_and(1) == 0, budget)
				{ work: { state: positioned, offsets, roots, ranks, members, positions: other, prefixes, dirty_root: 0 }, operations, stopped }
			}
		}
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
		var $member_start = 0
		var $member_end = 0
		var $member_index = 0
		match work.members {
			Ready(index) => {
				span = index.spans.get(root) ?? { start: 0, length: 0 }
				first_rank = work.ranks.get(group.first) ?? 0
				last_rank = work.ranks.get(group.last) ?? 0
				low_rank = if (first_rank < last_rank) first_rank else last_rank
				high_rank = if (first_rank < last_rank) last_rank else first_rank
				low = GraphiteCollision.member_bound(index.ids, work.ranks, span, low_rank, budget)
				if low.stopped != 0 {
					return { regions: [], operations: low.operations, stopped: low.stopped }
				}
				high = GraphiteCollision.member_bound(index.ids, work.ranks, span, high_rank + 1, budget - low.operations)
				$operations = low.operations + high.operations
				if high.stopped != 0 {
					return { regions: [], operations: $operations, stopped: high.stopped }
				}
				$member_start = low.index
				$member_end = high.index
				if low.index == high.index {
					$cursor = 0
				} else {
					$member_index = if (reverse) high.index - 1 else low.index
					$cursor = index.ids.get($member_index) ?? 0
				}
			}
			_ => {}
		}
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
						if GraphiteCollision.broad_active(target, box, TableVar.f32_sub(slot.position_x, neighbor.position_x), TableVar.f32_sub(slot.position_y, neighbor.position_y), input.limits, offset.base_x, offset.base_y, input.margin) {
							before = if (reverse) (work.ranks.get($cursor) ?? 0) > rank else (work.ranks.get($cursor) ?? 0) < rank
							regions = GraphiteCollision.sequence_regions(work.state, id, $cursor, target, box, TableVar.f32_sub(neighbor.position_x, origin_x), TableVar.f32_sub(neighbor.position_y, origin_y), input.limits, before)
							for region in regions {
								$regions = $regions.append(region)
							}
						}
					}
				}
			}
			match work.members {
				Ready(index) => {
					if (reverse and $member_index == $member_start) or (!reverse and $member_index + 1 == $member_end) {
						break
					}
					$member_index = if (reverse) $member_index - 1 else $member_index + 1
					$cursor = index.ids.get($member_index) ?? 0
				}
				_ => {
					if $cursor == group.last {
						break
					}
					$cursor = if (reverse) neighbor.previous else neighbor.next
				}
			}
		}
		{ regions: $regions, operations: $operations, stopped: 0 }
	}

	# Mode zero is the initial forward sweep, one the reverse bad-target
	# retry, and two the forward good-target refinement. A pass's Work is
	# retained across all sweeps and overlapping groups.
	shift_work_once : Work, Context, Group, Bool, U64, U64, (U64, U64, I32 -> I32) -> Worked
	shift_work_once = |initial, context, group, reverse, mode, budget, base_metric| {
		{ work: member_work, operations: member_operations, stopped: _ } = GraphiteCollision.prepare_members(initial, budget)
		var $work = member_work
		backward = mode == 1
		var $id = if (backward) group.last else group.first
		end = if (backward) group.first else group.last
		walk_reverse = reverse != backward
		var $walked = 0
		var $operations = member_operations
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
				{ work: positioned_work, operations: position_operations, stopped: position_stopped } = GraphiteCollision.position_work($work, context, budget - $operations)
				$work = positioned_work
				$operations = $operations + position_operations
				if position_stopped != 0 {
					return { work: $work, operations: $operations, stopped: position_stopped, movement: $movement }
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
						if input.active or !sequence.regions.is_empty() {
							frame = GraphiteCollision.sequence_frame(box, input.current_x, input.current_y)
							solved = GraphiteCollision.solve_shift_regions(input.limits, input.current_x, input.current_y, input.obstacles, input.margin, input.weight, sequence.regions, frame, budget - $operations)
							$operations = $operations + solved.operations
							if solved.stopped != 0 {
								return { work: $work, operations: $operations, stopped: solved.stopped, movement: $movement }
							}
							{ work: stored_work, operations: stored_operations, movement: stored_movement } = GraphiteCollision.store_work_shift($work, $id, solved.x, solved.y, solved.feasible, context.rtl, context.sub.direction.bitwise_and(1) == 0, budget - $operations)
							$work = stored_work
							$operations = $operations + stored_operations
							$movement = TableVar.f32_max($movement, stored_movement)
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
		{ work: final_work, operations: final_operations, stopped: final_stopped } = GraphiteCollision.position_work($work, context, budget - $operations)
		{ work: final_work, operations: $operations + final_operations, stopped: final_stopped, movement: $movement }
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
			{ work: initial_sweep_work, operations: initial_sweep_operations, stopped: initial_sweep_stopped, movement: initial_sweep_movement } = GraphiteCollision.shift_work_once($work, context, group, reverse, 0, budget - $operations, base_metric)
			$work = initial_sweep_work
			$operations = $operations + initial_sweep_operations
			if initial_sweep_stopped != 0 {
				return { state: $work.state, operations: $operations, stopped: initial_sweep_stopped }
			}
			var $movement = initial_sweep_movement
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
				{ work: rescued_sweep_work, operations: rescued_sweep_operations, stopped: rescued_sweep_stopped, movement: _ } = GraphiteCollision.shift_work_once($work, context, group, reverse, 1, budget - $operations, base_metric)
				$work = rescued_sweep_work
				$operations = $operations + rescued_sweep_operations
				if rescued_sweep_stopped != 0 {
					return { state: $work.state, operations: $operations, stopped: rescued_sweep_stopped }
				}
				$movement = 0
				if refine {
					{ work: forward_sweep_work, operations: forward_sweep_operations, stopped: forward_sweep_stopped, movement: forward_sweep_movement } = GraphiteCollision.shift_work_once($work, context, group, reverse, 2, budget - $operations, base_metric)
					$work = forward_sweep_work
					$operations = $operations + forward_sweep_operations
					if forward_sweep_stopped != 0 {
						return { state: $work.state, operations: $operations, stopped: forward_sweep_stopped }
					}
					$movement = forward_sweep_movement
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
		input = { target: GraphiteCollision.load_box(context.table.attributes, slot.glyph, 0, base_metric), obstacles: [], active: False, current_x, current_y, limits: { x_min: number(4), y_min: number(5), x_max: number(6), y_max: number(7) }, margin: number(10), weight: number(11), operations: 0, stopped: 0 }
		target = match input.target {
			Absent => return input
			Present(box) => box
		}
		origin_x = TableVar.f32_sub(TableVar.f32_sub(slot.position_x, offset.delta_x), offset.base_x)
		origin_y = TableVar.f32_sub(TableVar.f32_sub(slot.position_y, offset.delta_y), offset.base_y)
		var $obstacles = []
		var $active = False
		var $operations = 0
		var $walked = 0
		var $neighbor_id = group.first
		while $neighbor_id != 0 and $walked < state.active {
			if $operations >= budget {
				return { ..input, obstacles: $obstacles, active: $active, operations: $operations, stopped: 2 }
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
						physical_dx = TableVar.f32_sub(slot.position_x, world_x)
						physical_dy = TableVar.f32_sub(slot.position_y, world_y)
						possible = if $parts > 1 {
							if $operations >= budget {
								return { ..input, obstacles: $obstacles, active: $active, operations: $operations, stopped: 2 }
							}
							$operations = $operations + 1
							match GraphiteCollision.load_box(context.table.attributes, glyph, 0, base_metric) {
								Absent => False
								Present(whole) => GraphiteCollision.broad_possible(target, GraphiteCollision.part_cover(whole), physical_dx, physical_dy, input.limits, offset.base_x, offset.base_y, input.margin)
							}
						} else True
						if possible {
							first_part = if ($parts == 0) 0 else 1
							for part in first_part..<($parts + 1) {
								if $operations >= budget {
									return { ..input, obstacles: $obstacles, active: $active, operations: $operations, stopped: 2 }
								}
								$operations = $operations + 1
								match GraphiteCollision.load_box(context.table.attributes, glyph, part, base_metric) {
									Absent => {}
									Present(box) => {
										if GraphiteCollision.broad_active(target, box, physical_dx, physical_dy, input.limits, offset.base_x, offset.base_y, input.margin) {
											$active = True
											dx = TableVar.f32_sub(origin_x, world_x)
											dy = TableVar.f32_sub(origin_y, world_y)
											$obstacles = $obstacles.append(GraphiteCollision.forbidden(target, box, dx, dy))
										}
									}
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
		{ ..input, obstacles: $obstacles, active: $active, operations: $operations, stopped: 0 }
	}

	# Cover every encoded subbox, without trusting the stored whole-glyph
	# diagonal approximation to contain it. Endpoints use the exact same
	# normalized arithmetic as load_box, including its binary32 rounding.
	part_cover : Octabox -> Octabox
	part_cover = |whole| {
		x_span = TableVar.f32_sub(whole.x_max, whole.x_min)
		y_span = TableVar.f32_sub(whole.y_max, whole.y_min)
		span = TableVar.f32_add(x_span, y_span)
		sum_base = TableVar.f32_add(whole.x_min, whole.y_min)
		diff_base = TableVar.f32_sub(whole.x_min, whole.y_max)
		{ x_min: GraphiteCollision.coordinate(whole.x_min, x_span, 0), x_max: GraphiteCollision.coordinate(whole.x_min, x_span, 255), y_min: GraphiteCollision.coordinate(whole.y_min, y_span, 0), y_max: GraphiteCollision.coordinate(whole.y_min, y_span, 255), sum_min: GraphiteCollision.coordinate(sum_base, span, 0), sum_max: GraphiteCollision.coordinate(sum_base, span, 255), diff_min: GraphiteCollision.coordinate(diff_base, span, 0), diff_max: GraphiteCollision.coordinate(diff_base, span, 255) }
	}

	# Necessary conditions only: raw cover intervals enclose every part's
	# projected intervals. Its orthogonal gap is no larger, so its padding
	# is no smaller. The original exact guard still decides each candidate.
	broad_possible : Octabox, Octabox, U32, U32, Rect, U32, U32, U32 -> Bool
	broad_possible = |target, cover, dx, dy, limits, base_x, base_y, margin| {
		add = TableVar.f32_add
		sub = TableVar.f32_sub
		lt = TableVar.f32_lt
		window = { x_min: limits.x_max.bitwise_xor(0x80000000), y_min: sub(limits.y_min, base_y), x_max: sub(limits.x_max, base_x), y_max: sub(limits.y_max, base_y) }
		projected_min_x = TableVar.f32_min(window.x_min, limits.x_min)
		box = GraphiteCollision.forbidden(target, cover, dx, dy)
		for axis in 0..<4 {
			orthogonal = match axis {
				0 => { low: box.y_min, high: box.y_max }
				1 => { low: box.x_min, high: box.x_max }
				2 => { low: box.diff_min, high: box.diff_max }
				_ => { low: box.sum_min, high: box.sum_max }
			}
			orth = TableVar.f32_min(orthogonal.high, TableVar.f32_max(orthogonal.low, 0))
			distance = TableVar.f32_max(sub(0, orth), sub(orth, 0))
			gap = if (axis < 2) distance else TableVar.f32_mul(distance, 0x3F3504F3)
			if !lt(margin, gap) {
				range = match axis {
					0 => { low: projected_min_x, high: window.x_max, span: sub(target.x_max, target.x_min), box_low: box.x_min, box_high: box.x_max }
					1 => { low: window.y_min, high: window.y_max, span: sub(target.y_max, target.y_min), box_low: box.y_min, box_high: box.y_max }
					2 => { low: add(projected_min_x, window.y_min), high: add(window.x_max, window.y_max), span: sub(target.sum_max, target.sum_min), box_low: box.sum_min, box_high: box.sum_max }
					_ => { low: sub(projected_min_x, window.y_max), high: sub(window.x_max, window.y_min), span: sub(target.diff_max, target.diff_min), box_low: box.diff_min, box_high: box.diff_max }
				}
				remaining = sub(margin, gap)
				padding = if (axis < 2) remaining else TableVar.f32_mul(remaining, 0x3FB504F3)
				if !lt(add(range.high, add(range.span, padding)), range.box_low) and !lt(add(range.box_high, padding), range.low) {
					return True
				}
			}
		}
		False
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

	# Normal projections use physical displacement. The coarse overlap gates
	# recover the prior-offset-free point before comparing with the retained
	# base-adjusted window; current-pass displacement remains independent.
	# This search window differs from the final movement slices.
	broad_active : Octabox, Octabox, U32, U32, Rect, U32, U32, U32 -> Bool
	broad_active = |target, neighbor, dx, dy, limits, base_x, base_y, margin| {
		add = TableVar.f32_add
		sub = TableVar.f32_sub
		lt = TableVar.f32_lt
		window = { x_min: limits.x_max.bitwise_xor(0x80000000), y_min: sub(limits.y_min, base_y), x_max: sub(limits.x_max, base_x), y_max: sub(limits.y_max, base_y) }
		rough_dx = sub(dx, base_x)
		rough_dy = sub(dy, base_y)
		x_overlap = !lt(sub(neighbor.y_max, rough_dy), sub(window.y_min, margin)) and !lt(add(window.y_max, margin), sub(neighbor.y_min, rough_dy))
		y_overlap = !lt(sub(neighbor.x_max, rough_dx), sub(window.x_min, margin)) and !lt(add(window.x_max, margin), sub(neighbor.x_min, rough_dx))
		if !x_overlap and !y_overlap {
			return False
		}
		projected_min_x = TableVar.f32_min(window.x_min, limits.x_min)
		box = GraphiteCollision.forbidden(target, neighbor, dx, dy)
		for axis in 0..<4 {
			if !((axis == 0 and !x_overlap) or (axis == 1 and !y_overlap)) {
				p = GraphiteCollision.project(box, axis, 0, 0)
				if !lt(margin, p.gap) {
					range = match axis {
						0 => { low: projected_min_x, high: window.x_max, span: sub(target.x_max, target.x_min) }
						1 => { low: window.y_min, high: window.y_max, span: sub(target.y_max, target.y_min) }
						2 => { low: add(projected_min_x, window.y_min), high: add(window.x_max, window.y_max), span: sub(target.sum_max, target.sum_min) }
						_ => { low: sub(projected_min_x, window.y_max), high: sub(window.x_max, window.y_min), span: sub(target.diff_max, target.diff_min) }
					}
					remaining = sub(margin, p.gap)
					padding = if (axis < 2) remaining else TableVar.f32_mul(remaining, 0x3FB504F3)
					if !lt(add(range.high, add(range.span, padding)), p.low) and !lt(add(p.high, padding), range.low) {
						return True
					}
				}
			}
		}
		False
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
			for region in regions {
				if $operations >= budget {
					return { x: current_x, y: current_y, feasible: False, operations: $operations, stopped: 2 }
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
				{ bounds: if (left_down) { x_min: outer.x_min, y_min: sub(c, h), x_max: b, y_max: outer.y_max } else { x_min: b, y_min: outer.y_min, x_max: outer.x_max, y_max: sub(c, h) }, penalty: Radial(number(21)) },
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

	part_count : GraphiteAttributes, U64 -> U64
	part_count = |attributes, glyph| {
		start = match attributes.box_starts.get(glyph) {
			Err(_) => return 0
			Ok(at) => at
		}
		bitmap = Bytes.u16(attributes.bytes, start)
		var $count = 0
		for bit in 0..<16 {
			if bitmap.bitwise_and((1.U64).shl_wrap(bit.to_u8_wrap())) != 0 {
				$count = $count + 1
			}
		}
		$count
	}

	KernPart : { box : Octabox, whole_min_y : U32, whole_max_y : U32 }
	YFrame : { min_y : U32, max_y : U32 }
	ClusterBoxes : { boxes : List(KernPart), operations : U64, stopped : U64 }
	cluster_boxes : Work, Context, U64, U64, (U64, U64, I32 -> I32) -> ClusterBoxes
	cluster_boxes = |work, context, root, budget, base_metric| {
		var $boxes = []
		var $id = work.state.first
		var $operations = 0
		var $walked = 0
		while $id != 0 and $walked < work.state.active {
			if $operations >= budget {
				return { boxes: $boxes, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			$walked = $walked + 1
			slot = GraphiteSlots.get(work.state, $id)
			if (work.roots.get($id) ?? 0) == root {
				match GraphiteCollision.load_box(context.table.attributes, slot.glyph, 0, base_metric) {
					Absent => {}
					Present(whole) => {
						min_y = TableVar.f32_add(whole.y_min, slot.position_y)
						max_y = TableVar.f32_add(whole.y_max, slot.position_y)
						parts = GraphiteCollision.part_count(context.table.attributes, slot.glyph)
						first_part = if (parts == 0) 0 else 1
						for part in first_part..<(parts + 1) {
							if $operations >= budget {
								return { boxes: $boxes, operations: $operations, stopped: 2 }
							}
							$operations = $operations + 1
							match GraphiteCollision.load_box(context.table.attributes, slot.glyph, part, base_metric) {
								Absent => {}
								Present(box) => {
									$boxes = $boxes.append({ box: GraphiteCollision.translate_box(box, slot.position_x, slot.position_y), whole_min_y: min_y, whole_max_y: max_y })
								}
							}
						}
					}
				}
			}
			$id = slot.next
		}
		{ boxes: $boxes, operations: $operations, stopped: 0 }
	}

	kern_capacity : U32, U32, U32 -> I64
	kern_capacity = |min_y, max_y, width| {
		span = TableVar.f32_add(TableVar.f32_sub(max_y, min_y), TableVar.f32_from_int(2))
		TableVar.f32_floor(TableVar.f32_add(TableVar.f32_mul(TableVar.f32_div(span, width), 0x3FC00000), TableVar.f32_one))
	}

	# Neighbor eligibility uses its whole glyph bounds and the finite
	# sampling frame, independently of actual part/target-cell overlap.
	kern_neighbor_in_frame : U32, U32, U32, U32, U32, I64 -> Bool
	kern_neighbor_in_frame = |whole_min, whole_max, min_y, width, margin, capacity| {
		lower = TableVar.f32_sub(min_y, TableVar.f32_mul(TableVar.f32_from_int(2), margin))
		first = TableVar.f32_floor(TableVar.f32_div(TableVar.f32_add(TableVar.f32_sub(whole_min, min_y), TableVar.f32_one), width))
		!TableVar.f32_lt(whole_max, lower) and first < capacity
	}

	# Apply one root's advance correction. The target cluster's occupied
	# bins share one vertical origin; external spaces reserve their advance
	# independently of ink. Occupied bins are bounded before allocation.
	kern_cluster : Work, Context, U64, Group, Bool, YFrame, U64, (U64, U64, I32 -> I32) -> Worked
	kern_cluster = |initial, context, id, group, reverse, frame, budget, base_metric| {
		if id == group.last {
			return { work: initial, operations: 0, stopped: 0, movement: 0 }
		}
		native_rtl = context.sub.direction.bitwise_and(1) == 0
		# Phase3 samples the pass-entry physical positions. Authored advances
		# and flags may change, but positions are refreshed only after the
		# complete phase, including native-LTR promotion offset suppression.
		var $operations = 0
		var $work = initial

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
		# A lower bound on every RTL edge, or an upper bound on every
		# LTR edge. Each facet clips to this part's rectangular extent.
		var $edge_bound = Absent
		for part in cluster.boxes {
			box = part.box
			if $operations >= budget {
				return { work: $work, operations: $operations, stopped: 2, movement: 0 }
			}
			$operations = $operations + 1
			edge = if (native_rtl) TableVar.f32_sub(box.x_min, m) else TableVar.f32_add(box.x_max, m)
			$edge_bound = Present(
				match $edge_bound {
					Absent => edge
					Present(previous) => if (native_rtl) TableVar.f32_min(previous, edge) else TableVar.f32_max(previous, edge)
				},
			)
		}
		cache_min_y = TableVar.f32_sub(frame.min_y, m)
		cache_max_y = TableVar.f32_add(frame.max_y, m)
		cache = GraphiteCollision.target_bins(cluster.boxes, m, cache_min_y, cache_max_y, native_rtl, budget - $operations)
		capacity = GraphiteCollision.kern_capacity(cache_min_y, cache_max_y, cache.width)
		$operations = $operations + cache.operations
		if cache.stopped != 0 {
			return { work: $work, operations: $operations, stopped: cache.stopped, movement: 0 }
		}
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
			if (initial.roots.get($cursor) ?? 0) != id {
				if GraphiteCollision.kerning_space(neighbor.glyph, flags, base_metric) {
					$space = TableVar.f32_add($space, TableVar.f32_mul(TableVar.f32_from_int(2), neighbor.advance_x))
				} else if flags.bitwise_and(2) == 0 {
					# Every part remains inside the validated whole glyph box.
					# Monotonic binary32 subtraction therefore gives a lower
					# bound on its possible gap, including whitespace reserve.
					# Strict inequality preserves all equal-gap tie behavior.
					whole_min = TableVar.f32_add(TableVar.f32_from_int(base_metric(neighbor.glyph, 3, 0).to_i64()), neighbor.position_y)
					whole_max = TableVar.f32_add(TableVar.f32_from_int(base_metric(neighbor.glyph, 2, 0).to_i64()), neighbor.position_y)
					eligible = GraphiteCollision.kern_neighbor_in_frame(whole_min, whole_max, cache_min_y, cache.width, m, capacity)
					var $empty_whole = False
					if eligible and !native_rtl {
						intersection = GraphiteCollision.bins_intersect_y(cache, whole_min, whole_max, budget - $operations)
						$operations = $operations + intersection.operations
						if intersection.stopped != 0 {
							return { work: $work, operations: $operations, stopped: intersection.stopped, movement: 0 }
						}
						$empty_whole = !intersection.present
					}
					if $empty_whole {
						match (cache.bound, GraphiteCollision.load_box(context.table.attributes, neighbor.glyph, 0, base_metric)) {
							(Present(bound), Present(whole)) => {
								# Pinned public C-API controls establish this ordered
								# LTR update. Finite comparisons take a minimum;
								# a later eligible whole glyph missing every finite
								# target cell raises that result to the sampled bound.
								left = TableVar.f32_add(whole.x_min, neighbor.position_x)
								fallback = TableVar.f32_sub(TableVar.f32_add(bound, m), left)
								$gap = TableVar.f32_max($gap, TableVar.f32_sub(fallback, $space))
								$external = True
							}
							(Absent, Present(_)) => {
								$external = True
							}
							_ => {}
						}
					}
					pruned = if (!eligible or $empty_whole) True else $external and match $edge_bound {
						Absent => False
						Present(bound) => {
							glyph_edge = TableVar.f32_add(TableVar.f32_from_int(base_metric(neighbor.glyph, if (native_rtl) 5 else 4, 0).to_i64()), neighbor.position_x)
							geometric_bound = if (native_rtl) TableVar.f32_sub(bound, glyph_edge) else TableVar.f32_sub(glyph_edge, bound)
							# bins_gap also includes its finite initial sentinel
							# in the minimum; preserve that part of its bound.
							gap_bound = TableVar.f32_min(0x7CF0BDC2, geometric_bound)
							TableVar.f32_lt($gap, TableVar.f32_sub(gap_bound, $space))
						}
					}
					if !pruned {
						parts = GraphiteCollision.part_count(context.table.attributes, neighbor.glyph)
						first_part = if (parts == 0) 0 else 1
						for part in first_part..<(parts + 1) {
							if $operations >= budget {
								return { work: $work, operations: $operations, stopped: 2, movement: 0 }
							}
							$operations = $operations + 1

							match GraphiteCollision.load_box(context.table.attributes, neighbor.glyph, part, base_metric) {
								Absent => {}
								Present(box) => {
									$external = True
									world = GraphiteCollision.translate_box(box, neighbor.position_x, neighbor.position_y)
									pair = GraphiteCollision.bins_gap(cache, world, native_rtl, budget - $operations)
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
		needed = if (native_rtl) $gap.bitwise_xor(0x80000000) else $gap
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

	# Phase3 reserves explicit SPACE and the origin-zero bounding box
	# even when IGNORE is also set. A nonzero point or a zero-area line
	# is still an ink obstacle; emptiness is not just zero extent.
	kerning_space : U64, I32, (U64, U64, I32 -> I32) -> Bool
	kerning_space = |glyph, flags, metric| flags.bitwise_and(128) != 0 or (metric(glyph, 4, 0) == 0 and metric(glyph, 3, 0) == 0 and metric(glyph, 5, 0) == 0 and metric(glyph, 2, 0) == 0)

	visit_y_frame : [Present(YFrame), Absent], U32, U32 -> YFrame
	visit_y_frame = |previous, min_y, max_y| match previous {
		Absent => { min_y, max_y }
		Present(frame) => { min_y: TableVar.f32_min(frame.min_y, min_y), max_y: TableVar.f32_max(frame.max_y, max_y) }
	}

	kerning : GraphiteSlots, Context, U64, U64, (U64, U64, I32 -> I32) -> Applied
	kerning = |initial, context, pass_flags, budget, base_metric| {
		if pass_flags.bitwise_and(8) == 0 {
			return { state: initial, operations: 0, stopped: 0 }
		}
		reverse = (context.rtl != (context.sub.direction.bitwise_and(1) == 0)) != (pass_flags.bitwise_and(32) != 0)
		# Collision-shift groups do not bound phase3 kerning. Its target
		# and neighbor scans cross START/END markers over the whole run.
		group = { first: if (reverse) initial.last else initial.first, last: if (reverse) initial.first else initial.last }
		{ state: positioned_state, operations: position_operations, stopped: position_stopped } = GraphitePosition.position_for_font(initial, context.rtl, context.sub.direction.bitwise_and(1) == 0, budget)
		if position_stopped != 0 {
			return { state: positioned_state, operations: position_operations, stopped: position_stopped }
		}
		prepared = GraphiteCollision.prepare_work(positioned_state, budget - position_operations)
		var $work = prepared.work
		var $operations = position_operations + prepared.operations
		if prepared.stopped != 0 {
			return { state: $work.state, operations: $operations, stopped: prepared.stopped }
		}
		var $frame = Absent
		var $id = group.first
		var $walked = 0
		while $id != 0 and $walked < $work.state.active {
			if $operations >= budget {
				return { state: $work.state, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			$walked = $walked + 1
			slot = GraphiteSlots.get($work.state, $id)
			match GraphiteCollision.load_box(context.table.attributes, slot.glyph, 0, base_metric) {
				Absent => {}
				Present(whole) => {
					$frame = Present(GraphiteCollision.visit_y_frame($frame, TableVar.f32_add(whole.y_min, slot.position_y), TableVar.f32_add(whole.y_max, slot.position_y)))
				}
			}

			flags = GraphiteSlots.get_extra($work.state, $id, 3)
			if flags.bitwise_and(17) == 17 {
				if slot.parent != 0 {
					# Promotion follows the scan. An already visited parent
					# does not retroactively become a kerning target.
					parent_flags = GraphiteSlots.get_extra($work.state, slot.parent, 3)
					promoted = GraphiteSlots.set_extra($work.state, slot.parent, 3, parent_flags.bitwise_or(17))
					$work = { ..$work, state: { ..promoted, positioned: promoted.positioned and parent_flags.bitwise_and(16) != 0 } }
				} else {
					result = match $frame {
						Absent => { work: $work, operations: 0, stopped: 0, movement: 0 }
						Present(frame) => GraphiteCollision.kern_cluster($work, context, $id, group, reverse, frame, budget - $operations, base_metric)
					}
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

	# Select the right facet at the cell center, retaining the upper-edge
	# sample association and applying the target margin after the facet.
	kern_right_cell : Octabox, U32, U32, U32 -> U32
	kern_right_cell = |box, high, midpoint, margin| {
		corner = TableVar.f32_sub(box.sum_max, box.diff_max)
		facet = if (!TableVar.f32_lt(corner, midpoint)) TableVar.f32_add(box.diff_max, high) else TableVar.f32_sub(box.sum_max, high)
		TableVar.f32_min(TableVar.f32_add(box.x_max, margin), TableVar.f32_add(facet, margin))
	}

	KernBin : { edge : U32, present : Bool }
	TargetBins : { bins : List(KernBin), start : I64, width : U32, min_y : U32, bound : [Present(U32), Absent], operations : U64, stopped : U64 }

	# Cache the target union once. Combining target edges before scanning
	# neighbors avoids a target-parts × neighbor-parts × bins work product.
	target_bins : List(KernPart), U32, U32, U32, Bool, U64 -> TargetBins
	target_bins = |parts, margin, min_y, max_y, rtl, budget| {
		width = TableVar.f32_div(TableVar.f32_mul(TableVar.f32_from_int(2), margin), TableVar.f32_from_int(3))
		index = |y| TableVar.f32_floor(TableVar.f32_div(TableVar.f32_add(TableVar.f32_sub(y, min_y), TableVar.f32_one), width))
		# The cache frame follows visited slots. Each glyph's whole bounds
		# limit margin expansion of its own parts; drawing also stays within
		# the reference frame's finite vector. Only occupied bins are stored.
		capacity = GraphiteCollision.kern_capacity(min_y, max_y, width)
		last_index = |part| {
			whole_cap = index(part.whole_max_y) + 1
			cap = if (whole_cap < 0) 0 else whole_cap
			value = TableVar.f32_floor(TableVar.f32_div(TableVar.f32_add(TableVar.f32_add(TableVar.f32_sub(part.box.y_max, min_y), margin), TableVar.f32_one), width))
			bounded = if (value > cap) cap else value
			if (bounded >= capacity) capacity - 1 else bounded
		}
		first_index = |part| {
			cap = index(part.whole_min_y)
			value = TableVar.f32_floor(TableVar.f32_div(TableVar.f32_add(TableVar.f32_sub(TableVar.f32_sub(part.box.y_min, min_y), margin), TableVar.f32_one), width))
			bounded = if (value < cap) cap else value
			if (bounded < 0) 0 else bounded
		}

		var $bounds = Absent
		var $operations = 0
		for part in parts {
			if $operations >= budget {
				return { bins: [], start: 0, width, min_y, bound: Absent, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			first = first_index(part)
			last = last_index(part)
			# The lower sentinel can leave an otherwise finite span empty.
			# Test its order before converting its length to an unsigned count.
			if last >= first {
				$bounds = Present(
					match $bounds {
						Absent => { first, last }
						Present(previous) => { first: if (first < previous.first) first else previous.first, last: if (last > previous.last) last else previous.last }
					},
				)
			}
		}
		bounds = match $bounds {
			Absent => return { bins: [], start: 0, width, min_y, bound: Absent, operations: $operations, stopped: 0 }
			Present(value) => value
		}
		count = (bounds.last - bounds.first).to_u64_wrap() + 1
		if count > budget - $operations {
			return { bins: [], start: bounds.first, width, min_y, bound: Absent, operations: $operations, stopped: 2 }
		}
		var $bins = List.repeat({ edge: 0, present: False }, count)
		var $bound = Absent
		$operations = $operations + count
		for part in parts {
			first = first_index(part)
			last = last_index(part)
			if last >= first {
				for offset in 0..<((last - first).to_u64_wrap() + 1) {
					if $operations >= budget {
						return { bins: $bins, start: bounds.first, width, min_y, bound: $bound, operations: $operations, stopped: 2 }
					}
					$operations = $operations + 1
					i = first + offset.to_i64_wrap()
					low = TableVar.f32_sub(TableVar.f32_add(min_y, TableVar.f32_mul(TableVar.f32_from_int(i), width)), TableVar.f32_one)
					high = TableVar.f32_add(low, width)
					# Right facets are chosen at the cell midpoint, then
					# evaluated at its upper sample, as for RTL neighbors.
					edge = if rtl or (part.box.x_min == part.box.x_max and part.box.y_min == part.box.y_max) {
						GraphiteCollision.kern_edge(part.box, low, high, margin, rtl)
					} else {
						midpoint = TableVar.f32_add(TableVar.f32_mul(TableVar.f32_from_int(2), TableVar.f32_sub(min_y, TableVar.f32_one)), TableVar.f32_mul(TableVar.f32_from_int(2 * i + 1), width))
						GraphiteCollision.kern_right_cell(part.box, high, midpoint, margin)
					}
					at = (i - bounds.first).to_u64_wrap()
					previous = $bins.get(at) ?? crash "checked target bin index"
					combined = if (!previous.present) edge else if (rtl) TableVar.f32_min(previous.edge, edge) else TableVar.f32_max(previous.edge, edge)
					$bins = $bins.set(at, { edge: combined, present: True }) ?? []
					$bound = Present(
						match $bound {
							Absent => combined
							Present(previous_bound) => if (rtl) TableVar.f32_min(previous_bound, combined) else TableVar.f32_max(previous_bound, combined)
						},
					)
				}
			}
		}
		{ bins: $bins, start: bounds.first, width, min_y, bound: $bound, operations: $operations, stopped: 0 }
	}

	# The empty-comparison rule concerns whole-glyph vertical coverage of
	# finite target cells. A hole inside the cached span is still empty;
	# an empty actual sub-box inside a qualifying whole glyph is not.
	bins_intersect_y : TargetBins, U32, U32, U64 -> { present : Bool, operations : U64, stopped : U64 }
	bins_intersect_y = |target, min_y, max_y, budget| {
		if target.bins.is_empty() {
			return { present: False, operations: 0, stopped: 0 }
		}
		index = |y| TableVar.f32_floor(TableVar.f32_div(TableVar.f32_add(TableVar.f32_sub(y, target.min_y), TableVar.f32_one), target.width))
		first = if (index(min_y) > target.start) index(min_y) else target.start
		cache_last = target.start + target.bins.len().to_i64_wrap() - 1
		last = if (index(max_y) < cache_last) index(max_y) else cache_last
		var $operations = 0
		if last >= first {
			for offset in 0..<((last - first).to_u64_wrap() + 1) {
				if $operations >= budget {
					return { present: False, operations: $operations, stopped: 2 }
				}
				$operations = $operations + 1
				bin = target.bins.get((first - target.start).to_u64_wrap() + offset) ?? crash "checked whole-neighbor bin index"
				if bin.present {
					return { present: True, operations: $operations, stopped: 0 }
				}
			}
		}
		{ present: False, operations: $operations, stopped: 0 }
	}

	bins_gap : TargetBins, Octabox, Bool, U64 -> KernGap
	bins_gap = |target, neighbor, rtl, budget| {
		if target.bins.is_empty() {
			return { gap: 0x7CF0BDC2, operations: 0, stopped: 0 }
		}
		index = |y| TableVar.f32_floor(TableVar.f32_div(TableVar.f32_add(TableVar.f32_sub(y, target.min_y), TableVar.f32_one), target.width))
		neighbor_first = index(neighbor.y_min)
		neighbor_last = index(neighbor.y_max)
		cache_last = target.start + target.bins.len().to_i64_wrap() - 1
		first = if (neighbor_first > target.start) neighbor_first else target.start
		last = if (neighbor_last < cache_last) neighbor_last else cache_last
		var $gap = 0x7CF0BDC2
		var $operations = 0
		if last < first {
			return { gap: $gap, operations: 0, stopped: 0 }
		}
		# Select the right-hand facet by each cell's midpoint. SUM−DIFF
		# is twice the Y coordinate of their intersection; evaluate the
		# selected facet at the cell's upper sample, then clip to xMax.
		corner = TableVar.f32_sub(neighbor.sum_max, neighbor.diff_max)
		midpoint_base = TableVar.f32_mul(TableVar.f32_from_int(2), TableVar.f32_sub(target.min_y, TableVar.f32_one))
		for offset in 0..<((last - first).to_u64_wrap() + 1) {
			if $operations >= budget {
				return { gap: $gap, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			i = first + offset.to_i64_wrap()
			bin = target.bins.get((i - target.start).to_u64_wrap()) ?? crash "checked neighbor bin index"
			if bin.present {
				low = TableVar.f32_sub(TableVar.f32_add(target.min_y, TableVar.f32_mul(TableVar.f32_from_int(i), target.width)), TableVar.f32_one)
				high = TableVar.f32_add(low, target.width)
				edge = if rtl {
					# Preserve this expanded binary32 association. Computing
					# 2*low+width fails the exact-margin101 oracle boundary.
					# f32_floor bounds i so doubling it remains within I64.
					midpoint = TableVar.f32_add(midpoint_base, TableVar.f32_mul(TableVar.f32_from_int(2 * i + 1), target.width))
					facet = if (!TableVar.f32_lt(corner, midpoint)) TableVar.f32_add(neighbor.diff_max, high) else TableVar.f32_sub(neighbor.sum_max, high)
					TableVar.f32_min(neighbor.x_max, facet)
				} else {
					GraphiteCollision.kern_edge(neighbor, low, high, 0, !rtl)
				}
				gap = if (rtl) TableVar.f32_sub(bin.edge, edge) else TableVar.f32_sub(edge, bin.edge)
				$gap = TableVar.f32_min($gap, gap)
			}
		}
		{ gap: $gap, operations: $operations, stopped: 0 }
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
		# An initially empty diagonal retains the endpoint selected by
		# ordered comparisons against the unconstrained minimum (zero).
		# The reference's negative-only witness selects the upper endpoint;
		# a positive-only slice selects the lower one. This is a derived
		# search rule, not a repair of the font's stored movement bounds.
		if axis >= 2 and TableVar.f32_lt(slice.high, slice.low) {
			value = if (TableVar.f32_lt(0, slice.low)) slice.low else if (TableVar.f32_lt(slice.high, 0)) slice.high else 0
			{ ..slice, low: value, high: value }
		} else {
			{ ..slice, high: TableVar.f32_max(slice.low, slice.high) }
		}
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

# Source-only numerical fixtures share a single whole-glyph frame.
collision_target_bins = |parts, margin, min_y, max_y, rtl, budget|
	GraphiteCollision.target_bins(parts.map(|box| { box, whole_min_y: TableVar.f32_add(min_y, margin), whole_max_y: max_y }), margin, min_y, TableVar.f32_add(max_y, margin), rtl, budget)

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

expect {
	# Independent original broad-window endpoints; clipping against the
	# final movement slices would incorrectly call all these far hits misses.
	n = TableVar.f32_from_int
	limits = { x_min: n(-100), y_min: n(-100), x_max: n(100), y_max: n(100) }
	GraphiteCollision.broad_active(collision_square, collision_square, n(-850), 0, limits, 0, 0, 0) and !GraphiteCollision.broad_active(collision_square, collision_square, n(-851), 0, limits, 0, 0, 0)
}
expect {
	n = TableVar.f32_from_int
	limits = { x_min: n(-500), y_min: n(-300), x_max: n(-101), y_max: n(-20) }
	GraphiteCollision.broad_active(collision_square, collision_square, n(199), 0, limits, 0, 0, 0) and !GraphiteCollision.broad_active(collision_square, collision_square, n(200), 0, limits, 0, 0, 0) and !GraphiteCollision.broad_active(collision_square, collision_square, n(100), 0, limits, 0, 0, 0)
}
expect {
	n = TableVar.f32_from_int
	limits = { x_min: n(-100), y_min: n(-100), x_max: n(100), y_max: n(100) }
	GraphiteCollision.broad_active(collision_square, collision_square, n(-750), 0, limits, n(200), 0, 0) and !GraphiteCollision.broad_active(collision_square, collision_square, n(-751), 0, limits, n(200), 0, 0)
}
expect {
	n = TableVar.f32_from_int
	limits = { x_min: n(-100), y_min: n(-100), x_max: n(100), y_max: n(100) }
	!GraphiteCollision.broad_active(collision_square, collision_square, n(-851), 0, limits, 0, 0, n(1)) and GraphiteCollision.broad_active(collision_square, collision_square, n(-851), 0, limits, 0, 0, n(10)) and GraphiteCollision.broad_active(collision_square, collision_square, n(-400), n(-150), limits, 0, 0, n(50)) and !GraphiteCollision.broad_active(collision_square, collision_square, n(-400), n(-151), limits, 0, 0, n(50))
}

expect {
	# Independent margin challenge: the X guard expands its physical
	# reach by the authored margin, including the exact endpoint.
	n = TableVar.f32_from_int
	limits = { x_min: n(-1000), y_min: n(-1000), x_max: n(1000), y_max: n(1000) }
	GraphiteCollision.broad_active(collision_square, collision_square, n(-1601), 0, limits, 0, 0, n(50)) and GraphiteCollision.broad_active(collision_square, collision_square, n(-1650), 0, limits, 0, 0, n(50)) and !GraphiteCollision.broad_active(collision_square, collision_square, n(-1651), 0, limits, 0, 0, n(50)) and GraphiteCollision.broad_active(collision_square, collision_square, n(-2100), 0, limits, 0, 0, n(500)) and !GraphiteCollision.broad_active(collision_square, collision_square, n(-2101), 0, limits, 0, 0, n(500))
}

expect {
	# Original half-left TARGET subbox changes phase3 advance from −110
	# to 40.588241577..., pinned by raw public CAPI bits 1109547612.
	match collision_prepared {
		Err(_) => False
		Ok(table) => match table.program.subtables.first() {
			Err(_) => False
			Ok(sub) => {
				attrs = { ..GraphiteAttributes.none, box_starts: [0, 6, 20], bytes: [0, 0, 0, 255, 0, 255, 0, 1, 0, 255, 0, 255, 0, 127, 0, 255, 0, 255, 0, 255, 0, 0, 0, 255, 0, 255] }
				context = { table: { ..table, attributes: attrs }, sub, rtl: False }
				metric = |_, wanted, _| match wanted {
					2 => 600
					5 => 300
					_ => 0
				}
				state = GraphiteSlots.set_extra(GraphiteSlots.set_extra(collision_ink_state, 1, 3, 17), 2, 3, 0)
				result = GraphiteCollision.collisions(state, context, 9, 0, 10000, metric)
				result.stopped == 0 and GraphiteSlots.get(result.state, 1).advance_x == 1109547612
			}
		}
	}
}

expect {
	# Bin capacity is checked against the remaining work before allocation.
	n = TableVar.f32_from_int
	cache = collision_target_bins([collision_square], n(10), n(-10), n(600), True, 4)
	cache.stopped == 2 and cache.bins.is_empty() and cache.operations == 1
}

expect {
	# Original top-half target control: lower occupancy extends by the
	# margin, while the bin frame remains the whole glyph's −10 origin.
	n = TableVar.f32_from_int
	top = { ..collision_square, y_min: GraphiteCollision.coordinate(0, n(600), 127) }
	cache = collision_target_bins([top], n(10), n(-10), n(600), True, 1000)
	cache.stopped == 0 and cache.start == 44 and cache.bins.len() == 49
}

# Original documented Glat metrics for the isolated Awami final-pass
# witness. Copied bytes contain only four glyph approximation records;
# no test font or test helper is imported into the package.
awami_kerning_boxes = {
	..GraphiteAttributes.none,
	box_starts: [0, 6, 60, 130],
	bytes: [0, 0, 4, 251, 32, 224, 0, 63, 18, 252, 71, 219, 1, 44, 20, 38, 20, 34, 156, 173, 200, 254, 218, 254, 213, 252, 72, 96, 94, 180, 0, 61, 27, 95, 190, 217, 189, 241, 93, 218, 121, 225, 84, 183, 20, 94, 0, 30, 19, 46, 173, 208, 180, 243, 26, 93, 70, 134, 170, 215, 0, 255, 18, 252, 19, 184, 4, 19, 193, 229, 77, 99, 20, 36, 91, 130, 34, 140, 69, 134, 117, 141, 5, 91, 0, 101, 24, 93, 63, 142, 170, 242, 124, 193, 161, 217, 141, 184, 1, 41, 101, 151, 43, 73, 41, 85, 130, 186, 87, 148, 116, 163, 124, 165, 233, 255, 178, 253, 217, 252, 153, 178, 0, 24, 151, 193, 59, 86, 27, 55, 255, 255, 0, 241, 57, 175, 43, 51, 182, 188, 137, 144, 62, 66, 12, 47, 140, 153, 99, 119, 75, 92, 146, 160, 221, 243, 199, 216, 60, 74, 34, 106, 175, 182, 130, 158, 63, 84, 118, 137, 185, 219, 163, 192, 65, 89, 8, 32, 44, 61, 32, 52, 135, 152, 99, 118, 182, 214, 155, 183, 63, 85, 51, 99, 182, 209, 140, 174, 61, 81, 9, 40, 61, 107, 44, 85, 104, 142, 11, 43, 107, 140, 76, 109, 82, 114, 160, 255, 193, 255, 183, 241, 57, 108, 137, 160, 189, 221, 172, 202, 68, 93, 17, 64, 153, 166, 109, 133, 69, 84, 26, 83, 166, 175, 121, 146, 65, 81, 1, 24, 0, 30, 1, 28, 155, 175, 6, 28, 30, 44, 23, 39, 146, 160],
}

awami_kerning_metric = |glyph, wanted, _level| {
	box = match glyph {
		0 => { xmin: 108, ymin: 141, xmax: 367, ymax: 1751 }
		1 => { xmin: -281, ymin: 8, xmax: 485, ymax: 1900 }
		2 => { xmin: -95, ymin: 106, xmax: 1263, ymax: 964 }
		_ => { xmin: 58, ymin: -1109, xmax: 1134, ymax: 1177 }
	}
	match wanted {
		2 => box.ymax
		3 => box.ymin
		4 => box.xmin
		5 => box.xmax
		_ => 0
	}
}

awami_kerning_state = {
	n = TableVar.f32_from_int
	a = GraphiteSlots.append(GraphiteSlots.make(0, 4), { ..GraphiteSlots.no_slot, glyph: 2, advance_x: n(1261), attach_x: n(426), attach_y: n(-7) })
	b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, glyph: 1, advance_x: n(426), attach_x: n(253), attach_y: n(-25) })
	c = GraphiteSlots.append(b.state, { ..GraphiteSlots.no_slot, glyph: 0, advance_x: n(253) })
	d = GraphiteSlots.append(c.state, { ..GraphiteSlots.no_slot, glyph: 3, advance_x: n(1237) })
	one = GraphitePosition.attach(d.state, 1, 2, 100)
	two = GraphitePosition.attach(one.state, 2, 3, 100)
	var $state = two.state
	for id in [1, 2, 3, 4] {
		$state = GraphiteSlots.set_extra($state, id, 31, 1)
		$state = GraphiteSlots.set_extra($state, id, 4, -2000)
		$state = GraphiteSlots.set_extra($state, id, 6, 2000)
	}
	$state = GraphiteSlots.set_extra($state, 3, 3, 17)
	$state = GraphiteSlots.set_extra($state, 3, 10, 273)
	$state = GraphiteSlots.set_extra($state, 4, 3, 17)
	$state = GraphiteSlots.set_extra($state, 4, 10, 150)
	$state
}
expect {
	match collision_prepared {
		Err(_) => False
		Ok(table) => match table.program.subtables.first() {
			Err(_) => False
			Ok(sub) => {
				context = { table: { ..table, attributes: awami_kerning_boxes }, sub: { ..sub, direction: 2 }, rtl: True }
				result = GraphiteCollision.kerning(awami_kerning_state, context, 12, 65536, awami_kerning_metric)
				advance = GraphiteSlots.integer(GraphiteSlots.get(result.state, 3).advance_x)
				advance == 315 and result.stopped == 0
			}
		}
	}
}

# Empty derived target spans must not wrap into an unsigned iteration count.
expect {
	n = TableVar.f32_from_int
	below = { ..collision_square, y_min: n(-1000), y_max: n(-900) }
	cache = collision_target_bins([below, collision_square], n(10), n(-10), n(600), True, 1000)
	ordinary = collision_target_bins([collision_square], n(10), n(-10), n(600), True, 1000)
	cache.stopped == 0 and cache.start == ordinary.start and cache.bins == ordinary.bins
}

# The cached broad-audit-080 trace preserves empty SUM[100,0] and
# DIFF[-20,-100] searches, selecting +100 and -100 at equal cost.
expect {
	n = TableVar.f32_from_int
	limits = { x_min: n(-10), x_max: 0, y_min: n(50), y_max: n(100) }
	sum = GraphiteCollision.axis_limits(limits, 2, 0, 0)
	diff = GraphiteCollision.axis_limits(limits, 3, 0, 0)
	sum.low == n(100) and sum.high == n(100) and diff.low == n(-100) and diff.high == n(-100)
}
expect {
	n = TableVar.f32_from_int
	limits = { x_min: n(-10), x_max: 0, y_min: n(50), y_max: n(100) }
	obstacle = { x_min: n(-300), x_max: n(300), y_min: n(-600), y_max: n(600), sum_min: n(-900), sum_max: n(900), diff_min: n(-900), diff_max: n(900) }
	solved = GraphiteCollision.solve_shift(limits, 0, 0, [obstacle], 0, n(10), 1000)
	solved.stopped == 0 and solved.x == n(50) and solved.y == n(50)
}

# A one-unit full rectangle seeds its only neighbor cell at the horizontal
# edge; the SUM cut applies immediately to a substantially clipped diagonal.
expect {
	n = TableVar.f32_from_int
	cache = collision_target_bins([collision_square], n(10), n(-10), n(600), True, 1000)
	neighbor = { ..collision_square, y_max: n(1), sum_max: n(301), diff_min: n(-1) }
	full = GraphiteCollision.bins_gap(cache, neighbor, True, 1000)
	clipped = GraphiteCollision.bins_gap(cache, { ..neighbor, sum_max: n(150) }, True, 1000)
	full.stopped == 0 and full.gap == n(-310) and TableVar.f32_lt(n(-160), clipped.gap)
}

# The exact margin101 tie distinguishes expanded midpoint arithmetic
# from 2*low+width (which rounds above the accepted upper-SUM corner).
expect {
	n = TableVar.f32_from_int
	cache = collision_target_bins([collision_square], n(101), n(-101), n(600), True, 1000)
	neighbor = { x_min: 0, x_max: n(300), y_min: n(-6), y_max: n(4), sum_min: n(-6), sum_max: n(304), diff_min: n(-4), diff_max: n(306) }
	gap = GraphiteCollision.bins_gap(cache, neighbor, True, 1000)
	gap.stopped == 0 and gap.gap == n(-401)
}
# Public Graphite2 later-h600-s128-d128-m10 has a right peak at
# 154.098... in cell46, rather than the other facet's149.431... .
# This unit interval distinguishes the switch; the native cached oracle
# separately enforces the exact public glyph run.
expect {
	n = TableVar.f32_from_int
	cache = collision_target_bins([collision_square], n(10), n(-10), n(600), True, 1000)
	neighbor = { ..collision_square, sum_max: GraphiteCollision.coordinate(0, n(900), 128), diff_max: GraphiteCollision.coordinate(n(-600), n(900), 128) }
	gap = GraphiteCollision.bins_gap(cache, neighbor, True, 1000)
	gap.stopped == 0 and TableVar.f32_lt(n(-165), gap.gap) and TableVar.f32_lt(gap.gap, n(-164))
}

phase3_space_state = |flags| {
	n = TableVar.f32_from_int
	a = GraphiteSlots.append(GraphiteSlots.make(0, 3), { ..GraphiteSlots.no_slot, glyph: 1, advance_x: n(100) })
	b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, glyph: 0, advance_x: n(100) })
	c = GraphiteSlots.append(b.state, { ..GraphiteSlots.no_slot, glyph: 2, advance_x: n(603) })
	var $state = c.state
	for id in [1, 2, 3] {
		$state = GraphiteSlots.set_extra($state, id, 31, 1)
		$state = GraphiteSlots.set_extra($state, id, 4, -1000)
		$state = GraphiteSlots.set_extra($state, id, 6, 1000)
	}
	$state = GraphiteSlots.set_extra($state, 1, 3, 17)
	$state = GraphiteSlots.set_extra($state, 1, 10, 10)
	GraphiteSlots.set_extra($state, 2, 3, flags)
}

# Independent phase3-space controls: START/END never bound the scan;
# explicit SPACE takes precedence over IGNORE, as does an all-zero box.
expect {
	match collision_prepared {
		Err(_) => False
		Ok(table) => match table.program.subtables.first() {
			Err(_) => False
			Ok(sub) => {
				attrs = { ..GraphiteAttributes.none, box_starts: [0, 6, 12], bytes: [0, 0, 0, 255, 0, 255, 0, 0, 0, 255, 0, 255, 0, 0, 0, 255, 0, 255] }
				var $ok = True
				for rtl in [False, True] {
					for blank in [False, True] {
						metric = |glyph, wanted, _| {
							if (blank and glyph == 0) 0 else match wanted {
								2 => 600
								5 => 300
								_ => 0
							}
						}
						for flags in [0, 2, 4, 8, 12, 14, 128, 130, 132, 136, 140, 142] {
							context = { table: { ..table, attributes: attrs }, sub: { ..sub, direction: if (rtl) 2 else 1 }, rtl }
							result = GraphiteCollision.kerning(phase3_space_state(flags), context, 9, 65536, metric)
							space = blank or flags.bitwise_and(128) != 0
							increment = if space {
								if (rtl) -193 else -310
							} else if flags.bitwise_and(2) != 0 {
								if (rtl) -393 else -110
							} else {
								if (rtl) 210 else -210
							}
							$ok = $ok and result.stopped == 0 and GraphiteSlots.get(result.state, 1).advance_x == TableVar.f32_from_int(100 + increment)
						}
					}
				}
				$ok
			}
		}
	}
}
expect {
	point = |_, wanted, _| if (wanted == 0 or wanted == 4 or wanted == 5) 5 else if (wanted == 2 or wanted == 3) 10 else 0
	!GraphiteCollision.kerning_space(0, 0, point) and !GraphiteCollision.kerning_space(0, 2, point) and GraphiteCollision.kerning_space(0, 130, point)
}

# A nonzero point is an ink obstacle with an occupied cell. Only the
# all-zero glyph box is classified as whitespace before this geometry step.
expect {
	n = TableVar.f32_from_int
	cache = collision_target_bins([collision_square], n(10), n(-10), n(600), True, 1000)
	point = { x_min: n(5), x_max: n(5), y_min: n(10), y_max: n(10), sum_min: n(15), sum_max: n(15), diff_min: n(-5), diff_max: n(-5) }
	gap = GraphiteCollision.bins_gap(cache, point, True, 1000)
	gap.stopped == 0 and TableVar.f32_lt(n(-10), gap.gap) and TableVar.f32_lt(gap.gap, n(-9))
}

# A later logical obstacle shifted physically closer must still improve
# the gap, even beyond another KERN target. Public CAPI reports +506.
expect {
	match collision_prepared {
		Err(_) => False
		Ok(table) => match table.program.subtables.first() {
			Err(_) => False
			Ok(sub) => {
				n = TableVar.f32_from_int
				a = GraphiteSlots.append(GraphiteSlots.make(0, 4), { ..GraphiteSlots.no_slot, glyph: 1, advance_x: n(100) })
				b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, glyph: 0, advance_x: n(100) })
				c = GraphiteSlots.append(b.state, { ..GraphiteSlots.no_slot, glyph: 2, advance_x: n(100) })
				d = GraphiteSlots.append(c.state, { ..GraphiteSlots.no_slot, glyph: 0, advance_x: n(604), shift_x: n(-1000) })
				var $state = d.state
				for id in [1, 2, 3, 4] {
					$state = GraphiteSlots.set_extra($state, id, 31, 1)
					$state = GraphiteSlots.set_extra($state, id, 4, -5000)
					$state = GraphiteSlots.set_extra($state, id, 6, 5000)
					$state = GraphiteSlots.set_extra($state, id, 10, 10)
				}
				$state = GraphiteSlots.set_extra($state, 1, 3, 17)
				$state = GraphiteSlots.set_extra($state, 3, 3, 17)
				attrs = { ..GraphiteAttributes.none, box_starts: [0, 6, 12], bytes: [0, 0, 0, 255, 0, 255, 0, 0, 0, 255, 0, 255, 0, 0, 0, 255, 0, 255] }
				metric = |_, wanted, _| match wanted {
					2 => 600
					5 => 300
					_ => 0
				}
				result = GraphiteCollision.kerning($state, { table: { ..table, attributes: attrs }, sub: { ..sub, direction: 2 }, rtl: True }, 9, 65536, metric)
				result.stopped == 0 and GraphiteSlots.get(result.state, 1).advance_x == n(606)
			}
		}
	}
}

# Rounded normalization at255 can extend beyond the mathematical diagonal
# endpoint. The cover must enclose the decoder's actual output bits.
expect {
	n = TableVar.f32_from_int
	whole = { x_min: n(-32768), x_max: n(32767), y_min: n(-32768), y_max: n(32766), sum_min: 0, sum_max: 0, diff_min: 0, diff_max: 0 }
	cover = GraphiteCollision.part_cover(whole)
	TableVar.f32_lt(n(65533), cover.sum_max) and TableVar.f32_lt(n(65535), cover.diff_max)
}

shift_bound_part = |whole, seed| {
	pair = |step| {
		a = (seed * 37 + step * 11) % 256
		b = (seed * 79 + step * 23 + 1) % 256
		{ low: if (a < b) a else b, high: if (a < b) b else a }
	}
	x = pair(1)
	y = pair(2)
	s = pair(3)
	d = pair(4)
	x_span = TableVar.f32_sub(whole.x_max, whole.x_min)
	y_span = TableVar.f32_sub(whole.y_max, whole.y_min)
	span = TableVar.f32_add(x_span, y_span)
	sum_base = TableVar.f32_add(whole.x_min, whole.y_min)
	diff_base = TableVar.f32_sub(whole.x_min, whole.y_max)
	{ x_min: GraphiteCollision.coordinate(whole.x_min, x_span, x.low), x_max: GraphiteCollision.coordinate(whole.x_min, x_span, x.high), y_min: GraphiteCollision.coordinate(whole.y_min, y_span, y.low), y_max: GraphiteCollision.coordinate(whole.y_min, y_span, y.high), sum_min: GraphiteCollision.coordinate(sum_base, span, s.low), sum_max: GraphiteCollision.coordinate(sum_base, span, s.high), diff_min: GraphiteCollision.coordinate(diff_base, span, d.low), diff_max: GraphiteCollision.coordinate(diff_base, span, d.high) }
}

# Differential property: an exact reference-pinned candidate must survive
# the cheaper cover test. Include extreme boxes, points, fractional bases
# and inverted movement windows; no coherent-diagonal assumption is used.
expect {
	n = TableVar.f32_from_int
	var $ok = True
	var $active = 0
	var $rejected = 0
	for whole in [collision_square, { ..collision_square, x_min: n(-32768), x_max: n(32767), y_min: n(-32768), y_max: n(32766) }, { ..collision_square, x_min: n(5), x_max: n(5), y_min: n(10), y_max: n(10) }, { ..collision_square, x_min: n(-50), x_max: n(100), y_min: n(-70), y_max: n(200) }] {
		cover = GraphiteCollision.part_cover(whole)
		for target in [collision_square, { x_min: 0, x_max: 0, y_min: 0, y_max: 0, sum_min: 0, sum_max: 0, diff_min: 0, diff_max: 0 }] {
			for seed in 0..<32 {
				part = shift_bound_part(whole, seed)
				dx = TableVar.f32_div(n(((seed * 997) % 5000).to_i64_wrap() - 2500), n(3))
				dy = TableVar.f32_div(n(((seed * 617) % 3500).to_i64_wrap() - 1750), n(7))
				base_x = TableVar.f32_div(n(((seed * 19) % 301).to_i64_wrap() - 150), n(3))
				base_y = TableVar.f32_div(n(((seed * 29) % 401).to_i64_wrap() - 200), n(7))
				limits = { x_min: n(((seed * 67) % 1001).to_i64_wrap() - 500), x_max: n(((seed * 79) % 1001).to_i64_wrap() - 500), y_min: n(((seed * 83) % 1001).to_i64_wrap() - 500), y_max: n(((seed * 97) % 1001).to_i64_wrap() - 500) }
				margin = n(((seed * 31) % 101).to_i64_wrap())
				exact = GraphiteCollision.broad_active(target, part, dx, dy, limits, base_x, base_y, margin)
				possible = GraphiteCollision.broad_possible(target, cover, dx, dy, limits, base_x, base_y, margin)
				$ok = $ok and (!exact or possible)
				if exact {
					$active = $active + 1
				}
				if !possible {
					$rejected = $rejected + 1
				}
			}
		}
	}
	$ok and $active > 0 and $rejected > 0
}

# Index membership survives a deleted stable root and interleaved trees.
# Inclusive reversed and overlapping groups preserve the scan's region
# order and every scalar coefficient, including live retry-flag changes.
expect {
	match collision_prepared {
		Err(_) => False
		Ok(table) => match table.program.subtables.first() {
			Err(_) => False
			Ok(sub) => {
				n = TableVar.f32_from_int
				var $state = GraphiteSlots.make(0, 6)
				for id in 1..<7 {
					appended = GraphiteSlots.append($state, { ..GraphiteSlots.no_slot, glyph: 1, parent: if (id < 5) (if (id % 2 == 1) 5 else 6) else 0, position_x: n(id.to_i64_wrap() * 10), position_y: n(id.to_i64_wrap() * 20) })
					$state = appended.state
					for field in [(3, 1), (15, 1), (17, 1), (18, id.to_i32_wrap() * 7), (19, 100), (20, id.to_i32_wrap() * 11), (21, 200), (22, 150), (23, 300)] {
						$state = GraphiteSlots.set_extra($state, id, field.0, field.1)
					}
				}
				$state = GraphiteSlots.delete($state, 5)
				prepared = GraphiteCollision.prepare_work($state, 1000)
				indexed = GraphiteCollision.prepare_members(prepared.work, 1000)
				attrs = { ..GraphiteAttributes.none, box_starts: [0, 6, 12], bytes: [0, 0, 0, 255, 0, 255, 0, 0, 0, 255, 0, 255, 0, 0, 0, 255, 0, 255] }
				context = { table: { ..table, attributes: attrs }, sub, rtl: False }
				metric = |_, wanted, _| match wanted {
					2 => 600
					5 => 300
					_ => 0
				}
				input = { target: Present(collision_square), obstacles: [], active: True, current_x: 0, current_y: 0, limits: { x_min: n(-1000), y_min: n(-1000), x_max: n(1000), y_max: n(1000) }, margin: n(10), weight: n(100), operations: 0, stopped: 0 }
				var $ok = prepared.stopped == 0 and indexed.stopped == 0
				var $nonempty = 0
				for flags in [0, 1, 33, 257, 289, 2, 17] {
					live = GraphiteSlots.set_extra(indexed.work.state, 1, 3, flags)
					work = { ..indexed.work, state: live }
					for retry in [False, True] {
						for reverse in [False, True] {
							for pair in [(1, 6), (2, 4), (3, 3)] {
								group = if (reverse) { first: pair.1, last: pair.0 } else { first: pair.0, last: pair.1 }
								a = GraphiteCollision.collect_sequence(work, context, 3, group, reverse, retry, input, 1000, metric)
								b = GraphiteCollision.collect_sequence({ ..work, members: Scan }, context, 3, group, reverse, retry, input, 1000, metric)
								$ok = $ok and a.stopped == 0 and b.stopped == 0 and a.regions == b.regions
								$nonempty = $nonempty + a.regions.len()
							}
						}
					}
				}
				fallback = GraphiteCollision.prepare_members(prepared.work, 0)
				$ok and $nonempty > 0 and fallback.operations == 0 and fallback.stopped == 0 and match fallback.work.members {
					Scan => True
					_ => False
				}
			}
		}
	}
}

expect {
	state = GraphiteSlots.set_extra(GraphiteSlots.set_extra(collision_ink_state, 2, 15, 1), 2, 3, 1)
	prepared = GraphiteCollision.prepare_work(state, 100)
	exact = state.nodes.len() + 2 * state.active
	built = GraphiteCollision.prepare_members(prepared.work, exact)
	short = GraphiteCollision.prepare_members(prepared.work, exact - 1)
	none = GraphiteCollision.prepare_work(GraphiteSlots.make(0, 0), 100)
	built.operations == exact and built.stopped == 0 and short.operations == 0 and short.stopped == 0 and (
		match built.work.members {
			Ready(_) => True
			_ => False
		}
	) and (
		match short.work.members {
			Scan => True
			_ => False
		}
	) and (
		match none.work.members {
			Scan => True
			_ => False
		}
	)
}

# Original public-C-API upper-occupancy witnesses distinguish adding the
# margin before division from adding one after flooring. Complete bounds
# cap part occupancy independently of the cache's allocated capacity.
expect {
	n = TableVar.f32_from_int
	var $ok = True
	for sample in [(600, 10, 128, 48), (600, 10, 127, 47), (600, 10, 64, 25), (600, 10, 248, 90), (600, 10, 254, 92), (600, 10, 255, 92), (600, 30, 128, 18), (600, 30, 127, 17), (600, 30, 64, 10), (600, 30, 255, 32), (9, 10, 255, 4), (609, 10, 255, 94)] {
		height = n(sample.0)
		part = { ..collision_square, y_max: GraphiteCollision.coordinate(0, height, sample.2) }
		cache = collision_target_bins([part], n(sample.1), n(-sample.1), height, True, 1000)
		$ok = $ok and cache.stopped == 0 and cache.start == 1 and cache.bins.len() == sample.3
	}
	$ok
}

# The public three-root negative-X control keeps a far obstacle that
# blocks the nearer obstacle's apparent escape. The display/overlap box's
# symmetric X minimum is not the projected movement interval minimum.
expect {
	n = TableVar.f32_from_int
	neighbor = { x_min: 0, y_min: 0, x_max: n(1000), y_max: n(600), sum_min: 0, sum_max: n(1600), diff_min: n(-600), diff_max: n(1000) }
	limits = { x_min: n(-1000), y_min: n(-1), x_max: 0, y_max: n(1) }
	GraphiteCollision.broad_active(collision_square, neighbor, n(1967), n(170), limits, 0, 0, 0)
}

# A positive-only movement interval retains the reflected outer search
# radius observed by the public broad-audit034 control.
expect {
	n = TableVar.f32_from_int
	limits = { x_min: n(101), y_min: n(20), x_max: n(201), y_max: n(300) }
	GraphiteCollision.broad_active(collision_square, collision_square, n(550), 0, limits, 0, 0, 0)
}

# A previous-pass offset does not translate the reflected lower radius.
# The cached broad-audit073 obstacle ends one unit outside that radius.
expect {
	n = TableVar.f32_from_int
	limits = { x_min: n(-100), y_min: n(-100), x_max: n(100), y_max: n(100) }
	!GraphiteCollision.broad_active(collision_square, collision_square, n(401), 0, limits, 0, n(200), 0)
}

# Visited prior glyphs move the sampling origin, while each current whole
# glyph retains its own terminal occupied-bin limit (public frame audit).
expect {
	n = TableVar.f32_from_int
	part = { box: collision_square, whole_min_y: 0, whole_max_y: n(600) }
	bins = GraphiteCollision.target_bins([part], n(10), n(-610), n(1210), True, 1000)
	bins.stopped == 0 and bins.start == 91 and bins.bins.len() == 92
}

# A later child may draw outside the root's displayed frame. Its own
# whole limits permit that ink, and the finite frame vector caps drawing.
expect {
	n = TableVar.f32_from_int
	box = GraphiteCollision.translate_box({ ..collision_square, y_min: n(-600), y_max: n(1200), sum_min: n(-600), sum_max: n(1500), diff_min: n(-1200), diff_max: n(900) }, 0, n(170))
	bins = GraphiteCollision.target_bins([{ box, whole_min_y: n(-430), whole_max_y: n(1370) }], n(10), n(-10), n(610), True, 1000)
	bins.stopped == 0 and bins.start == 0 and bins.bins.len() == 140
}

# Per-glyph whole lower bounds constrain the expanded parts independently
# of earlier visited glyphs; a negative whole lower index can reach zero.
expect {
	n = TableVar.f32_from_int
	box = { ..collision_square, y_min: n(6), y_max: n(248) }
	bins = GraphiteCollision.target_bins([{ box, whole_min_y: n(-7), whole_max_y: n(248) }], n(10), n(-10), n(610), True, 1000)
	bins.stopped == 0 and bins.start == 1
}

# Whole upper bounds can retain the lower sentinel, while the signed
# expanded part interval still leaves sufficiently distant ink empty.
expect {
	n = TableVar.f32_from_int
	check = |max_y, expected| {
		box = { ..collision_square, y_min: n(max_y - 600), y_max: n(max_y) }
		cache = GraphiteCollision.target_bins([{ box, whole_min_y: box.y_min, whole_max_y: box.y_max }], n(10), n(-10), n(610), True, 1000)
		cache.stopped == 0 and cache.bins.len() == expected
	}
	check(-18, 1) and check(-25, 0) and check(-1000, 0)
}

# Public whole-glyph boundary controls distinguish eligibility from
# occupied target cells and from the actual neighbor's subbox bounds.
expect {
	n = TableVar.f32_from_int
	m = n(10)
	width = TableVar.f32_div(n(20), n(3))
	capacity = GraphiteCollision.kern_capacity(n(-10), n(610), width)
	capacity == 140 and GraphiteCollision.kern_neighbor_in_frame(n(922), n(923), n(-10), width, m, capacity) and !GraphiteCollision.kern_neighbor_in_frame(n(923), n(924), n(-10), width, m, capacity) and GraphiteCollision.kern_neighbor_in_frame(n(-31), n(-30), n(-10), width, m, capacity) and !GraphiteCollision.kern_neighbor_in_frame(n(-32), n(-31), n(-10), width, m, capacity)
}

expect {
	n = TableVar.f32_from_int
	var $ok = True
	for value in [(13, 930, -39), (17, 945, -51), (30, 968, -90), (101, 1109, -303)] {
		margin = n(value.0)
		min_y = n(-value.0)
		max_y = n(600 + value.0)
		width = TableVar.f32_div(n(2 * value.0), n(3))
		capacity = GraphiteCollision.kern_capacity(min_y, max_y, width)
		$ok = $ok and GraphiteCollision.kern_neighbor_in_frame(n(value.1), n(value.1 + 100), min_y, width, margin, capacity) and !GraphiteCollision.kern_neighbor_in_frame(n(value.1 + 1), n(value.1 + 101), min_y, width, margin, capacity) and GraphiteCollision.kern_neighbor_in_frame(n(value.2 - 100), n(value.2), min_y, width, margin, capacity) and !GraphiteCollision.kern_neighbor_in_frame(n(value.2 - 101), n(value.2 - 1), min_y, width, margin, capacity)
	}
	$ok
}

# Original two-pass controls keep physical geometry constant while varying
# the established prior offset. Coarse gates use the recovered point;
# the forbidden projection remains in physical coordinates.
expect {
	n = TableVar.f32_from_int
	limits = { x_min: n(-1), y_min: n(-1000), x_max: n(1), y_max: n(1000) }
	var $ok = True
	for sample in [(100, True), (300, True), (414, True), (415, True), (416, False), (500, False), (600, False), (800, False), (-885, True), (-886, False)] {
		actual = GraphiteCollision.broad_active(collision_square, collision_square, n(-80), n(-170), limits, 0, n(sample.0), 0)
		$ok = $ok and actual == sample.1
	}
	$ok
}

expect {
	n = TableVar.f32_from_int
	limits = { x_min: n(-1000), y_min: n(-1), x_max: n(1000), y_max: n(1) }
	var $ok = True
	for sample in [(460, 0, True), (461, 0, False), (465, 10, True), (466, 10, False), (-1380, 0, True), (-1381, 0, False), (-1390, 10, True), (-1391, 10, False)] {
		actual = GraphiteCollision.broad_active(collision_square, collision_square, n(-80), n(-170), limits, n(sample.0), 0, n(sample.1))
		$ok = $ok and actual == sample.2
	}
	$ok
}

# A disjoint whole-glyph query differs from an empty actual part. The
# whole-y probe checks present cells, including holes inside the cache.
expect {
	n = TableVar.f32_from_int
	low = { ..collision_square, y_max: n(100) }
	high = { ..collision_square, y_min: n(500) }
	parts = [{ box: low, whole_min_y: 0, whole_max_y: n(600) }, { box: high, whole_min_y: 0, whole_max_y: n(600) }]
	cache = GraphiteCollision.target_bins(parts, n(10), n(-10), n(610), False, 10000)
	hole = GraphiteCollision.bins_intersect_y(cache, n(250), n(300), 1000)
	whole = GraphiteCollision.bins_intersect_y(cache, 0, n(600), 1000)
	outside = GraphiteCollision.bins_intersect_y(cache, n(700), n(800), 1000)
	limited = GraphiteCollision.bins_intersect_y(cache, 0, n(600), 0)
	cache.stopped == 0 and !hole.present and hole.stopped == 0 and whole.present and whole.stopped == 0 and !outside.present and outside.operations == 0 and limited.stopped == 2
}

# Sampled bounds exclude an attached part wholly beyond the finite vector;
# including it in a conservative bbox would change the empty comparison.
expect {
	n = TableVar.f32_from_int
	far = GraphiteCollision.translate_box(collision_square, n(500), n(3000))
	parts = [{ box: collision_square, whole_min_y: 0, whole_max_y: n(600) }, { box: far, whole_min_y: n(3000), whole_max_y: n(3600) }]
	left = GraphiteCollision.target_bins(parts, n(10), n(-10), n(610), True, 10000)
	right = GraphiteCollision.target_bins(parts, n(10), n(-10), n(610), False, 10000)
	left.stopped == 0 and right.stopped == 0 and left.bound == Present(n(-10)) and right.bound == Present(n(310))
}

# A trimmed target's sampled maximum exposes midpoint facet selection;
# taking both facets at the upper edge gives a different public advance.
expect {
	n = TableVar.f32_from_int
	box = { ..collision_square, x_min: n(500), x_max: n(800), sum_min: n(500), sum_max: GraphiteCollision.coordinate(n(500), n(900), 100), diff_min: n(-100), diff_max: GraphiteCollision.coordinate(n(-100), n(900), 100) }
	cache = GraphiteCollision.target_bins([{ box, whole_min_y: 0, whole_max_y: n(600) }], n(10), n(-10), n(610), False, 10000)
	cache.stopped == 0 and match cache.bound {
		Absent => False
		Present(bound) => GraphiteSlots.integer(bound) == 565
	}
}
