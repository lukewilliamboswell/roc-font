import GraphiteSlots
import GraphiteAttributes

## Direction changes reverse base/NSM groups, retaining the leading NSMs.
## This is the font-defined directionality attribute, independent of Unicode
## segmentation and of the segment's readonly direction slot attribute.
GraphiteDirection :: {}.{
	Applied : { state : GraphiteSlots, operations : U64, stopped : U64 }

	reverse : GraphiteSlots, GraphiteAttributes, U64, U64 -> Applied
	reverse = |state, attributes, direction_attribute, budget| {
		if state.active == 0 {
			return { state, operations: 0, stopped: 0 }
		}
		# Atomic relinking: preparation and mutation together visit each
		# active slot three times. Check the arithmetic in a wider type.
		if state.active.to_u128() * 3 > budget.to_u128() {
			return { state, operations: 0, stopped: 2 }
		}
		var $ids = List.with_capacity(state.active)
		var $starts = List.with_capacity(state.active)
		var $id = state.first
		while $id != 0 and $ids.len() < state.active {
			slot = GraphiteSlots.get(state, $id)
			if GraphiteAttributes.get(attributes, slot.glyph, direction_attribute).to_u8_wrap() != 16 {
				$starts = $starts.append($ids.len())
			}
			$ids = $ids.append($id)
			$id = slot.next
		}
		var $order = List.with_capacity($ids.len())
		leading = $starts.first() ?? $ids.len()
		for i in 0..<leading {
			$order = $order.append($ids.get(i) ?? crash "checked leading NSM span")
		}
		var $group = $starts.len()
		while $group != 0 {
			$group = $group - 1
			start = $starts.get($group) ?? crash "checked group index"
			end = $starts.get($group + 1) ?? $ids.len()
			for i in start..<end {
				$order = $order.append($ids.get(i) ?? crash "checked direction group")
			}
		}
		{ nodes, users, user_count, justification_levels, feature_changes, first: _, last: _, active, positioned: _, advance_x, advance_y } = state
		var $nodes = nodes
		for i in 0..<$order.len() {
			key = $order.get(i) ?? crash "checked direction order"
			slot = $nodes.get(key) ?? crash "active slot ID"
			previous = if (i == 0) 0 else $order.get(i - 1) ?? crash "prior active ID"
			next = $order.get(i + 1) ?? 0
			$nodes = $nodes.set(key, { ..slot, previous, next }) ?? []
		}
		{ state: { nodes: $nodes, users, user_count, justification_levels, feature_changes, first: $order.first() ?? 0, last: $order.last() ?? 0, active, positioned: False, advance_x, advance_y }, operations: 3 * active, stopped: 0 }
	}
}

# Original sparse attributes: glyph1 is strong RTL, glyph2 is NSM16.
direction_attributes = GraphiteAttributes.read([0.U8, 1, 0, 0, 0, 0, 0, 2, 0, 4, 0, 8, 0, 12, 0, 16], [0.U8, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 3, 1, 1, 0, 16], 3, 1024) ?? crash "original sparse directions"

direction_state = |glyphs| {
	var $state = GraphiteSlots.make(0, glyphs.len())
	for glyph in glyphs {
		added = GraphiteSlots.append($state, { ..GraphiteSlots.no_slot, glyph })
		$state = added.state
	}
	$state
}

direction_order = |state| {
	var $ids = []
	var $id = state.first
	while $id != 0 and $ids.len() < state.active {
		$ids = $ids.append($id)
		$id = GraphiteSlots.get(state, $id).next
	}
	$ids
}

expect {
	state = direction_state([1, 2, 1, 2])
	changed = GraphiteDirection.reverse(state, direction_attributes, 1, 100)
	changed.stopped == 0 and direction_order(changed.state) == [3, 4, 1, 2] and direction_order(GraphiteDirection.reverse(changed.state, direction_attributes, 1, 100).state) == [1, 2, 3, 4]
}
expect {
	state = direction_state([2, 2, 1, 2, 1])
	changed = GraphiteDirection.reverse(state, direction_attributes, 1, 100)
	direction_order(changed.state) == [1, 2, 5, 3, 4]
}
expect {
	state = direction_state([2, 2, 2])
	direction_order(GraphiteDirection.reverse(state, direction_attributes, 1, 100).state) == [1, 2, 3]
}

## fuzz regression: an exhausted direction change keeps every active link.
expect {
	state = direction_state([1, 2, 1, 2])
	changed = GraphiteDirection.reverse(state, direction_attributes, 1, 11)
	changed.stopped == 2 and changed.operations == 0 and direction_order(changed.state) == [1, 2, 3, 4]
}

# Directionality is an unsigned-byte glyph property, as independently
# pinned by values16,272,-240 and528 through the public C API.
expect {
	var $ok = True
	for value in [16.I16, 272, -240, 528] {
		bits = value.to_u16_wrap()
		attributes = GraphiteAttributes.read([0.U8, 1, 0, 0, 0, 0, 0, 2, 0, 4, 0, 8, 0, 12, 0, 16], [0.U8, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 3, 1, 1, bits.shr_zf_wrap(8).to_u8_wrap(), bits.to_u8_wrap()], 3, 1024) ?? crash "original wide direction"
		state = direction_state([1, 2, 1, 2])
		$ok = $ok and direction_order(GraphiteDirection.reverse(state, attributes, 1, 100).state) == [3, 4, 1, 2]
	}
	$ok
}
