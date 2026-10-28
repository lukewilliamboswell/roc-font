import Bytes
import GraphiteCode
import GraphiteArithmetic
import GraphiteClasses
import GraphiteSilf
import GraphiteAttributes
import GraphiteFeatures
import GraphitePosition
import GraphiteSlots
import GraphiteSlotAttributes
import TableGraphite
import TableVar

## A bounded interpreter over prepared Graphite instructions. Glyph writes protect
## original input glyphs; ordinary attributes stay live on stable slot IDs.
GraphiteMachine :: {}.{
	Context : { table : TableGraphite, sub : GraphiteSilf.Subtable, defaults : List(U16), rtl : Bool, reverse : Bool }
	Input : { ids : List(U64), slots : List(GraphiteSlots.Slot), users : List(I32), base : I64, length : U64, start : I64, current : I64 }
	Limits : { operations : U64, glyphs : U64 }
	Result : { state : GraphiteSlots, input : I64, cursor : U64, value : I32, operations : U64, stopped : U64, aborted : Bool }

	run : Context, GraphiteSilf.Program, GraphiteSlots, Input, Limits, (U64, U64, I32 -> I32) -> Result
	run = |ctx, program, state, input, limits, metric| {
		var $state = state
		var $input = input.current
		var $cursor = input.ids.get($input.to_u64_wrap()) ?? 0
		var $pc = program.start
		var $stack = List.with_capacity(program.max_stack.min(1024))
		var $operations = 0
		var $backups = input.slots
		var $saved_users = []
		if program.copies {
			stride = state.user_count + 32 + 4 * (state.justification_levels - 1)
			for at in program.protected_start..<program.protected_end {
				encoded = ctx.table.program.protected_inputs.get(at) ?? crash "prepared protected input span"
				position = input.start + encoded.to_i64_wrap() - 4294967296
				if GraphiteMachine.has_input(input, position) {
					old = input.slots.get(position.to_u64_wrap()) ?? crash "protected input in snapshot"
					start = $saved_users.len()
					for i in 0..<stride {
						if $operations >= limits.operations {
							return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: 2, aborted: False }
						}
						$operations = $operations + 1
						$saved_users = $saved_users.append(state.users.get(old.user_start + i) ?? 0)
					}
					$backups = $backups.set(position.to_u64_wrap(), { ..old, user_start: start }) ?? []
				}
			}
		}
		snapshot = { ..input, slots: $backups, users: $saved_users }
		while $pc < program.end {
			if $operations >= limits.operations {
				return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: 2, aborted: False }
			}
			$operations = $operations + 1
			instruction = ctx.table.program.instructions.get($pc) ?? crash "prepared program span"
			op = instruction.opcode
			$pc = $pc + 1
			if op >= 1 and op <= 5 {
				$stack = $stack.append(instruction.a)
			} else if op == 0x0C or op == 0x0D or op == 0x0E or op == 0x12 or op == 0x40 {
				value = $stack.last() ?? crash "validated unary stack depth"
				$stack = $stack.drop_last(1).append(GraphiteArithmetic.unary(op, value))
			} else if (op >= 6 and op <= 0x0B) or op == 0x10 or op == 0x11 or (op >= 0x13 and op <= 0x18) or op == 0x3E or op == 0x3F {
				right = $stack.last() ?? crash "validated binary stack depth"
				left = $stack.get($stack.len() - 2) ?? crash "validated binary stack depth"
				match GraphiteArithmetic.binary(op, left, right) {
					Ok(value) => {
						$stack = $stack.drop_last(2).append(value)
					}
					Err(_) => return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: 0, aborted: True }
				}
			} else if op == 0x0F {
				condition = $stack.get($stack.len() - 3) ?? crash "validated conditional stack depth"
				yes = $stack.get($stack.len() - 2) ?? 0
				no = $stack.last() ?? 0
				$stack = $stack.drop_last(3).append(if (condition != 0) yes else no)
			} else if op == 0x41 {
				value = $stack.last() ?? crash "validated bit operation stack depth"
				$stack = $stack.drop_last(1).append(value.bitwise_and(instruction.a.bitwise_xor(-1)).bitwise_or(instruction.b))
			} else if op == 0x30 or op == 0x31 or op == 0x32 {
				if $stack.len() != (if (op == 0x30) 1 else 0) {
					return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: 0, aborted: True }
				}
				value = if (op == 0x30) $stack.last() ?? 0 else if (op == 0x32) 1 else 0
				return { state: $state, input: $input, cursor: $cursor, value, operations: $operations, stopped: 0, aborted: False }
			} else if op == 0x22 {
				if $input != input.start + instruction.a.to_i64() {
					$pc = program.start + instruction.target
					$stack = $stack.append(1)
				}
			} else if op == 0x36 or op == 0x37 {
				$stack = $stack.append(if (op == 0x36) 1 else 0)
			} else if op == 0x19 or op == 0x1B {
				if op == 0x1B {
					source = GraphiteMachine.reference(ctx.table.program, program, $state, snapshot, $input)
					copied = GraphiteMachine.copy($state, $cursor, source.id, source.slot, if (source.frozen) Frozen(snapshot.users) else Live, limits.operations - $operations)
					$state = copied.state
					$operations = $operations + copied.operations
					if copied.aborted or copied.stopped != 0 {
						return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: copied.stopped, aborted: copied.aborted }
					}
				}
				$cursor = if ($cursor == 0 and $input < input.slots.len().to_i64_wrap()) GraphiteMachine.initial($state, ctx.reverse) else GraphiteMachine.forward($state, $cursor, ctx.reverse)
				$input = $input + 1
			} else if op == 0x1C or op == 0x3B or op == 0x1D or op == 0x38 {
				var $position = 0
				out_class = if (op == 0x1C or op == 0x3B) instruction.a else instruction.c
				if op == 0x1D or op == 0x38 {
					source = GraphiteMachine.reference(ctx.table.program, program, $state, snapshot, $input + instruction.a.to_i64()).slot
					class = ctx.table.program.classes.get(ctx.sub.class_start + instruction.b.to_u64_wrap()) ?? crash "prepared input class"
					found = GraphiteClasses.index_bounded(ctx.table.program.data, class, source.glyph, limits.operations - $operations)
					$operations = $operations + found.operations
					if found.stopped != 0 {
						return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: found.stopped, aborted: False }
					}
					match found.result {
						Found(index) => {
							$position = index
						}
						Missing => return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: 0, aborted: True }
					}
				}
				class = ctx.table.program.classes.get(ctx.sub.class_start + out_class.to_u64_wrap()) ?? crash "prepared output class"
				found = GraphiteClasses.glyph_bounded(ctx.table.program.data, class, $position, limits.operations - $operations)
				$operations = $operations + found.operations
				if found.stopped != 0 {
					return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: found.stopped, aborted: False }
				}
				match found.result {
					Found(glyph) => {
						s = GraphiteSlots.get($state, $cursor)
						$state = GraphiteSlots.set({ ..$state, positioned: False }, $cursor, { ..s, glyph, missing: False, advance_x: TableVar.f32_from_int(metric(glyph, 8, 0).to_i64()), advance_y: TableVar.f32_from_int(metric(glyph, 9, 0).to_i64()), trace: if (s.trace == 2) 2 else 1 })
					}
					Missing => return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: 0, aborted: True }
				}
			} else if op == 0x1E {
				source = GraphiteMachine.reference(ctx.table.program, program, $state, snapshot, $input + instruction.a.to_i64())
				copied = GraphiteMachine.copy($state, $cursor, source.id, source.slot, if (source.frozen) Frozen(snapshot.users) else Live, limits.operations - $operations)
				$state = copied.state
				$operations = $operations + copied.operations
				if copied.aborted or copied.stopped != 0 {
					return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: copied.stopped, aborted: copied.aborted }
				}
			} else if op == 0x1F {
				if $state.active >= limits.glyphs {
					return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: 1, aborted: False }
				}
				source = GraphiteSlots.get($state, $cursor)
				insertion = if (ctx.reverse) (if ($cursor == 0) $state.first else GraphiteSlots.get($state, $cursor).next) else $cursor
				inserted = GraphiteSlots.insert($state, insertion, { ..GraphiteSlots.no_slot, before: source.before, after: source.before, original: source.original, direction: if (ctx.rtl) 1 else 0, feature: source.feature, trace: 2 })
				$state = inserted.state
				$cursor = inserted.id
				$input = $input - 1
			} else if op == 0x20 {
				s = GraphiteSlots.get($state, $cursor)
				$state = GraphiteSlots.delete($state, $cursor)
				$cursor = if (ctx.reverse) s.next else s.previous
			} else if op == 0x21 {
				var $before = 9223372036854775807.I64
				var $after = -1.I64
				for i in 0..<instruction.a.to_u64_wrap() {
					at = Bytes.u8(ctx.table.program.data, instruction.at + 2 + i).to_i8_wrap().to_i64()
					s = GraphiteMachine.reference(ctx.table.program, program, $state, snapshot, $input + at).slot
					$before = $before.min(s.before)
					$after = $after.max(s.after)
				}
				if $after >= 0 {
					s = GraphiteSlots.get($state, $cursor)
					$state = GraphiteSlots.set($state, $cursor, { ..s, before: $before, after: $after })
				}
			} else if (op >= 0x23 and op <= 0x27) or (op >= 0x33 and op <= 0x35) {
				value = $stack.last() ?? crash "validated attribute stack depth"
				$stack = $stack.drop_last(1)
				attribute = instruction.a.to_u64_wrap()
				index = if (op == 0x27 or op >= 0x33) instruction.b.to_u64_wrap() else 0
				if attribute >= 25 and attribute <= 28 {
					prepared = GraphiteMachine.ensure_justification(ctx, $state, $cursor, limits.operations - $operations)
					$state = prepared.state
					$operations = $operations + prepared.operations
					if prepared.stopped != 0 {
						return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: prepared.stopped, aborted: False }
					}
				}
				old = GraphiteSlotAttributes.get($state, $cursor, attribute, index)
				adjusted = if (op == 0x24 or op == 0x34) (old.to_i64() + value.to_i64()).to_i32_wrap() else if (op == 0x25 or op == 0x35) (old.to_i64() - value.to_i64()).to_i32_wrap() else value
				if attribute == 2 {
					position = if (op == 0x26 or op == 0x27) $input + value.to_i64() else input.base + value.to_i64()
					if GraphiteMachine.has_input(input, position) {
						parent = input.ids.get(position.to_u64_wrap()) ?? crash "checked rule input map"
						var $output_position = $input
						for i in 0..<input.ids.len() {
							if $operations >= limits.operations {
								return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: 2, aborted: False }
							}
							$operations = $operations + 1
							if input.ids.get(i) == Ok($cursor) {
								$output_position = i.to_i64_wrap()
								break
							}
						}
						parent_after = if (ctx.reverse) position < $output_position else position > $output_position
						attached = GraphitePosition.attach_with_direction($state, $cursor, parent, parent_after, ctx.rtl, limits.operations - $operations)
						$state = attached.state
						$operations = $operations + attached.operations
						if attached.stopped != 0 {
							return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: attached.stopped, aborted: False }
						}
					}
				} else {
					$state = GraphiteSlotAttributes.set($state, $cursor, attribute, index, adjusted)
				}
			} else if (op >= 0x28 and op <= 0x2E) or op == 0x3C or op == 0x3D or op == 0x42 {
				position = $input + instruction.b.to_i64()
				if !GraphiteMachine.has_input(input, position) {
					if op == 0x42 {
						$stack = $stack.drop_last(1)
					} else {
						$stack = $stack.append(0)
					}
				} else {
					s = GraphiteMachine.reference(ctx.table.program, program, $state, snapshot, position).slot
					id = input.ids.get(position.to_u64_wrap()) ?? 0
					var $value = 0.I32
					if op == 0x28 or op == 0x2E {
						if instruction.a == 18 or instruction.a == 19 {
							located = GraphitePosition.position_for_font($state, ctx.rtl, ctx.sub.direction.bitwise_and(1) == 0, limits.operations - $operations)
							$state = located.state
							$operations = $operations + located.operations
							if located.stopped != 0 {
								return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: located.stopped, aborted: False }
							}
						}
						attribute = instruction.a.to_u64_wrap()
						index = if (op == 0x2E) instruction.c.to_u64_wrap() else 0
						$value = if (attribute >= 25 and attribute <= 28 and !GraphiteSlots.get($state, id).justification_defined) GraphiteMachine.justification_default(ctx, GraphiteSlots.get($state, id).glyph, index, attribute - 25) else GraphiteSlotAttributes.get($state, id, attribute, index)
					} else if op == 0x29 or op == 0x3C or op == 0x2C or op == 0x3D {
						parent = GraphiteSlots.get($state, id).parent
						if op == 0x29 or op == 0x3C {
							$value = GraphiteAttributes.get(ctx.table.attributes, s.glyph, instruction.a.to_u64_wrap())
						}
						else if parent != 0 {
							$value = GraphiteAttributes.get(ctx.table.attributes, GraphiteSlots.get($state, parent).glyph, instruction.a.to_u64_wrap())
						}
					} else if op == 0x2A or op == 0x2D {
						parent = GraphiteSlots.get($state, id).parent
						metric_id = if (op == 0x2D) parent else id
						if instruction.c == 0 {
							if op == 0x2A {
								$value = metric(s.glyph, instruction.a.to_u64_wrap(), 0)
							}
							else if parent != 0 {
								$value = metric(GraphiteSlots.get($state, parent).glyph, instruction.a.to_u64_wrap(), 0)
							}
						} else {
							measured = GraphitePosition.metric_for_font($state, metric_id, instruction.a.to_u64_wrap(), instruction.c, ctx.rtl, ctx.sub.direction.bitwise_and(1) == 0, limits.operations - $operations, metric)
							$state = measured.state
							$operations = $operations + measured.operations
							if measured.stopped != 0 {
								return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: measured.stopped, aborted: False }
							}
							$value = measured.value
						}
					} else {
						feature = instruction.a.to_u64_wrap()
						definition = ctx.table.features.features.get(feature) ?? crash "prepared feature index"
						if op == 0x42 {
							value = $stack.last() ?? crash "validated SetFeat stack depth"
							$stack = $stack.drop_last(1)
							$state = GraphiteSlots.set_feature($state, id, definition.alias, value.to_u32_wrap().min(definition.maximum.to_u32()).to_u16_wrap())
						} else {
							resolved = GraphiteSlots.feature($state, ctx.defaults, GraphiteSlots.get($state, id).feature, definition.alias, limits.operations - $operations)
							$operations = $operations + resolved.operations
							if resolved.exhausted {
								return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: 2, aborted: False }
							}
							$value = resolved.value.to_i16_wrap().to_i32()
						}
					}
					if op != 0x42 {
						$stack = $stack.append($value)
					}
				}
			}
			# The pinned engine accepts larger programs at reading, then
			# aborts text that reaches its 1024th simultaneous stack value.
			if $stack.len() >= 1024 {
				return { state: $state, input: $input, cursor: $cursor, value: 0, operations: $operations, stopped: 0, aborted: True }
			}
		}
		{ state: $state, input: $input, cursor: $cursor, value: 1, operations: $operations, stopped: 0, aborted: False }
	}

	justification_default : Context, U64, U64, U64 -> I32
	justification_default = |ctx, glyph, level, component| {
		if level >= ctx.sub.justification_count or component >= 4 {
			return 0
		}
		attribute = Bytes.u8(ctx.table.program.data, ctx.sub.justification_start + level * 8 + component)
		GraphiteAttributes.get(ctx.table.attributes, glyph, attribute)
	}

	ensure_justification : Context, GraphiteSlots, U64, U64 -> GraphitePosition.Applied
	ensure_justification = |ctx, state, id, budget| {
		slot = GraphiteSlots.get(state, id)
		if slot.justification_defined {
			return { state, operations: 0, stopped: 0 }
		}
		count = state.justification_levels * 4
		if count > budget {
			return { state, operations: 0, stopped: 2 }
		}
		var $state = state
		for level in 0..<$state.justification_levels {
			for component in 0..<4 {
				$state = GraphiteSlots.set_justification($state, id, level, component, GraphiteMachine.justification_default(ctx, slot.glyph, level, component))
			}
		}
		{ state: GraphiteSlots.set($state, id, { ..slot, justification_defined: True }), operations: count, stopped: 0 }
	}

	initial : GraphiteSlots, Bool -> U64
	initial = |state, reverse| if (reverse) state.last else state.first
	forward : GraphiteSlots, U64, Bool -> U64
	forward = |state, id, reverse| if (reverse) GraphiteSlots.get(state, id).previous else GraphiteSlots.get(state, id).next
	backward : GraphiteSlots, U64, Bool -> U64
	backward = |state, id, reverse| if (reverse) GraphiteSlots.get(state, id).next else GraphiteSlots.get(state, id).previous

	has_input : Input, I64 -> Bool
	has_input = |input, index| index >= input.base and index - input.base < input.length.to_i64_wrap()

	reference : GraphiteSilf, GraphiteSilf.Program, GraphiteSlots, Input, I64 -> { slot : GraphiteSlots.Slot, id : U64, frozen : Bool }
	reference = |table, program, state, input, index| {
		if !GraphiteMachine.has_input(input, index) {
			return { slot: GraphiteSlots.no_slot, id: 0, frozen: False }
		}
		key = (index - input.start + 4294967296).to_u64_wrap()
		var $lo = program.protected_start
		var $hi = program.protected_end
		while $lo < $hi {
			mid = $lo + ($hi - $lo) // 2
			if (table.protected_inputs.get(mid) ?? 0) < key {
				$lo = mid + 1
			} else {
				$hi = mid
			}
		}
		frozen = $lo < program.protected_end and table.protected_inputs.get($lo) == Ok(key)
		id = input.ids.get(index.to_u64_wrap()) ?? crash "bounded input ID"
		{ id, frozen, slot: if (frozen) input.slots.get(index.to_u64_wrap()) ?? crash "bounded protected input" else GraphiteSlots.get(state, id) }
	}

	real : Context, U64 -> U64
	real = |ctx, glyph| {
		pseudo = GraphiteAttributes.get(ctx.table.attributes, glyph, ctx.sub.pseudo_attribute)
		if (pseudo != 0) pseudo.to_u16_wrap().to_u64() else glyph
	}

	copy : GraphiteSlots, U64, U64, GraphiteSlots.Slot, [Frozen(List(I32)), Live], U64 -> GraphitePosition.Copied
	copy = |state, id, source_id, source, saved, budget| {
		if !GraphiteSlots.valid(state, id) or !GraphiteSlots.valid(state, source_id) {
			return { state, operations: 0, stopped: 0, aborted: True }
		}
		if source_id == id {
			match saved {
				Live => return { state, operations: 0, stopped: 0, aborted: False }
				Frozen(_) => {}
			}
		}
		stride = state.user_count + 32 + 4 * (state.justification_levels - 1)
		if stride > budget {
			return { state, operations: 0, stopped: 2, aborted: False }
		}
		attached = GraphitePosition.copy_attachment_from(state, id, source_id, source.parent, budget - stride)
		if attached.aborted or attached.stopped != 0 {
			return attached
		}
		{ nodes, users, user_count, justification_levels, feature_changes, first, last, active, positioned: _, advance_x, advance_y } = attached.state
		current = nodes.get(id) ?? crash "checked destination ID"
		var $users = users
		for i in 0..<stride {
			value = match saved {
				Frozen(values) => values.get(source.user_start + i) ?? 0
				Live => $users.get(source.user_start + i) ?? 0
			}
			$users = $users.set(current.user_start + i, value) ?? []
		}
		updated = { ..source, previous: current.previous, next: current.next, parent: current.parent, child: current.child, last_child: current.last_child, sibling: current.sibling, user_start: current.user_start, deleted: False, trace: if (current.trace == 2) 2 else 1 }
		{ state: { nodes: nodes.set(id, updated) ?? [], users: $users, user_count, justification_levels, feature_changes, first, last, active, positioned: False, advance_x, advance_y }, operations: attached.operations + stride, stopped: 0, aborted: False }
	}

}

# Tiny original rule inputs; font-level agreement is pinned separately through
# Graphite2 records. These expose immutable snapshots and partial-work state.
machine_test = |code, budget, growth| {
	bytes = [0.U8, 2].concat(code)
	decoded = GraphiteCode.read(bytes, 2, bytes.len(), { classes: 1, attributes: 1, features: 0, users: 3, levels: 0, positioning: False, constraint: False }) ?? crash "original valid opcode fixture"
	sub = { pass_start: 0, pass_end: 0, class_start: 0, class_end: 1, pseudo_start: 0, pseudo_end: 0, substitution: 0, positioning: 0, justification: 0, bidi: 255, flags: 0, direction: 1, pseudo_attribute: 0, break_attribute: 0, direction_attribute: 0, mirror_attribute: 0, skip_attribute: 0, collision_attribute: 0, user_count: 3, justification_start: 0, justification_count: 0, components: 0, line_break: 0, extra_ascent: 0, extra_descent: 0 }
	program = { ..GraphiteSilf.none, data: bytes, classes: [{ start: 0, count: 1, linear: True, max_index: 0 }], instructions: decoded.instructions, protected_inputs: decoded.protected_inputs }
	table = { ..TableGraphite.none, program }
	a = GraphiteSlots.append(GraphiteSlots.make(3, 3), { ..GraphiteSlots.no_slot, glyph: 1, advance_x: TableVar.f32_from_int(601) })
	b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, glyph: 2, before: 1, after: 1, advance_x: TableVar.f32_from_int(602) })
	input = { ids: [a.id, b.id], slots: [GraphiteSlots.get(b.state, a.id), GraphiteSlots.get(b.state, b.id)], users: b.state.users, base: 0, length: 2, start: 0, current: 0 }
	GraphiteMachine.run({ table, sub, defaults: [], rtl: False, reverse: False }, { start: 0, end: decoded.instructions.len(), max_stack: decoded.max_stack, protected_start: 0, protected_end: decoded.protected_inputs.len(), copies: decoded.copies }, b.state, input, { operations: budget, glyphs: growth }, |glyph, metric, _| if (metric == 8) 600 + glyph.to_i32_wrap() else 0)
}

expect {
	a = machine_test([0x1C, 0, 0x1E, 0, 0x19, 0x31], 100, 10)
	!a.aborted and a.stopped == 0 and GraphiteSlots.get(a.state, 1).glyph == 1
}
expect {
	a = machine_test([0x1C, 0, 0x2A, 8, 0, 0, 0x23, 0, 0x19, 0x31], 100, 10)
	s = GraphiteSlots.get(a.state, 1)
	!a.aborted and s.glyph == 2 and GraphiteSlots.integer(s.advance_x) == 601
}
expect {
	a = machine_test([0x1F, 0x1E, 1, 0x19, 0x32], 100, 10)
	!a.aborted and a.state.active == 3 and a.input == 0 and GraphiteSlots.get(a.state, a.state.first).glyph == 1
}
expect {
	a = machine_test([0x20, 0x19, 0x32], 100, 10)
	s = GraphiteSlots.get(a.state, a.state.first)
	!a.aborted and a.cursor == a.state.first and a.state.active == 1 and s.glyph == 2 and s.before == 1 and s.after == 1
}
expect {
	a = machine_test([1, 5, 1, 0, 9, 0x23, 0, 0x32], 100, 10)
	a.aborted and a.stopped == 0 and a.operations == 3
}
expect {
	a = machine_test([0x1F, 0x1C, 0, 0x19, 0x32], 100, 2)
	b = machine_test([1, 17, 0x23, 0, 0x32], 1, 10)
	a.stopped == 1 and a.state.active == 2 and !a.aborted and b.stopped == 2 and GraphiteSlots.integer(GraphiteSlots.get(b.state, 1).advance_x) == 601
}

expect {
	# Accepted fonts can abort only when matching text reaches a stack
	# boundary. Reading must not turn this into a rejected optional table.
	var $code = []
	for _ in 0..<1024 {
		$code = $code.append(1.U8).append(1)
	}
	for _ in 0..<1023 {
		$code = $code.append(6)
	}
	a = machine_test($code.append(0x30), 65536, 10)
	b = machine_test([1, 1, 0x32], 100, 10)
	a.aborted and a.stopped == 0 and a.operations == 1024 and b.aborted and b.stopped == 0
}

expect {
	# Ordinary attributes stay live when the action never replaces that
	# input glyph. A later glyph write protects the initial input instead.
	a = machine_test([1, 17, 0x23, 0, 0x1E, 0, 0x19, 0x31], 1000, 10)
	b = machine_test([1, 17, 0x23, 0, 0x1C, 0, 0x1E, 0, 0x19, 0x31], 1000, 10)
	c = machine_test([0x1C, 0, 1, 17, 0x23, 0, 0x28, 0, 0, 0x23, 21, 0x32], 1000, 10)
	GraphiteSlots.integer(GraphiteSlots.get(a.state, 1).advance_x) == 17 and GraphiteSlots.integer(GraphiteSlots.get(b.state, 1).advance_x) == 601 and GraphiteSlots.integer(GraphiteSlots.get(c.state, 1).shift_y) == 17
}

expect {
	a = machine_test([1, 0, 1, 11, 1, 22, 0x0F, 0x23, 0, 0x32], 1000, 10)
	b = machine_test([1, 1, 1, 11, 1, 22, 0x0F, 0x23, 0, 0x32], 1000, 10)
	GraphiteSlots.integer(GraphiteSlots.get(a.state, 1).advance_x) == 22 and GraphiteSlots.integer(GraphiteSlots.get(b.state, 1).advance_x) == 11
}
