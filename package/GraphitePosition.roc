import GraphiteSlots

## Original geometry for Graphite's stable slot forest. Attachment links
## retain deleted input slots, as required by immutable rule references.
GraphitePosition :: {}.{

	Applied : { state : GraphiteSlots, operations : U64, stopped : U64 }

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
