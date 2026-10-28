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
		s = GraphiteSlots.get(state, id)
		when_float = |bits| GraphiteSlots.integer(bits)
		match attribute {
			0 => when_float(s.advance_x)
			1 => when_float(s.advance_y)
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
			29 => when_float(s.justify_width)
			55 => GraphiteSlots.get_user(state, id, index)
			56 => s.bidi_level
			_ if attribute >= 25 and attribute <= 28 => GraphiteSlots.get_extra(state, id, attribute - 1)
			_ if attribute >= 54 and attribute <= 77 => GraphiteSlots.get_extra(state, id, attribute - 54)
			_ => 0
		}
	}

	set : GraphiteSlots, U64, U64, U64, I32 -> GraphiteSlots
	set = |state, id, attribute, index, value| {
		if !GraphiteSlots.valid(state, id) {
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
			14 => { ..s, break_weight: value }
			16 => { ..s, direction: value }
			17 => { ..s, insert_before: value != 0 }
			20 => { ..s, shift_x: float }
			21 => { ..s, shift_y: float }
			29 => { ..s, justify_width: float }
			56 => { ..s, bidi_level: value }
			13 => return GraphiteSlots.set_extra(state, id, 28, value)
			22 => return GraphiteSlots.set_user(state, id, 0, value)
			55 => return GraphiteSlots.set_user(state, id, index, value)
			_ if attribute >= 25 and attribute <= 28 => return GraphiteSlots.set_extra(state, id, attribute - 1, value)
			_ if attribute >= 54 and attribute <= 77 => return GraphiteSlots.set_extra(state, id, attribute - 54, value)
			_ => return state
		}
		GraphiteSlots.set({ ..state, positioned: False }, id, updated)
	}
}

expect {
	a = GraphiteSlots.append(GraphiteSlots.make(3, 1), GraphiteSlots.no_slot)
	b = GraphiteSlotAttributes.set(a.state, a.id, 55, 2, -17)
	c = GraphiteSlotAttributes.set(b, a.id, 20, 0, -123)
	d = GraphiteSlotAttributes.set(c, a.id, 65, 0, 700)
	GraphiteSlotAttributes.get(d, a.id, 55, 2) == -17 and GraphiteSlotAttributes.get(d, a.id, 20, 0) == -123 and GraphiteSlotAttributes.get(d, a.id, 65, 0) == 700 and GraphiteSlotAttributes.get(d, a.id, 0, 0) == 0
}
