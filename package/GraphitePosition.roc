import GraphiteSlots
import TableVar

## Original geometry for Graphite's stable slot forest. Attachment links
## retain deleted input slots, as required by immutable rule references.
GraphitePosition :: {}.{

	Applied : { state : GraphiteSlots, operations : U64, stopped : U64 }
	Prefix : { present : Bool, x : U32, y : U32, previous : U64, next : U64 }
	Cache : { prefixes : List(Prefix), rtl : Bool, native_rtl : Bool }
	Cached : { state : GraphiteSlots, cache : [Present(Cache), Absent], operations : U64, stopped : U64 }
	CachePreparation : { cache : [Present(Cache), Absent], operations : U64 }
	PositionStart : { id : U64, previous : U64, x : U32, y : U32, prefixes : List(Prefix), resume : Bool }
	empty_prefix : Prefix
	empty_prefix = { present: False, x: 0, y: 0, previous: 0, next: 0 }
	Copied : { state : GraphiteSlots, operations : U64, stopped : U64, aborted : Bool }
	Frame : { id : U64, x : U32, y : U32 }

	# Explicit ATT_TO initializes one horizontal endpoint when making a new
	# edge. Input order comes from the VM's immutable rule window, including
	# deleted targets and reversed passes. This is the endpoint advance,
	# even when the two inputs are non-adjacent; it is not a summed distance.
	# Copying an attachment instead uses the link-only .attach below.
	attach_with_direction : GraphiteSlots, U64, U64, Bool, Bool, U64 -> Applied
	attach_with_direction = |state, id, parent, parent_after, rtl, budget| {
		previous = GraphiteSlots.get(state, id).parent
		result = GraphitePosition.attach(state, id, parent, budget)
		if result.stopped != 0 or previous == parent or GraphiteSlots.get(result.state, id).parent != parent {
			return result
		}
		slot = GraphiteSlots.get(result.state, id)
		updated = if (parent_after != rtl) { ..slot, with_x: slot.advance_x } else { ..slot, attach_x: GraphiteSlots.get(result.state, parent).advance_x }
		{ state: GraphiteSlots.set(result.state, id, updated), operations: result.operations, stopped: result.stopped }
	}

	# PUT_COPY may populate an independent output slot from a live or
	# protected input. It never copies the input's child/sibling links.
	# Overwriting another slot already participating in an attachment is a
	# language abort; a true self-copy preserves the existing live forest.
	copy_attachment_from : GraphiteSlots, U64, U64, U64, U64 -> Copied
	copy_attachment_from = |state, destination, source, source_parent, budget| {
		if destination == source {
			return { state, operations: 0, stopped: 0, aborted: False }
		}
		dest = GraphiteSlots.get(state, destination)
		if dest.parent != 0 or dest.child != 0 or destination == source_parent {
			return { state, operations: 0, stopped: 0, aborted: True }
		}
		if source_parent == 0 {
			return { state, operations: 0, stopped: 0, aborted: False }
		}
		attached = GraphitePosition.attach(state, destination, source_parent, budget)
		{ state: attached.state, operations: attached.operations, stopped: attached.stopped, aborted: False }
	}

	# Geometry uses separate rounded binary32 operations. VM writes are
	# signed32 values and the slot pool is U64-addressed: even summing a
	# value for every addressable slot stays below binary32's finite range.
	shift_x : GraphiteSlots.Slot, Bool -> U32
	shift_x = |slot, rtl| if (rtl) TableVar.f32_sub(0, slot.shift_x) else slot.shift_x

	Metric : { state : GraphiteSlots, value : I32, operations : U64, stopped : U64 }

	# Level zero is resolved by the VM against its immutable input glyph.
	# Nonzero levels address the root's composite, with each attachment edge
	# selecting descendants at or below the requested unsigned8 level.
	metric : GraphiteSlots, U64, U64, I32, Bool, U64, (U64, U64, I32 -> I32) -> Metric
	metric = |input, id, wanted, level, rtl, budget, base_metric| GraphitePosition.metric_for_font(input, id, wanted, level, rtl, rtl, budget, base_metric)

	metric_for_font : GraphiteSlots, U64, U64, I32, Bool, Bool, U64, (U64, U64, I32 -> I32) -> Metric
	metric_for_font = |input, id, wanted, level, rtl, native_rtl, budget, base_metric| {
		if !GraphiteSlots.valid(input, id) {
			return { state: input, value: 0, operations: 0, stopped: 0 }
		}
		if level == 0 {
			return { value: base_metric(GraphiteSlots.get(input, id).glyph, wanted, 0), state: input, operations: 0, stopped: 0 }
		}
		prepared = GraphitePosition.position_for_font(input, rtl, native_rtl, budget)
		var $operations = prepared.operations
		if prepared.stopped != 0 {
			return { state: prepared.state, value: 0, operations: $operations, stopped: prepared.stopped }
		}
		state = prepared.state
		var $root_id = id
		var $walked = 0
		while GraphiteSlots.get(state, $root_id).parent != 0 and $walked < state.nodes.len() {
			if $operations >= budget {
				return { state, value: 0, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			$walked = $walked + 1
			$root_id = GraphiteSlots.get(state, $root_id).parent
		}
		root = GraphiteSlots.get(state, $root_id)
		root_shift = GraphitePosition.shift_x(root, native_rtl)
		root_x = TableVar.f32_add(root_shift, root.justify_width)
		var $right = TableVar.f32_add(root.advance_x, root.justify_width)
		var $left = 0
		var $min_x = TableVar.f32_add(root_x, TableVar.f32_from_int(base_metric(root.glyph, 4, 0).to_i64()))
		var $max_x = TableVar.f32_add(root_x, TableVar.f32_from_int(base_metric(root.glyph, 5, 0).to_i64()))
		var $min_y = TableVar.f32_add(root.shift_y, TableVar.f32_from_int(base_metric(root.glyph, 3, 0).to_i64()))
		var $max_y = TableVar.f32_add(root.shift_y, TableVar.f32_from_int(base_metric(root.glyph, 2, 0).to_i64()))
		var $pending = if (root.child == 0) [] else [{ id: root.child, x: root_x, y: root.shift_y }]
		var $visited = 0
		while !$pending.is_empty() and $visited < state.nodes.len() {
			if $operations >= budget {
				return { state, value: 0, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			$visited = $visited + 1
			frame = $pending.last() ?? { id: 0, x: 0, y: 0 }
			$pending = $pending.drop_last(1)
			child = GraphiteSlots.get(state, frame.id)
			if child.sibling != 0 {
				$pending = $pending.append({ ..frame, id: child.sibling })
			}
			if GraphiteSlots.get_extra(state, frame.id, 28) <= level.to_u8_wrap().to_i32() {
				shift = GraphitePosition.shift_x(child, native_rtl)
				x = TableVar.f32_add(TableVar.f32_add(TableVar.f32_sub(child.attach_x, child.with_x), frame.x), TableVar.f32_add(shift, child.justify_width))
				y = TableVar.f32_add(TableVar.f32_add(TableVar.f32_sub(child.attach_y, child.with_y), frame.y), child.shift_y)
				if TableVar.f32_lt(0, child.advance_x) {
					$right = TableVar.f32_max($right, TableVar.f32_add(TableVar.f32_sub(x, shift), child.advance_x))
				}
				$left = TableVar.f32_min($left, TableVar.f32_sub(x, root_x))
				$min_x = TableVar.f32_min($min_x, TableVar.f32_add(x, TableVar.f32_from_int(base_metric(child.glyph, 4, 0).to_i64())))
				$max_x = TableVar.f32_max($max_x, TableVar.f32_add(x, TableVar.f32_from_int(base_metric(child.glyph, 5, 0).to_i64())))
				$min_y = TableVar.f32_min($min_y, TableVar.f32_add(y, TableVar.f32_from_int(base_metric(child.glyph, 3, 0).to_i64())))
				$max_y = TableVar.f32_max($max_y, TableVar.f32_add(y, TableVar.f32_from_int(base_metric(child.glyph, 2, 0).to_i64())))
				if child.child != 0 {
					$pending = $pending.append({ id: child.child, x, y })
				}
			}
		}
		advance = TableVar.f32_sub($right, $left)
		min_x = TableVar.f32_sub($min_x, $left)
		max_x = TableVar.f32_sub($max_x, $left)
		bits = match wanted {
			0 | 4 => min_x
			1 => TableVar.f32_sub(advance, max_x)
			2 => $max_y
			3 => $min_y
			5 => max_x
			6 => TableVar.f32_sub($max_y, $min_y)
			7 => TableVar.f32_sub(max_x, min_x)
			8 => advance
			9 => if (root.child == 0) root.advance_y else 0
			_ => 0
		}
		{ state, value: GraphiteSlots.integer(bits), operations: $operations, stopped: 0 }
	}

	position : GraphiteSlots, Bool, U64 -> Applied
	position = |state, rtl, budget| GraphitePosition.position_for_font(state, rtl, rtl, budget)

	# Segment direction selects active-root traversal and physical collision
	# conventions. The selected Silf's native direction independently gives
	# the sign of authored horizontal shifts, including opposite-script runs.
	position_for_font : GraphiteSlots, Bool, Bool, U64 -> Applied
	position_for_font = |state, rtl, native_rtl, budget| {
		if state.positioned {
			return { state, operations: 0, stopped: 0 }
		}
		id = if (rtl) state.last else state.first
		result = GraphitePosition.position_run(state, rtl, native_rtl, budget, { id, previous: 0, x: 0, y: 0, prefixes: [], resume: False })
		{ state: result.state, operations: result.operations, stopped: result.stopped }
	}

	# Cache only complete positioning results. The pass owns all subsequent
	# geometry changes; ordinary VM edits keep using the complete traversal.
	prepare_cache : GraphiteSlots, Bool, Bool, U64 -> CachePreparation
	prepare_cache = |state, rtl, native_rtl, budget| {
		count = state.nodes.len()
		if !state.positioned or count > budget or state.active > budget - count {
			return { cache: Absent, operations: 0 }
		}
		var $prefixes = List.repeat(GraphitePosition.empty_prefix, count)
		var $id = if (rtl) state.last else state.first
		var $walked = 0
		var $previous = 0
		var $x = 0
		var $y = 0
		while $id != 0 and $walked < state.active {
			$walked = $walked + 1
			slot = GraphiteSlots.get(state, $id)
			if slot.parent == 0 and !slot.deleted {
				if $previous != 0 {
					old = $prefixes.get($previous) ?? GraphitePosition.empty_prefix
					$prefixes = $prefixes.set($previous, { ..old, next: $id }) ?? []
				}
				$prefixes = $prefixes.set($id, { present: True, x: $x, y: $y, previous: $previous, next: 0 }) ?? []
				$previous = $id
				$x = TableVar.f32_add($x, GraphiteSlots.get_extra(state, $id, 29).to_u32_wrap())
				$y = TableVar.f32_add($y, GraphiteSlots.get_extra(state, $id, 30).to_u32_wrap())
			}
			$id = if (rtl) slot.previous else slot.next
		}
		{ cache: Present({ prefixes: $prefixes, rtl, native_rtl }), operations: count + $walked }
	}

	# A collision pass changes one root's physical offsets at a time. Begin
	# from its exact prior prefix, retaining the full algorithm's rounding.
	# Once the following prefix is bit-identical, its untouched suffix is
	# still valid. The collision pass keeps forest/order/author metrics
	# fixed; this cache does not validate arbitrary VM topology changes.
	# A root absent from the prepared active forest uses Whole.
	position_from : GraphiteSlots, Cache, U64, Bool, Bool, U64 -> Cached
	position_from = |state, { prefixes, rtl: cached_rtl, native_rtl: cached_native_rtl }, root, rtl, native_rtl, budget| {
		if state.positioned {
			return { state, cache: Present({ prefixes, rtl: cached_rtl, native_rtl: cached_native_rtl }), operations: 0, stopped: 0 }
		}
		prefix = prefixes.get(root) ?? GraphitePosition.empty_prefix
		slot = GraphiteSlots.get(state, root)
		if slot.deleted or slot.parent != 0 or cached_rtl != rtl or cached_native_rtl != native_rtl or prefixes.len() != state.nodes.len() or !prefix.present {
			id = if (rtl) state.last else state.first
			return GraphitePosition.position_run(state, rtl, native_rtl, budget, { id, previous: 0, x: 0, y: 0, prefixes: [], resume: False })
		}
		GraphitePosition.position_run(state, rtl, native_rtl, budget, { id: root, previous: prefix.previous, x: prefix.x, y: prefix.y, prefixes, resume: True })
	}

	position_run : GraphiteSlots, Bool, Bool, U64, PositionStart -> Cached
	position_run = |state, rtl, native_rtl, budget, { id: initial_id, previous: initial_previous, x: initial_x, y: initial_y, prefixes, resume }| {
		var $prefixes = prefixes
		{ nodes, users, user_count, justification_levels, feature_changes, first, last, active, positioned: _, advance_x: old_advance_x, advance_y: old_advance_y } = state
		var $nodes = nodes
		var $users = users
		var $operations = 0
		var $stopped = 0
		var $pen_x = initial_x
		var $pen_y = initial_y
		var $id = initial_id
		var $walked = 0
		var $previous_root = initial_previous
		var $pending = []
		var $members = []
		while $id != 0 and $walked < active and $stopped == 0 {
			if $operations >= budget {
				$stopped = 2
				break
			}
			$operations = $operations + 1
			$walked = $walked + 1
			root_id = $id
			root = $nodes.get(root_id) ?? GraphiteSlots.no_slot
			$id = if (rtl) root.previous else root.next
			if root.parent == 0 and !root.deleted {
				if resume {
					old = $prefixes.get(root_id) ?? GraphitePosition.empty_prefix
					# The first dirty root starts at its unchanged exact prefix.
					# Avoid writing identical data, including any needless COW.
					if old.x != $pen_x or old.y != $pen_y {
						$prefixes = $prefixes.set(root_id, { ..old, x: $pen_x, y: $pen_y }) ?? []
					}
				}
				# The public C API includes subsequent roots in the sibling chain.
				if $previous_root != 0 {
					previous = $nodes.get($previous_root) ?? GraphiteSlots.no_slot
					$nodes = $nodes.set($previous_root, { ..previous, sibling: root_id }) ?? []
				}
				$previous_root = root_id
				root_shift = GraphitePosition.shift_x(root, native_rtl)
				root_x = TableVar.f32_add(root_shift, root.justify_width)
				var $right = TableVar.f32_add(root.advance_x, root.justify_width)
				var $left = 0
				var $cluster_y = root.advance_y
				$members = $members.clear().append(root_id)
				$nodes = $nodes.set(root_id, { ..root, position_x: root_x, position_y: root.shift_y, sibling: 0 }) ?? []
				$pending = $pending.clear()
				root_at = root.user_start + user_count
				root_kern = ($users.get(root_at + 3) ?? 0).bitwise_and(16) != 0
				root_collision = ($users.get(root_at + 31) ?? 0) != 0 and (native_rtl or !root_kern)
				root_offset_x = if (root_collision) ($users.get(root_at + 8) ?? 0).to_u32_wrap() else 0
				root_physical_x = TableVar.f32_add(root_x, root_offset_x)
				if root.child != 0 {
					$pending = $pending.append({ id: root.child, x: root_x, y: root.shift_y, parent_x: root_physical_x })
					$cluster_y = 0
				}
				var $visited = 0
				while !$pending.is_empty() and $visited < $nodes.len() {
					if $operations >= budget {
						$stopped = 2
						break
					}
					$operations = $operations + 1
					$visited = $visited + 1
					frame = $pending.last() ?? { id: 0, x: 0, y: 0, parent_x: 0 }
					$pending = $pending.drop_last(1)
					child = $nodes.get(frame.id) ?? GraphiteSlots.no_slot
					if child.sibling != 0 {
						$pending = $pending.append({ ..frame, id: child.sibling })
					}
					# Deleted attachment nodes retain their geometry and authored
					# advance. Their live descendants still inherit that transform;
					# only the active output list excludes the deleted node.
					shift = GraphitePosition.shift_x(child, native_rtl)
					x = TableVar.f32_add(TableVar.f32_add(TableVar.f32_sub(child.attach_x, child.with_x), frame.x), TableVar.f32_add(shift, child.justify_width))
					y = TableVar.f32_add(TableVar.f32_add(TableVar.f32_sub(child.attach_y, child.with_y), frame.y), child.shift_y)
					$nodes = $nodes.set(frame.id, { ..child, position_x: x, position_y: y }) ?? []
					$members = $members.append(frame.id)
					# The right edge inherits parent collision motion but
					# excludes this child's own collision correction. Left
					# rebasing compares physical child/root origins; level metrics
					# retain their independently queried authored geometry.
					advance_x = TableVar.f32_add(TableVar.f32_add(TableVar.f32_sub(child.attach_x, child.with_x), frame.parent_x), TableVar.f32_add(shift, child.justify_width))
					if TableVar.f32_lt(0, child.advance_x) {
						$right = TableVar.f32_max($right, TableVar.f32_add(TableVar.f32_sub(advance_x, shift), child.advance_x))
					}
					at = child.user_start + user_count
					kern = ($users.get(at + 3) ?? 0).bitwise_and(16) != 0
					enabled = ($users.get(at + 31) ?? 0) != 0 and (native_rtl or !kern)
					ox = if (enabled) ($users.get(at + 8) ?? 0).to_u32_wrap() else 0
					physical_x = TableVar.f32_add(advance_x, ox)
					# Positive-advance children reserve their full negative
					# relative extent. Zero/negative-advance marks can overlay
					# preceding roots until they cross the segment origin.
					if TableVar.f32_lt(0, child.advance_x) or TableVar.f32_lt(TableVar.f32_add($pen_x, physical_x), 0) {
						$left = TableVar.f32_min($left, TableVar.f32_sub(physical_x, root_physical_x))
					}
					if child.child != 0 {
						$pending = $pending.append({ id: child.child, x, y, parent_x: physical_x })
					}
				}
				if $stopped != 0 {
					break
				}
				cluster_x = TableVar.f32_sub($right, $left)
				origin_x = TableVar.f32_sub($pen_x, $left)
				for member in $members {
					slot = $nodes.get(member) ?? GraphiteSlots.no_slot
					at = slot.user_start + user_count
					# Native LTR collision kerning stores its adjustment in the raw
					# offset and advance, but suppresses the entire own physical
					# offset point. RTL kerning keeps the ordinary offset point.
					kern = ($users.get(at + 3) ?? 0).bitwise_and(16) != 0
					enabled = ($users.get(at + 31) ?? 0) != 0 and (native_rtl or !kern)
					ox = if (enabled) ($users.get(at + 8) ?? 0).to_u32_wrap() else 0
					oy = if (enabled) ($users.get(at + 9) ?? 0).to_u32_wrap() else 0
					# Advances/rebasing above use authored geometry. Physical
					# origins are a second parent-first walk: a moved parent
					# moves its descendants, with binary32 rounding at each edge.
					point = if member == root_id {
						{ x: TableVar.f32_add(origin_x, TableVar.f32_add(root_x, ox)), y: TableVar.f32_add($pen_y, TableVar.f32_add(root.shift_y, oy)) }
					} else {
						parent = $nodes.get(slot.parent) ?? GraphiteSlots.no_slot
						shift = TableVar.f32_add(GraphitePosition.shift_x(slot, native_rtl), slot.justify_width)
						{ x: TableVar.f32_add(TableVar.f32_add(TableVar.f32_sub(slot.attach_x, slot.with_x), parent.position_x), TableVar.f32_add(shift, ox)), y: TableVar.f32_add(TableVar.f32_add(TableVar.f32_sub(slot.attach_y, slot.with_y), parent.position_y), TableVar.f32_add(slot.shift_y, oy)) }
					}
					$nodes = $nodes.set(member, { ..slot, position_x: point.x, position_y: point.y }) ?? []
				}
				# Cache full-cluster advances without overwriting authored metrics.
				$users = $users.set(root.user_start + user_count + 29, cluster_x.to_i32_wrap()) ?? []
				$users = $users.set(root.user_start + user_count + 30, $cluster_y.to_i32_wrap()) ?? []
				$pen_x = TableVar.f32_add($pen_x, cluster_x)
				$pen_y = TableVar.f32_add($pen_y, $cluster_y)
				if resume {
					entry = $prefixes.get(root_id) ?? GraphitePosition.empty_prefix
					if entry.next != 0 {
						next = $prefixes.get(entry.next) ?? GraphitePosition.empty_prefix
						if next.x == $pen_x and next.y == $pen_y {
							# Whole would link this root when visiting its successor.
							current = $nodes.get(root_id) ?? GraphiteSlots.no_slot
							$nodes = $nodes.set(root_id, { ..current, sibling: entry.next }) ?? []
							# The cached suffix, including its final advance, is exact.
							$pen_x = old_advance_x
							$pen_y = old_advance_y
							break
						}
					}
					# Root links skip active descendants already positioned above.
					$id = entry.next
				}
			}
		}
		{ state: { nodes: $nodes, users: $users, user_count, justification_levels, feature_changes, first, last, active, positioned: $stopped == 0, advance_x: $pen_x, advance_y: $pen_y }, cache: if (resume and $stopped == 0) Present({ prefixes: $prefixes, rtl, native_rtl }) else Absent, operations: $operations, stopped: $stopped }
	}

	# Public Graphite2 C-API witnesses establish that self-links and links
	# to descendants are ignored, preserving an existing attachment. A
	# deleted input node remains a valid attachment target. Work is checked
	# before mutation so exhaustion cannot leave a half-linked forest.
	attach : GraphiteSlots, U64, U64, U64 -> Applied
	attach = |state, id, parent, budget| {
		if !GraphiteSlots.valid(state, id) or !GraphiteSlots.valid(state, parent) or id == parent {
			return { state, operations: 0, stopped: 0 }
		}
		slot = GraphiteSlots.get(state, id)
		if slot.parent == parent {
			return { state, operations: 0, stopped: 0 }
		}
		var $operations = 0
		var $ancestor = parent
		var $steps = 0
		while $ancestor != 0 and $steps < state.nodes.len() {
			if $operations >= budget {
				return { state, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			$steps = $steps + 1
			if $ancestor == id {
				return { state, operations: $operations, stopped: 0 }
			}
			$ancestor = GraphiteSlots.get(state, $ancestor).parent
		}
		# Only a forest produced by this module reaches this point. The
		# independent count bound also makes a corrupted internal state total.
		if $ancestor != 0 {
			return { state, operations: $operations, stopped: 0 }
		}
		var $previous = 0
		if slot.parent != 0 {
			var $child = GraphiteSlots.get(state, slot.parent).child
			var $count = 0
			while $child != 0 and $child != id and $count < state.nodes.len() {
				if $operations >= budget {
					return { state, operations: $operations, stopped: 2 }
				}
				$operations = $operations + 1
				$count = $count + 1
				$previous = $child
				$child = GraphiteSlots.get(state, $child).sibling
			}
		}
		tail = GraphiteSlots.get(state, parent).last_child
		if $operations >= budget {
			return { state, operations: $operations, stopped: 2 }
		}
		$operations = $operations + 1
		{ nodes, users, user_count, justification_levels, feature_changes, first, last, active, positioned: _, advance_x, advance_y } = state
		var $nodes = nodes
		# Every link below is a checked stable ID into this same node pool.
		if slot.parent != 0 {
			if $previous == 0 {
				old = $nodes.get(slot.parent) ?? GraphiteSlots.no_slot
				$nodes = $nodes.set(slot.parent, { ..old, child: slot.sibling, last_child: if (old.last_child == id) $previous else old.last_child }) ?? []
			} else {
				old = $nodes.get($previous) ?? GraphiteSlots.no_slot
				$nodes = $nodes.set($previous, { ..old, sibling: slot.sibling }) ?? []
			}
			if $previous != 0 {
				old = $nodes.get(slot.parent) ?? GraphiteSlots.no_slot
				$nodes = $nodes.set(slot.parent, { ..old, last_child: if (old.last_child == id) $previous else old.last_child }) ?? []
			}
		}
		if tail == 0 {
			old = $nodes.get(parent) ?? GraphiteSlots.no_slot
			$nodes = $nodes.set(parent, { ..old, child: id, last_child: id }) ?? []
		} else {
			old = $nodes.get(tail) ?? GraphiteSlots.no_slot
			$nodes = $nodes.set(tail, { ..old, sibling: id }) ?? []
			parent_slot = $nodes.get(parent) ?? GraphiteSlots.no_slot
			$nodes = $nodes.set(parent, { ..parent_slot, last_child: id }) ?? []
		}
		$nodes = $nodes.set(id, { ..slot, parent, sibling: 0 }) ?? []
		{ state: { nodes: $nodes, users, user_count, justification_levels, feature_changes, first, last, active, positioned: False, advance_x, advance_y }, operations: $operations, stopped: 0 }
	}
}

attachment_fixture = {
	a = GraphiteSlots.append(GraphiteSlots.make(0, 3), { ..GraphiteSlots.no_slot, glyph: 1 })
	b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, glyph: 2 })
	c = GraphiteSlots.append(b.state, { ..GraphiteSlots.no_slot, glyph: 3 })
	{ state: c.state, a: a.id, b: b.id, c: c.id }
}

expect {
	f = attachment_fixture
	a = GraphitePosition.attach(f.state, f.a, f.b, 100)
	b = GraphitePosition.attach(a.state, f.c, f.b, 100)
	GraphiteSlots.get(b.state, f.b).child == f.a and GraphiteSlots.get(b.state, f.a).sibling == f.c and GraphiteSlots.get(b.state, f.c).parent == f.b and GraphiteSlots.get(b.state, f.c).insert_before
}
expect {
	f = attachment_fixture
	a = GraphitePosition.attach(f.state, f.a, f.b, 100)
	b = GraphitePosition.attach(a.state, f.b, f.a, 100)
	GraphiteSlots.get(b.state, f.a).parent == f.b and GraphiteSlots.get(b.state, f.b).parent == 0 and b.stopped == 0
}
expect {
	f = attachment_fixture
	a = GraphitePosition.attach(f.state, f.a, f.b, 0)
	a.stopped == 2 and GraphiteSlots.get(a.state, f.a).parent == 0 and GraphiteSlots.get(a.state, f.b).child == 0
}
expect {
	f = attachment_fixture
	a = GraphitePosition.attach(GraphiteSlots.delete(f.state, f.b), f.a, f.b, 100)
	GraphiteSlots.get(a.state, f.a).parent == f.b and GraphiteSlots.get(a.state, f.b).deleted
}
expect {
	f = attachment_fixture
	a = GraphitePosition.attach(f.state, f.a, f.b, 100)
	b = GraphitePosition.attach(a.state, f.a, f.c, 100)
	GraphiteSlots.get(b.state, f.b).child == 0 and GraphiteSlots.get(b.state, f.c).child == f.a and GraphiteSlots.get(b.state, f.a).parent == f.c
}

geometry_fixture = {
	a = GraphiteSlots.append(GraphiteSlots.make(0, 3), { ..GraphiteSlots.no_slot, glyph: 1, advance_x: TableVar.f32_from_int(601), attach_x: TableVar.f32_from_int(100), attach_y: TableVar.f32_from_int(200), with_x: TableVar.f32_from_int(20), with_y: TableVar.f32_from_int(30) })
	b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, glyph: 2, advance_x: TableVar.f32_from_int(602), attach_x: TableVar.f32_from_int(50), attach_y: TableVar.f32_from_int(80), with_x: TableVar.f32_from_int(10), with_y: TableVar.f32_from_int(20) })
	c = GraphiteSlots.append(b.state, { ..GraphiteSlots.no_slot, glyph: 3, advance_x: TableVar.f32_from_int(603) })
	c.state
}

expect {
	a = GraphitePosition.position(geometry_fixture, False, 100)
	b = GraphitePosition.position(geometry_fixture, True, 100)
	a.state.advance_x == TableVar.f32_from_int(1806) and GraphiteSlots.get(a.state, 2).position_x == TableVar.f32_from_int(601) and GraphiteSlots.get(b.state, 1).position_x == TableVar.f32_from_int(1205)
}
expect {
	a = GraphitePosition.attach(geometry_fixture, 1, 2, 100)
	b = GraphitePosition.attach(a.state, 2, 3, 100)
	c = GraphitePosition.position(b.state, False, 100)
	c.state.advance_x == TableVar.f32_from_int(721) and GraphiteSlots.get(c.state, 1).position_x == TableVar.f32_from_int(120) and GraphiteSlots.get(c.state, 1).position_y == TableVar.f32_from_int(230)
}
expect {
	a = GraphitePosition.attach(geometry_fixture, 1, 2, 100)
	slot = GraphiteSlots.get(a.state, 1)
	b = GraphiteSlots.set(a.state, 1, { ..slot, shift_x: TableVar.f32_from_int(-100) })
	c = GraphitePosition.position(b, False, 100)
	c.state.advance_x == TableVar.f32_from_int(1304) and GraphiteSlots.get(c.state, 1).position_x == 0 and GraphiteSlots.get(c.state, 2).position_x == TableVar.f32_from_int(20)
}
expect {
	a = GraphitePosition.attach(geometry_fixture, 1, 2, 100)
	slot = GraphiteSlots.get(a.state, 2)
	b = GraphiteSlots.set(a.state, 2, { ..slot, shift_x: TableVar.f32_from_int(-100) })
	c = GraphitePosition.position(b, False, 100)
	c.state.advance_x == TableVar.f32_from_int(1205) and GraphiteSlots.get(c.state, 1).position_x == TableVar.f32_from_int(-20) and GraphiteSlots.get(c.state, 2).position_x == TableVar.f32_from_int(-100)
}
expect {
	a = GraphitePosition.attach(geometry_fixture, 1, 2, 100)
	b = GraphiteSlots.delete(a.state, 2)
	c = GraphitePosition.position(b, False, 100)
	c.state.advance_x == TableVar.f32_from_int(603) and GraphiteSlots.get(c.state, 1).position_x == 0
}

geometry_metric = |_, wanted, _| match wanted {
	2 => 600
	5 => 300
	_ => 0
}
expect {
	a = GraphitePosition.attach(geometry_fixture, 1, 2, 100)
	b = GraphiteSlots.set_extra(a.state, 1, 28, 50)
	wanted = [0, 302, 600, 0, 0, 300, 600, 300, 602, 0, 0]
	var $ok = True
	for i in 0..<wanted.len() {
		answer = GraphitePosition.metric(b, 1, i, 1, False, 100, geometry_metric)
		$ok = $ok and answer.value == (wanted.get(i) ?? -1) and answer.stopped == 0
	}
	$ok
}
expect {
	a = GraphitePosition.attach(geometry_fixture, 1, 2, 100)
	b = GraphiteSlots.set_extra(a.state, 1, 28, 50)
	wanted = [0, 301, 770, 0, 0, 380, 770, 380, 681, 0, 0]
	var $ok = True
	for i in 0..<wanted.len() {
		answer = GraphitePosition.metric(b, 1, i, -1, True, 100, geometry_metric)
		$ok = $ok and answer.value == (wanted.get(i) ?? -1) and answer.stopped == 0
	}
	$ok
}

expect {
	f = attachment_fixture
	a = GraphitePosition.attach(f.state, f.a, f.b, 100)
	b = GraphitePosition.copy_attachment_from(a.state, f.a, f.b, 0, 100)
	c = GraphitePosition.copy_attachment_from(a.state, f.c, f.a, f.b, 100)
	d = GraphitePosition.copy_attachment_from(a.state, f.b, f.b, 0, 100)
	b.aborted and !c.aborted and !d.aborted and GraphiteSlots.get(c.state, f.c).parent == f.b and GraphiteSlots.get(c.state, f.a).sibling == f.c and GraphiteSlots.get(d.state, f.b).child == f.a
}

expect {
	a = GraphitePosition.attach(geometry_fixture, 1, 2, 100)
	root = GraphiteSlots.get(a.state, 2)
	b = GraphiteSlots.set(a.state, 2, { ..root, justify_width: TableVar.f32_from_int(-300) })
	c = GraphitePosition.position(b, False, 100)
	c.state.advance_x == TableVar.f32_from_int(984) and GraphiteSlots.get(c.state, 1).position_x == TableVar.f32_from_int(-220) and GraphiteSlots.get(c.state, 2).position_x == TableVar.f32_from_int(-300)
}

expect {
	input = geometry_fixture
	a = GraphitePosition.attach_with_direction(input, 1, 2, True, False, 100)
	b = GraphitePosition.attach_with_direction(input, 1, 2, True, True, 100)
	GraphiteSlots.get(a.state, 1).with_x == TableVar.f32_from_int(601) and GraphiteSlots.get(a.state, 1).attach_x == TableVar.f32_from_int(100) and GraphiteSlots.get(b.state, 1).attach_x == TableVar.f32_from_int(602) and GraphiteSlots.get(b.state, 1).with_x == TableVar.f32_from_int(20)
}
expect {
	input = geometry_fixture
	a = GraphitePosition.attach(input, 1, 2, 100)
	b = GraphitePosition.attach_with_direction(a.state, 1, 2, True, False, 100)
	GraphiteSlots.get(b.state, 1).with_x == TableVar.f32_from_int(20)
}

expect {
	a = GraphitePosition.attach(geometry_fixture, 1, 2, 100)
	b = GraphiteSlots.set_extra(GraphiteSlots.set_extra(a.state, 2, 31, 1), 2, 8, TableVar.f32_from_int(-220).to_i32_wrap())
	c = GraphitePosition.position(b, False, 100)
	GraphiteSlots.get(c.state, 1).position_x == TableVar.f32_from_int(-140) and GraphiteSlots.get(c.state, 2).position_x == TableVar.f32_from_int(-220) and c.state.advance_x == TableVar.f32_from_int(1205)
}
expect {
	# Public C-API witness with 512 preceding 32768-unit glyphs. Rounding
	# the parent's physical position before adding the attachment delta
	# differs from adding a summed collision offset to the child's base.
	n = TableVar.f32_from_int
	p = GraphiteSlots.append(GraphiteSlots.make(0, 3), { ..GraphiteSlots.no_slot, advance_x: n(16777216) })
	a = GraphiteSlots.append(p.state, { ..GraphiteSlots.no_slot, advance_x: n(601), attach_x: n(5), attach_y: n(170) })
	b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, advance_x: n(602), shift_x: n(1) })
	c = GraphitePosition.attach(b.state, a.id, b.id, 100)
	d = GraphiteSlots.set_extra(GraphiteSlots.set_extra(c.state, b.id, 31, 1), b.id, 8, TableVar.f32_from_ratio(-3460, 11).to_i32_wrap())
	e = GraphitePosition.position(d, False, 100)
	GraphiteSlots.get(e.state, b.id).position_x == n(16776902) and GraphiteSlots.get(e.state, a.id).position_x == n(16776907)
}

expect {
	n = TableVar.f32_from_int
	a = GraphiteSlots.append(GraphiteSlots.make(0, 2), { ..GraphiteSlots.no_slot, advance_x: n(-110), shift_y: n(500) })
	b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, advance_x: n(602) })
	c = GraphiteSlots.set_extra(GraphiteSlots.set_extra(GraphiteSlots.set_extra(GraphiteSlots.set_extra(b.state, a.id, 31, 1), a.id, 3, 17), a.id, 8, n(-210).to_i32_wrap()), a.id, 9, n(100).to_i32_wrap())
	d = GraphitePosition.position(c, False, 100)
	GraphiteSlots.get(d.state, a.id).position_x == 0 and GraphiteSlots.get(d.state, a.id).position_y == n(500) and GraphiteSlots.get(d.state, b.id).position_x == n(-110)
}

expect {
	# CAPI Charis a+acute and original far-child programs: only a positive
	# child advance extends the cluster's right edge. Nonpositive children
	# still participate in left rebasing and keep their physical position.
	n = TableVar.f32_from_int
	var $good = True
	for advance in [-1, 0, 1] {
		a = GraphiteSlots.append(GraphiteSlots.make(0, 2), { ..GraphiteSlots.no_slot, advance_x: n(advance), attach_x: n(1000) })
		b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, advance_x: n(602) })
		linked = GraphitePosition.attach(b.state, 1, 2, 100)
		positioned = GraphitePosition.position(linked.state, False, 100)
		if positioned.stopped != 0 or positioned.state.advance_x != n(if (advance > 0) 1001 else 602) or GraphiteSlots.get(positioned.state, 1).position_x != n(1000) {
			$good = False
		}
	}
	$good
}

expect {
	# Attachment preserves authored insertion boundaries in either state.
	f = attachment_fixture
	slot = GraphiteSlots.get(f.state, f.a)
	input = GraphiteSlots.set(f.state, f.a, { ..slot, insert_before: False })
	linked = GraphitePosition.attach(input, f.a, f.b, 100)
	!GraphiteSlots.get(linked.state, f.a).insert_before
}

expect {
	# Original attached-forward ink and sequencing controls: the parent
	# correction moves the child right edge, reducing segment advance to
	# 602. A nonzero-level glyph metric remains the authored composite681.
	n = TableVar.f32_from_int
	a = GraphiteSlots.append(GraphiteSlots.make(0, 2), { ..GraphiteSlots.no_slot, advance_x: n(601), attach_x: n(100), with_x: n(20), attach_y: n(200), with_y: n(30) })
	b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, advance_x: n(602) })
	linked = GraphitePosition.attach(b.state, 1, 2, 100)
	enabled = GraphiteSlots.set_extra(GraphiteSlots.set_extra(linked.state, 2, 31, 1), 2, 8, n(-220).to_i32_wrap())
	positioned = GraphitePosition.position(enabled, False, 100)
	metric = GraphitePosition.metric(positioned.state, 2, 8, 1, False, 100, |_, _, _| 0)
	positioned.state.advance_x == n(602) and GraphiteSlots.get(positioned.state, 1).position_x == n(-140) and metric.value == 681
}

expect {
	# A native RTL font keeps negative physical ShiftX under an effective
	# LTR segment as well. The public ABI's opposite-text control pins both
	# positions and a 701-unit segment advance; traversal still uses LTR.
	n = TableVar.f32_from_int
	a = GraphiteSlots.append(GraphiteSlots.make(0, 2), { ..GraphiteSlots.no_slot, advance_x: n(601), attach_x: n(100), with_x: n(20), shift_x: n(100) })
	b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, advance_x: n(602) })
	linked = GraphitePosition.attach(b.state, 1, 2, 100)
	positioned = GraphitePosition.position_for_font(linked.state, False, True, 100)
	positioned.state.advance_x == n(701) and GraphiteSlots.get(positioned.state, 1).position_x == 0 and GraphiteSlots.get(positioned.state, 2).position_x == n(20)
}

expect {
	# Native RTL collision kerning retains its own physical offset even
	# when an opposite-script adapter requests an effective LTR segment.
	n = TableVar.f32_from_int
	a = GraphiteSlots.append(GraphiteSlots.make(0, 2), { ..GraphiteSlots.no_slot, advance_x: n(100) })
	b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, advance_x: n(811) })
	state = GraphiteSlots.set_extra(GraphiteSlots.set_extra(GraphiteSlots.set_extra(b.state, 2, 31, 1), 2, 3, 17), 2, 8, n(210).to_i32_wrap())
	result = GraphitePosition.position_for_font(state, False, True, 100)
	result.state.advance_x == n(911) and GraphiteSlots.get(result.state, 2).position_x == n(310)
}

expect {
	# Cached sibling sequencing control: a child's own negative correction
	# rebases the complete cluster. Ancestor motion is removed by measuring
	# against the root's physical origin, not the uncorrected authored root.
	n = TableVar.f32_from_int
	a = GraphiteSlots.append(GraphiteSlots.make(0, 3), { ..GraphiteSlots.no_slot, advance_x: n(601), attach_x: n(80) })
	b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, advance_x: n(602), attach_x: n(180) })
	c = GraphiteSlots.append(b.state, { ..GraphiteSlots.no_slot, advance_x: n(603) })
	first = GraphitePosition.attach(c.state, 1, 3, 100)
	second = GraphitePosition.attach(first.state, 2, 3, 100)
	shifted = GraphiteSlots.set_extra(GraphiteSlots.set_extra(second.state, 2, 31, 1), 2, 8, n(-480).to_i32_wrap())
	placed = GraphitePosition.position(shifted, False, 100)
	placed.state.advance_x == n(1082) and GraphiteSlots.get(placed.state, 1).position_x == n(380) and GraphiteSlots.get(placed.state, 2).position_x == 0 and GraphiteSlots.get(placed.state, 3).position_x == n(300)
}

expect {
	# Original two-zero-mark chain reproduces the real Scheherazade
	# interior-root case. Prefix 26 still triggers the full 27-unit relative
	# rebase; prefix 27 reaches absolute zero and suppresses it entirely.
	n = TableVar.f32_from_int
	var $good = True
	for prefix in [0, 10, 26, 27, 28, 604] {
		a = GraphiteSlots.append(GraphiteSlots.make(0, 4), { ..GraphiteSlots.no_slot, attach_x: n(30) })
		b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, attach_x: n(-27) })
		c = GraphiteSlots.append(b.state, { ..GraphiteSlots.no_slot, advance_x: n(603) })
		d = GraphiteSlots.append(c.state, { ..GraphiteSlots.no_slot, advance_x: n(prefix) })
		first = GraphitePosition.attach(d.state, 1, 2, 100)
		second = GraphitePosition.attach(first.state, 2, 3, 100)
		placed = GraphitePosition.position(second.state, True, 100)
		shift = if (prefix < 27) 27 else 0
		if placed.state.advance_x != n(prefix + 603 + shift) or GraphiteSlots.get(placed.state, 3).position_x != n(prefix + shift) {
			$good = False
		}
	}
	$good
}

# Original public controls distinguish a positive child's reserved extent
# from a zero/negative mark overlay after a preceding 602-unit root.
expect {
	n = TableVar.f32_from_int
	var $ok = True
	for advance in [-1, 0, 1, 601] {
		a = GraphiteSlots.append(GraphiteSlots.make(0, 3), { ..GraphiteSlots.no_slot, advance_x: n(602) })
		b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, advance_x: n(advance), attach_x: n(-601) })
		c = GraphiteSlots.append(b.state, { ..GraphiteSlots.no_slot, advance_x: n(603) })
		linked = GraphitePosition.attach(c.state, 2, 3, 100)
		positioned = GraphitePosition.position(linked.state, False, 100)
		child = GraphiteSlots.get(positioned.state, 2)
		root = GraphiteSlots.get(positioned.state, 3)
		$ok = $ok and positioned.stopped == 0 and child.position_x == n(if (advance > 0) 602 else 1) and root.position_x == n(if (advance > 0) 1203 else 602)
	}
	$ok
}

# Incremental collision positioning must be bit-identical to a complete
# traversal, including zero-advance origin guards and large F32 prefixes.
expect {
	n = TableVar.f32_from_int
	var $ok = True
	var $saved = 0
	for rtl in [False, True] {
		for native_rtl in [False, True] {
			for prefix in [0, 16777216] {
				for child_advance in [-1, 0, 1, 601] {
					var $state = GraphiteSlots.make(0, 5)
					for advance in [prefix, 601, 602, child_advance, 0] {
						appended = GraphiteSlots.append($state, { ..GraphiteSlots.no_slot, advance_x: n(advance), shift_y: n(7), attach_x: n(31), attach_y: n(13), with_x: n(237), with_y: n(17) })
						$state = GraphiteSlots.set_extra(appended.state, appended.id, 31, 1)
					}
					$state = GraphitePosition.attach($state, 4, 2, 1000).state
					$state = GraphitePosition.attach($state, 5, 3, 1000).state
					positioned = GraphitePosition.position_for_font($state, rtl, native_rtl, 1000)
					cache = GraphitePosition.prepare_cache(positioned.state, rtl, native_rtl, 1000)
					match cache.cache {
						Absent => {
							$ok = False
						}
						Present(prepared) => {
							for pair in [(2, 2), (4, 2), (3, 3), (5, 3)] {
								for offset in [-500, -1, 1, 500] {
									changed = GraphiteSlots.set_extra(GraphiteSlots.set_extra(positioned.state, pair.0, 8, n(offset).to_i32_wrap()), pair.0, 9, n(-offset).to_i32_wrap())
									dirty = { ..changed, positioned: False }
									full = GraphitePosition.position_for_font(dirty, rtl, native_rtl, 1000)
									partial = GraphitePosition.position_from(dirty, prepared, pair.1, rtl, native_rtl, 1000)
									$ok = $ok and full.stopped == 0 and partial.stopped == 0 and full.state.nodes == partial.state.nodes and full.state.users == partial.state.users and full.state.advance_x == partial.state.advance_x and full.state.advance_y == partial.state.advance_y and full.state.positioned == partial.state.positioned
									if partial.operations < full.operations {
										$saved = $saved + 1
									}
								}
							}
						}
					}
				}
			}
		}
	}
	$ok and $saved > 0
}

expect {
	n = TableVar.f32_from_int
	var $ok = True
	for rtl in [False, True] {
		for native_rtl in [False, True] {
			var $state = GraphiteSlots.make(0, 5)
			for advance in [16777216, 601, -300, 0, 602] {
				appended = GraphiteSlots.append($state, { ..GraphiteSlots.no_slot, advance_x: n(advance), attach_x: n(13), with_x: n(37), attach_y: n(-2), with_y: n(7) })
				$state = GraphiteSlots.set_extra(appended.state, appended.id, 31, 1)
			}
			$state = GraphitePosition.attach($state, 4, 2, 1000).state
			$state = GraphitePosition.attach($state, 5, 3, 1000).state
			$state = GraphiteSlots.set_extra($state, 2, 3, 17)
			$state = GraphitePosition.position_for_font($state, rtl, native_rtl, 1000).state
			var $cache = GraphitePosition.prepare_cache($state, rtl, native_rtl, 1000).cache
			for change in [(4, 2, -500), (1, 1, 13), (3, 3, 1), (5, 3, 510), (4, 2, 0), (1, 1, -37), (2, 2, 2)] {
				match $cache {
					Absent => {
						$ok = False
					}
					Present(prepared) => {
						changed = GraphiteSlots.set_extra($state, change.0, 8, n(change.2).to_i32_wrap())
						dirty = { ..changed, positioned: False }
						full = GraphitePosition.position_for_font(dirty, rtl, native_rtl, 1000)
						partial = GraphitePosition.position_from(dirty, prepared, change.1, rtl, native_rtl, 1000)
						fresh = GraphitePosition.prepare_cache(full.state, rtl, native_rtl, 1000)
						$ok = $ok and partial.stopped == 0 and full.state.nodes == partial.state.nodes and full.state.users == partial.state.users and full.state.advance_x == partial.state.advance_x and full.state.advance_y == partial.state.advance_y and fresh.cache == partial.cache
						$state = partial.state
						$cache = partial.cache
					}
				}
			}
		}
	}
	$ok
}

expect {
	f = attachment_fixture
	attached = GraphitePosition.attach(f.state, 1, 3, 100).state
	deleted = GraphiteSlots.delete(attached, 3)
	positioned = GraphitePosition.position_for_font(deleted, False, True, 100)
	exact = positioned.state.nodes.len() + positioned.state.active
	prepared = GraphitePosition.prepare_cache(positioned.state, False, True, exact)
	short = GraphitePosition.prepare_cache(positioned.state, False, True, exact - 1)
	match prepared.cache {
		Absent => False
		Present(cache) => {
			dirty = { ..positioned.state, positioned: False }
			full = GraphitePosition.position_for_font(dirty, False, True, 100)
			orphan = GraphitePosition.position_from(dirty, cache, 3, False, True, 100)
			exhausted = GraphitePosition.position_from(dirty, cache, 2, False, True, 0)
			prepared.operations == exact and short.operations == 0 and short.cache == Absent and orphan.cache == Absent and orphan.state.nodes == full.state.nodes and orphan.state.users == full.state.users and exhausted.stopped == 2 and exhausted.operations == 0 and exhausted.cache == Absent
		}
	}
}

expect {
	f = attachment_fixture
	positioned = GraphitePosition.position_for_font(f.state, False, False, 100)
	match GraphitePosition.prepare_cache(positioned.state, False, False, 100).cache {
		Absent => False
		Present(cache) => {
			changed = GraphitePosition.attach(positioned.state, 2, 1, 100).state
			full = GraphitePosition.position_for_font(changed, False, False, 100)
			fallback = GraphitePosition.position_from(changed, cache, 2, False, False, 100)
			fallback.cache == Absent and fallback.state.nodes == full.state.nodes and fallback.state.users == full.state.users and fallback.state.advance_x == full.state.advance_x and fallback.stopped == 0
		}
	}
}

# Public-C-API original controls establish that a deleted intermediate
# retains its attachment transform and positive/negative guard bounds.
deleted_attachment_fixture = |dead_advance, live_advance, dead_x| {
	n = TableVar.f32_from_int
	a = GraphiteSlots.append(GraphiteSlots.make(0, 4), { ..GraphiteSlots.no_slot, glyph: 1, advance_x: n(live_advance), attach_x: n(100), with_x: n(20), attach_y: n(190), with_y: n(20) })
	d = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, glyph: 2, advance_x: n(dead_advance), attach_x: n(dead_x + 20), with_x: n(20), attach_y: n(190), with_y: n(20) })
	b = GraphiteSlots.append(d.state, { ..GraphiteSlots.no_slot, glyph: 3, advance_x: n(603) })
	e = GraphiteSlots.append(b.state, { ..GraphiteSlots.no_slot, glyph: 4, advance_x: n(604) })
	first = GraphitePosition.attach(e.state, a.id, d.id, 100).state
	second = GraphitePosition.attach(first, d.id, b.id, 100).state
	GraphiteSlots.delete(second, d.id)
}

expect {
	n = TableVar.f32_from_int
	var $ok = True
	for dead_advance in [-5000, 0, 5000] {
		for live_advance in [0, 1] {
			positioned = GraphitePosition.position_for_font(deleted_attachment_fixture(dead_advance, live_advance, 80), False, False, 100)
			next_x = if (dead_advance == 5000) 5080 else 603
			$ok = $ok and positioned.stopped == 0 and GraphiteSlots.get(positioned.state, 1).position_x == n(160) and GraphiteSlots.get(positioned.state, 1).position_y == n(340) and GraphiteSlots.get(positioned.state, 2).position_x == n(80) and GraphiteSlots.get(positioned.state, 2).position_y == n(170) and GraphiteSlots.get(positioned.state, 4).position_x == n(next_x) and positioned.state.advance_x == n(next_x + 604)
		}
	}
	$ok
}

expect {
	n = TableVar.f32_from_int
	var $ok = True
	for dead_advance in [-1, 0, 1] {
		for live_advance in [0, 1] {
			positioned = GraphitePosition.position_for_font(deleted_attachment_fixture(dead_advance, live_advance, -80), False, False, 100)
			$ok = $ok and positioned.stopped == 0 and GraphiteSlots.get(positioned.state, 3).position_x == n(80) and GraphiteSlots.get(positioned.state, 2).position_x == 0 and GraphiteSlots.get(positioned.state, 1).position_x == n(80) and GraphiteSlots.get(positioned.state, 4).position_x == n(683) and positioned.state.advance_x == n(1287)
		}
	}
	$ok
}

expect {
	initial = GraphitePosition.position_for_font(deleted_attachment_fixture(5000, 1, 80), False, False, 100).state
	match GraphitePosition.prepare_cache(initial, False, False, 100).cache {
		Absent => False
		Present(cache) => {
			root = GraphiteSlots.get(initial, 3)
			dirty = GraphiteSlots.set(initial, 3, { ..root, shift_y: TableVar.f32_from_int(17) })
			full = GraphitePosition.position_for_font(dirty, False, False, 100)
			partial = GraphitePosition.position_from(dirty, cache, 3, False, False, 100)
			partial.stopped == 0 and partial.state.nodes == full.state.nodes and partial.state.users == full.state.users and partial.state.advance_x == full.state.advance_x and partial.state.advance_y == full.state.advance_y
		}
	}
}

# Original post-DELETE VM metric probes keep a linked inactive intermediate
# in the composite metric, including its descendant and reserved advance.
expect {
	n = TableVar.f32_from_int
	a = GraphiteSlots.append(GraphiteSlots.make(0, 3), { ..GraphiteSlots.no_slot, advance_x: n(100), attach_x: n(80), attach_y: n(170) })
	d = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, advance_x: n(5000), attach_x: n(80), attach_y: n(170) })
	r = GraphiteSlots.append(d.state, { ..GraphiteSlots.no_slot, advance_x: n(603) })
	first = GraphitePosition.attach(r.state, 1, 2, 100)
	second = GraphitePosition.attach(first.state, 2, 3, 100)
	deleted = GraphiteSlots.delete(second.state, 2)
	advance = GraphitePosition.metric(deleted, 3, 8, 1, False, 1000, geometry_metric)
	top = GraphitePosition.metric(deleted, 3, 2, 1, False, 1000, geometry_metric)
	right = GraphitePosition.metric(deleted, 3, 5, 1, False, 1000, geometry_metric)
	advance.stopped == 0 and advance.value == 5080 and top.value == 940 and right.value == 460
}
