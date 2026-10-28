import GraphiteSlots
import TableVar

## Slot attribute numbers are the documented Graphite ABI. Geometry stays
## in binary32 until a stack instruction requests an integer conversion.
GraphiteSlotAttributes :: {}.{
	get : GraphiteSlots, U64, U64, U64 -> I32
	get = |state, id, attribute, index| {
		if !GraphiteSlots.valid(state, id) {
			return 0
		}
		if attribute >= 57 and GraphiteSlots.get_extra(state, id, 31) == 0 {
			return 0
		}
		s = GraphiteSlots.get(state, id)
		when_float = |bits| GraphiteSlots.integer(bits)
		match attribute {
			0 => when_float(s.advance_x)
			1 => when_float(s.advance_y)
			2 => if (s.parent != 0) 1 else 0
			3 => when_float(s.attach_x)
			4 => when_float(s.attach_y)
			8 => when_float(s.with_x)
			9 => when_float(s.with_y)
			13 => GraphiteSlots.get_extra(state, id, 28)
			14 => s.break_weight
			16 => s.direction
			17 => if (s.insert_before) 1 else 0
			18 => when_float(s.position_x)
			19 => when_float(s.position_y)
			20 => when_float(s.shift_x)
			21 => when_float(s.shift_y)
			22 => GraphiteSlots.get_user(state, id, 0)
			23 => -1
			24 => -1
			29 => when_float(s.justify_width)
			55 => GraphiteSlots.get_user(state, id, index)
			56 => 0
			62 => GraphiteSlots.integer(GraphiteSlots.get_extra(state, id, 8).to_u32_wrap())
			63 => GraphiteSlots.integer(GraphiteSlots.get_extra(state, id, 9).to_u32_wrap())
			_ if attribute >= 25 and attribute <= 28 => GraphiteSlots.get_justification(state, id, index, attribute - 25)
			_ if attribute >= 54 and attribute <= 77 => GraphiteSlots.get_extra(state, id, attribute - 54)
			_ => 0
		}
	}

	set : GraphiteSlots, U64, U64, U64, I32 -> GraphiteSlots
	set = |state, id, attribute, index, value| {
		if !GraphiteSlots.valid(state, id) {
			return state
		}
		if attribute >= 57 and GraphiteSlots.get_extra(state, id, 31) == 0 {
			return state
		}
		s = GraphiteSlots.get(state, id)
		float = TableVar.f32_from_int(value.to_i64())
		updated = match attribute {
			0 => { ..s, advance_x: float }
			1 => { ..s, advance_y: float }
			3 => { ..s, attach_x: float }
			4 => { ..s, attach_y: float }
			8 => { ..s, with_x: float }
			9 => { ..s, with_y: float }
			14 => { ..s, break_weight: value.to_i8_wrap().to_i32() }
			16 => return state
			17 => { ..s, insert_before: value != 0 }
			20 => { ..s, shift_x: float }
			21 => { ..s, shift_y: float }
			29 => { ..s, justify_width: float }
			56 => return state
			13 => return GraphiteSlots.set_extra(state, id, 28, value.to_u8_wrap().to_i32())
			22 => return GraphiteSlots.set_user(state, id, 0, value)
			55 => return GraphiteSlots.set_user(state, id, index, value)
			_ if attribute >= 25 and attribute <= 28 => return GraphiteSlots.set_justification(state, id, index, attribute - 25, value)
			54 => return GraphiteSlots.set_extra(state, id, 0, value.bitwise_and(3))
			62 => return state
			63 => return state
			_ if attribute >= 57 and attribute <= 77 => {
				unsigned = [57.U64, 64, 65, 66, 69, 70, 71, 73, 75, 76, 77].contains(attribute)
				stored = if (unsigned) value.to_u16_wrap().to_i32() else value.to_i16_wrap().to_i32()
				return GraphiteSlots.set_extra(if (attribute == 57) { ..state, positioned: False } else state, id, attribute - 54, stored)
			}
			_ => return state
		}
		GraphiteSlots.set({ ..state, positioned: False }, id, updated)
	}
}

expect {
	a = GraphiteSlots.append(GraphiteSlots.make(3, 1), GraphiteSlots.no_slot)
	b = GraphiteSlotAttributes.set(GraphiteSlots.set_extra(a.state, a.id, 31, 1), a.id, 55, 2, -17)
	c = GraphiteSlotAttributes.set(b, a.id, 20, 0, -123)
	d = GraphiteSlotAttributes.set(c, a.id, 65, 0, 700)
	GraphiteSlotAttributes.get(d, a.id, 55, 2) == -17 and GraphiteSlotAttributes.get(d, a.id, 20, 0) == -123 and GraphiteSlotAttributes.get(d, a.id, 65, 0) == 700 and GraphiteSlotAttributes.get(d, a.id, 0, 0) == 0
}

expect {
	a = GraphiteSlots.append(GraphiteSlots.make(1, 1), GraphiteSlots.no_slot)
	b = GraphiteSlotAttributes.set(a.state, a.id, 13, 0, 300)
	c = GraphiteSlotAttributes.set(b, a.id, 14, 0, 40000)
	d = GraphiteSlotAttributes.set(c, a.id, 55, 0, 40000)
	e = GraphiteSlotAttributes.set(d, a.id, 54, 0, 123)
	GraphiteSlotAttributes.get(e, a.id, 13, 0) == 44 and GraphiteSlotAttributes.get(e, a.id, 14, 0) == 64 and GraphiteSlotAttributes.get(e, a.id, 55, 0) == -25536 and GraphiteSlotAttributes.get(e, a.id, 54, 0) == 3 and GraphiteSlotAttributes.get(e, a.id, 23, 0) == -1
}
expect {
	a = GraphiteSlots.append(GraphiteSlots.make(0, 1), GraphiteSlots.no_slot)
	b = GraphiteSlotAttributes.set(a.state, a.id, 62, 0, 100)
	enabled = GraphiteSlots.set_extra(b, a.id, 31, 1)
	c = GraphiteSlots.set_extra(enabled, a.id, 8, TableVar.f32_from_int(100).to_i32_wrap())
	d = GraphiteSlotAttributes.set(c, a.id, 62, 0, 200)
	GraphiteSlotAttributes.get(b, a.id, 62, 0) == 0 and GraphiteSlotAttributes.get(d, a.id, 62, 0) == 100 and GraphiteSlots.get_extra(c, a.id, 8).to_u32_wrap() == TableVar.f32_from_int(100)
}

expect {
	a = GraphiteSlots.append(GraphiteSlots.make_with_levels(2, 3, 2), GraphiteSlots.no_slot)
	b = GraphiteSlots.append(a.state, GraphiteSlots.no_slot)
	c = GraphiteSlotAttributes.set(b.state, a.id, 25, 2, 40000)
	d = GraphiteSlotAttributes.set(c, b.id, 26, 1, 123)
	e = GraphiteSlots.set_user(d, a.id, 1, -17)
	GraphiteSlotAttributes.get(e, a.id, 25, 2) == -25536 and GraphiteSlotAttributes.get(e, b.id, 26, 1) == 123 and GraphiteSlotAttributes.get(e, a.id, 26, 1) == 0 and GraphiteSlots.get_user(e, a.id, 1) == -17 and GraphiteSlotAttributes.get(e, b.id, 25, 3) == 0
}
