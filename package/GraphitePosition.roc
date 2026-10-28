import GraphiteSlots
import TableVar

## Original geometry for Graphite's stable slot forest. Attachment links
## retain deleted input slots, as required by immutable rule references.
GraphitePosition :: {}.{

	Applied : { state : GraphiteSlots, operations : U64, stopped : U64 }
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
	metric = |input, id, wanted, level, rtl, budget, base_metric| {
		if !GraphiteSlots.valid(input, id) {
			return { state: input, value: 0, operations: 0, stopped: 0 }
		}
		if level == 0 {
			return { value: base_metric(GraphiteSlots.get(input, id).glyph, wanted, 0), state: input, operations: 0, stopped: 0 }
		}
		prepared = GraphitePosition.position(input, rtl, budget)
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
		root_shift = GraphitePosition.shift_x(root, rtl)
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
			if !child.deleted and GraphiteSlots.get_extra(state, frame.id, 28) <= level.to_u8_wrap().to_i32() {
				shift = GraphitePosition.shift_x(child, rtl)
				x = TableVar.f32_add(TableVar.f32_add(TableVar.f32_sub(child.attach_x, child.with_x), frame.x), TableVar.f32_add(shift, child.justify_width))
				y = TableVar.f32_add(TableVar.f32_add(TableVar.f32_sub(child.attach_y, child.with_y), frame.y), child.shift_y)
				$right = TableVar.f32_max($right, TableVar.f32_add(TableVar.f32_sub(x, shift), child.advance_x))
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
	position = |state, rtl, budget| {
		if state.positioned {
			return { state, operations: 0, stopped: 0 }
		}
		{ nodes, users, user_count, justification_levels, feature_changes, first, last, active, positioned: _, advance_x: _, advance_y: _ } = state
		var $nodes = nodes
		var $users = users
		var $operations = 0
		var $stopped = 0
		var $pen_x = 0
		var $pen_y = 0
		var $id = if (rtl) last else first
		var $walked = 0
		var $previous_root = 0
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
				# The public C API includes subsequent roots in the sibling chain.
				if $previous_root != 0 {
					previous = $nodes.get($previous_root) ?? GraphiteSlots.no_slot
					$nodes = $nodes.set($previous_root, { ..previous, sibling: root_id }) ?? []
				}
				$previous_root = root_id
				root_shift = GraphitePosition.shift_x(root, rtl)
				root_x = TableVar.f32_add(root_shift, root.justify_width)
				var $right = TableVar.f32_add(root.advance_x, root.justify_width)
				var $left = 0
				var $cluster_y = root.advance_y
				$members = $members.clear().append(root_id)
				$nodes = $nodes.set(root_id, { ..root, position_x: root_x, position_y: root.shift_y, sibling: 0 }) ?? []
				$pending = $pending.clear()
				if root.child != 0 {
					$pending = $pending.append({ id: root.child, x: root_x, y: root.shift_y })
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
					frame = $pending.last() ?? { id: 0, x: 0, y: 0 }
					$pending = $pending.drop_last(1)
					child = $nodes.get(frame.id) ?? GraphiteSlots.no_slot
					if child.sibling != 0 {
						$pending = $pending.append({ ..frame, id: child.sibling })
					}
					if !child.deleted {
						shift = GraphitePosition.shift_x(child, rtl)
						x = TableVar.f32_add(TableVar.f32_add(TableVar.f32_sub(child.attach_x, child.with_x), frame.x), TableVar.f32_add(shift, child.justify_width))
						y = TableVar.f32_add(TableVar.f32_add(TableVar.f32_sub(child.attach_y, child.with_y), frame.y), child.shift_y)
						$nodes = $nodes.set(frame.id, { ..child, position_x: x, position_y: y }) ?? []
						$members = $members.append(frame.id)
						$right = TableVar.f32_max($right, TableVar.f32_add(TableVar.f32_sub(x, shift), child.advance_x))
						$left = TableVar.f32_min($left, TableVar.f32_sub(x, root_x))
						if child.child != 0 {
							$pending = $pending.append({ id: child.child, x, y })
						}
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
					enabled = ($users.get(at + 31) ?? 0) != 0
					ox = if (enabled) ($users.get(at + 8) ?? 0).to_u32_wrap() else 0
					oy = if (enabled) ($users.get(at + 9) ?? 0).to_u32_wrap() else 0
					# Advances/rebasing above use authored geometry. Physical
					# origins are a second parent-first walk: a moved parent
					# moves its descendants, with binary32 rounding at each edge.
					point = if member == root_id {
						{ x: TableVar.f32_add(origin_x, TableVar.f32_add(root_x, ox)), y: TableVar.f32_add($pen_y, TableVar.f32_add(root.shift_y, oy)) }
					} else {
						parent = $nodes.get(slot.parent) ?? GraphiteSlots.no_slot
						shift = TableVar.f32_add(GraphitePosition.shift_x(slot, rtl), slot.justify_width)
						{ x: TableVar.f32_add(TableVar.f32_add(TableVar.f32_sub(slot.attach_x, slot.with_x), parent.position_x), TableVar.f32_add(shift, ox)), y: TableVar.f32_add(TableVar.f32_add(TableVar.f32_sub(slot.attach_y, slot.with_y), parent.position_y), TableVar.f32_add(slot.shift_y, oy)) }
					}
					$nodes = $nodes.set(member, { ..slot, position_x: point.x, position_y: point.y }) ?? []
				}
				# Cache full-cluster advances without overwriting authored metrics.
				$users = $users.set(root.user_start + user_count + 29, cluster_x.to_i32_wrap()) ?? []
				$users = $users.set(root.user_start + user_count + 30, $cluster_y.to_i32_wrap()) ?? []
				$pen_x = TableVar.f32_add($pen_x, cluster_x)
				$pen_y = TableVar.f32_add($pen_y, $cluster_y)
			}
		}
		{ state: { nodes: $nodes, users: $users, user_count, justification_levels, feature_changes, first, last, active, positioned: $stopped == 0, advance_x: $pen_x, advance_y: $pen_y }, operations: $operations, stopped: $stopped }
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
		$nodes = $nodes.set(id, { ..slot, parent, sibling: 0, insert_before: False }) ?? []
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
	GraphiteSlots.get(b.state, f.b).child == f.a and GraphiteSlots.get(b.state, f.a).sibling == f.c and GraphiteSlots.get(b.state, f.c).parent == f.b and !GraphiteSlots.get(b.state, f.c).insert_before
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
	GraphiteSlots.get(c.state, 1).position_x == TableVar.f32_from_int(-140) and GraphiteSlots.get(c.state, 2).position_x == TableVar.f32_from_int(-220) and c.state.advance_x == TableVar.f32_from_int(1284)
}
expect {
	# Public C-API witness with512 preceding32768-unit glyphs. Rounding
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
