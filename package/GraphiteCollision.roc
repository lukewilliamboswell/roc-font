import GraphiteSlots
import TableGraphite
import GraphiteSilf
import GraphiteAttributes

## Original Graphite collision state. The selected rendering description
## controls whether collision attributes exist; glyph attributes provide
## their documented initial values, independently of the Glat box format.
GraphiteCollision :: {}.{

	Context : { table : TableGraphite, sub : GraphiteSilf.Subtable, rtl : Bool }
	Applied : { state : GraphiteSlots, operations : U64, stopped : U64 }

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
