import TableVar

## Stable, index-addressed Graphite slots. Zero is the null link. Deleted
## nodes remain available to a rule's immutable input snapshot; active
## order is an explicit doubly linked list rather than nested structures.
GraphiteSlots := {
	nodes : List(Slot),
	users : List(I32),
	user_count : U64,
	justification_levels : U64,
	feature_changes : List(FeatureChange),
	first : U64,
	last : U64,
	active : U64,
	positioned : Bool,
	advance_x : U32,
	advance_y : U32,
}.{

	Slot : {
		glyph : U64,
		previous : U64,
		next : U64,
		parent : U64,
		child : U64,
		last_child : U64,
		sibling : U64,
		# A stable original-character feature cell, shared by its copies.
		feature : U64,
		user_start : U64,
		before : I64,
		after : I64,
		original : I64,
		deleted : Bool,
		missing : Bool,
		insert_before : Bool,
		trace : U8,
		advance_x : U32,
		advance_y : U32,
		shift_x : U32,
		shift_y : U32,
		attach_x : U32,
		attach_y : U32,
		with_x : U32,
		with_y : U32,
		position_x : U32,
		position_y : U32,
		justify_width : U32,
		justification_defined : Bool,
		break_weight : I32,
		direction : I32,
		bidi_level : I32,
	}
	FeatureChange : [Cell(U64), Value({ previous : U64, feature : U64, value : U16 })]

	no_slot : Slot
	no_slot = { glyph: 0, previous: 0, next: 0, parent: 0, child: 0, last_child: 0, sibling: 0, feature: 0, user_start: 0, before: 0, after: 0, original: 0, deleted: False, missing: False, insert_before: True, trace: 0, advance_x: 0, advance_y: 0, shift_x: 0, shift_y: 0, attach_x: 0, attach_y: 0, with_x: 0, with_y: 0, position_x: 0, position_y: 0, justify_width: 0, justification_defined: False, break_weight: 0, direction: 0, bidi_level: 0 }

	make : U64, U64 -> GraphiteSlots
	make = |user_count, capacity| GraphiteSlots.make_with_levels(user_count, 1, capacity)

	make_with_levels : U64, U64, U64 -> GraphiteSlots
	make_with_levels = |user_count, levels, capacity| {
		justification_levels = levels.max(1)
		{ nodes: List.with_capacity(capacity + 1).append(GraphiteSlots.no_slot), users: List.with_capacity(capacity * (user_count + 32 + 4 * (justification_levels - 1))), user_count, justification_levels, feature_changes: List.with_capacity(capacity + 1).append(Cell(0)), first: 0, last: 0, active: 0, positioned: False, advance_x: 0, advance_y: 0 }
	}

	get : GraphiteSlots, U64 -> Slot
	get = |state, id| state.nodes.get(id) ?? GraphiteSlots.no_slot

	valid : GraphiteSlots, U64 -> Bool
	valid = |state, id| id != 0 and id < state.nodes.len()

	set : GraphiteSlots, U64, Slot -> GraphiteSlots
	set = |state, id, slot| {
		# Runtime checks every slot reference before mutation.
		{ ..state, nodes: state.nodes.set(id, slot) ?? [] }
	}

	append : GraphiteSlots, Slot -> { state : GraphiteSlots, id : U64 }
	append = |state, slot| GraphiteSlots.insert(state, 0, slot)

	insert : GraphiteSlots, U64, Slot -> { state : GraphiteSlots, id : U64 }
	insert = |state, before, slot| {
		{ nodes, users, user_count, justification_levels, feature_changes, first, last, active, positioned: _, advance_x, advance_y } = state
		id = nodes.len()
		previous = if (before == 0) last else (nodes.get(before) ?? GraphiteSlots.no_slot).previous
		var $nodes = nodes
		if previous != 0 {
			old = $nodes.get(previous) ?? GraphiteSlots.no_slot
			$nodes = $nodes.set(previous, { ..old, next: id }) ?? []
		}
		if before != 0 {
			old = $nodes.get(before) ?? GraphiteSlots.no_slot
			$nodes = $nodes.set(before, { ..old, previous: id }) ?? []
		}
		$nodes = $nodes.append({ ..slot, previous, next: before, user_start: users.len(), deleted: False })
		var $users = users
		for _ in 0..<(user_count + 32 + 4 * (justification_levels - 1)) {
			$users = $users.append(0)
		}
		{ id, state: { nodes: $nodes, users: $users, user_count, justification_levels, feature_changes, first: if (previous == 0) id else first, last: if (before == 0) id else last, active: active + 1, positioned: False, advance_x, advance_y } }
	}

	delete : GraphiteSlots, U64 -> GraphiteSlots
	delete = |state, id| {
		if !GraphiteSlots.valid(state, id) {
			return state
		}
		{ nodes, users, user_count, justification_levels, feature_changes, first, last, active, positioned: _, advance_x, advance_y } = state
		slot = nodes.get(id) ?? GraphiteSlots.no_slot
		if slot.deleted {
			return { nodes, users, user_count, justification_levels, feature_changes, first, last, active, positioned: False, advance_x, advance_y }
		}
		var $nodes = nodes
		if slot.previous != 0 {
			old = $nodes.get(slot.previous) ?? GraphiteSlots.no_slot
			$nodes = $nodes.set(slot.previous, { ..old, next: slot.next }) ?? []
		}
		if slot.next != 0 {
			old = $nodes.get(slot.next) ?? GraphiteSlots.no_slot
			$nodes = $nodes.set(slot.next, { ..old, previous: slot.previous }) ?? []
		}
		$nodes = $nodes.set(id, { ..slot, deleted: True }) ?? []
		{ nodes: $nodes, users, user_count, justification_levels, feature_changes, first: if (first == id) slot.next else first, last: if (last == id) slot.previous else last, active: active - 1, positioned: False, advance_x, advance_y }
	}

	get_user : GraphiteSlots, U64, U64 -> I32
	get_user = |state, id, index|
		if (index < state.user_count and GraphiteSlots.valid(state, id)) state.users.get(GraphiteSlots.get(state, id).user_start + index) ?? 0 else 0

	set_user : GraphiteSlots, U64, U64, I32 -> GraphiteSlots
	set_user = |state, id, index, value| {
		if index >= state.user_count or !GraphiteSlots.valid(state, id) {
			return state
		}
		at = GraphiteSlots.get(state, id).user_start + index
		{ ..state, users: state.users.set(at, value.to_i16_wrap().to_i32()) ?? [] }
	}

	get_extra : GraphiteSlots, U64, U64 -> I32
	get_extra = |state, id, index|
		if (index < 32 and GraphiteSlots.valid(state, id)) state.users.get(GraphiteSlots.get(state, id).user_start + state.user_count + index) ?? 0 else 0

	set_extra : GraphiteSlots, U64, U64, I32 -> GraphiteSlots
	set_extra = |state, id, index, value| {
		if index >= 32 or !GraphiteSlots.valid(state, id) {
			return state
		}
		at = GraphiteSlots.get(state, id).user_start + state.user_count + index
		{ ..state, users: state.users.set(at, value) ?? [] }
	}

	get_justification : GraphiteSlots, U64, U64, U64 -> I32
	get_justification = |state, id, level, component| {
		if level >= state.justification_levels or component >= 4 or !GraphiteSlots.valid(state, id) {
			return 0
		}
		if level == 0 {
			return GraphiteSlots.get_extra(state, id, 24 + component)
		}
		at = GraphiteSlots.get(state, id).user_start + state.user_count + 32 + 4 * (level - 1) + component
		state.users.get(at) ?? 0
	}

	set_justification : GraphiteSlots, U64, U64, U64, I32 -> GraphiteSlots
	set_justification = |state, id, level, component, value| {
		if level >= state.justification_levels or component >= 4 or !GraphiteSlots.valid(state, id) {
			return state
		}
		if level == 0 {
			return GraphiteSlots.set_extra(state, id, 24 + component, value.to_i16_wrap().to_i32())
		}
		at = GraphiteSlots.get(state, id).user_start + state.user_count + 32 + 4 * (level - 1) + component
		{ ..state, users: state.users.set(at, value.to_i16_wrap().to_i32()) ?? [] }
	}

	feature : GraphiteSlots, List(U16), U64, U64, U64 -> { value : U16, operations : U64, exhausted : Bool }
	feature = |state, defaults, cell, wanted, budget| {
		var $head = match state.feature_changes.get(cell) {
			Ok(Cell(head)) => head
			_ => crash "slot feature names an allocated character cell"
		}
		var $operations = 0
		while $head != 0 {
			if $operations >= budget {
				return { value: 0, operations: $operations, exhausted: True }
			}
			$operations = $operations + 1
			change = match state.feature_changes.get($head) {
				Ok(Value(value)) => value
				_ => crash "feature history names previously appended value nodes"
			}
			if change.feature == wanted {
				return { value: change.value, operations: $operations, exhausted: False }
			}
			$head = change.previous
		}
		{ value: defaults.get(wanted) ?? 0, operations: $operations, exhausted: False }
	}

	new_feature : GraphiteSlots -> { state : GraphiteSlots, id : U64 }
	new_feature = |state| {
		id = state.feature_changes.len()
		{ state: { ..state, feature_changes: state.feature_changes.append(Cell(0)) }, id }
	}

	set_feature : GraphiteSlots, U64, U64, U16 -> GraphiteSlots
	set_feature = |state, id, wanted, value| {
		slot = GraphiteSlots.get(state, id)
		previous = match state.feature_changes.get(slot.feature) {
			Ok(Cell(head)) => head
			_ => crash "slot feature names an allocated character cell"
		}
		head = state.feature_changes.len()
		changes = state.feature_changes.append(Value({ previous, feature: wanted, value }))
		{ ..state, feature_changes: changes.set(slot.feature, Cell(head)) ?? [] }
	}

	# Graphite's stack language converts float attributes by truncation,
	# while the final public run separately clamps to signed design units.
	integer : U32 -> I32
	integer = |bits| {
		floor = TableVar.f32_floor(bits)
		whole = if (floor < 0 and TableVar.f32_from_int(floor) != bits) floor + 1 else floor
		whole.max(-2147483648).min(2147483647).to_i32_wrap()
	}
}

expect {
	a = GraphiteSlots.append(GraphiteSlots.make(2, 3), { ..GraphiteSlots.no_slot, glyph: 1 })
	b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, glyph: 2 })
	c = GraphiteSlots.insert(b.state, a.id, { ..GraphiteSlots.no_slot, glyph: 3, trace: 2 })
	d = GraphiteSlots.delete(c.state, a.id)
	d.active == 2 and d.first == c.id and d.last == b.id and GraphiteSlots.get(d, c.id).next == b.id and GraphiteSlots.get(d, b.id).previous == c.id and GraphiteSlots.get(d, a.id).deleted and GraphiteSlots.get(d, a.id).glyph == 1
}
expect {
	a = GraphiteSlots.append(GraphiteSlots.make(1, 1), GraphiteSlots.no_slot)
	b = GraphiteSlots.set_user(a.state, a.id, 0, -17)
	GraphiteSlots.get_user(b, a.id, 0) == -17 and GraphiteSlots.get_user(b, a.id, 1) == 0
}
expect GraphiteSlots.integer(0xBF000000) == 0 and GraphiteSlots.integer(0xBFC00000) == -1 and GraphiteSlots.integer(0x4F000000) == 2147483647

expect GraphiteSlots.integer(0x5F000000) == 2147483647 and GraphiteSlots.integer(0xDF000000) == -2147483648 and GraphiteSlots.integer(0x7F7FFFFF) == 2147483647 and GraphiteSlots.integer(0xFF7FFFFF) == -2147483648

expect {
	# Copies of one original character share its mutable feature cell;
	# another original character retains independent global defaults.
	initial = GraphiteSlots.make(0, 3)
	a_cell = GraphiteSlots.new_feature(initial)
	a = GraphiteSlots.append(a_cell.state, { ..GraphiteSlots.no_slot, feature: a_cell.id })
	b_cell = GraphiteSlots.new_feature(a.state)
	b = GraphiteSlots.append(b_cell.state, { ..GraphiteSlots.no_slot, feature: b_cell.id })
	copied = GraphiteSlots.append(b.state, { ..GraphiteSlots.no_slot, feature: a_cell.id })
	changed = GraphiteSlots.set_feature(copied.state, a.id, 0, 1)
	GraphiteSlots.feature(changed, [0], a_cell.id, 0, 10).value == 1 and GraphiteSlots.feature(changed, [0], GraphiteSlots.get(changed, copied.id).feature, 0, 10).value == 1 and GraphiteSlots.feature(changed, [0], b_cell.id, 0, 10).value == 0
}
