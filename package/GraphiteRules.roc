import Bytes
import Sorted
import GraphiteSilf
import GraphiteCode
import TableGraphite
import TableVar
import GraphitePass
import GraphiteMachine
import GraphiteSlots

## Original finite-state rule scheduler from the Graphite table format.
## Candidates sort by descending documented rule length, then source index.
GraphiteRules :: {}.{
	Result : { state : GraphiteSlots, operations : U64, stopped : U64, aborted : Bool }

	apply : GraphiteMachine.Context, GraphitePass.Pass, GraphiteSlots, GraphiteMachine.Limits, (U64, U64, I32 -> I32) -> Result
	apply = |ctx, pass, state, limits, metric| {
		var $state = state
		var $operations = 0
		var $cursor = GraphiteMachine.initial(state, ctx.reverse)
		var $highwater = $cursor
		var $loops = 0
		var $first = True
		bytes = ctx.table.program.data
		while $cursor != 0 {
			if $operations >= limits.operations {
				return { state: $state, operations: $operations, stopped: 2, aborted: False }
			}
			$operations = $operations + 1
			var $begin = $cursor
			var $pre = 0
			while $pre < pass.max_pre {
				previous = GraphiteMachine.backward($state, $begin, ctx.reverse)
				if previous == 0 {
					break
				}
				$begin = previous
				$pre = $pre + 1
			}
			var $ids = List.with_capacity(pass.max_context)
			var $slots = List.with_capacity(pass.max_context)
			var $at = $begin
			while $at != 0 and $ids.len() < pass.max_context {
				s = GraphiteSlots.get($state, $at)
				$ids = $ids.append($at)
				$slots = $slots.append(s)
				$at = GraphiteMachine.forward($state, $at, ctx.reverse)
			}
			input = { ids: $ids, slots: $slots, users: [], base: 0, length: $ids.len(), start: $pre.to_i64_wrap(), current: $pre.to_i64_wrap() }
			if $first {
				$first = False
				program = ctx.table.program.programs.get(pass.programs) ?? crash "prepared pass constraint"
				if program.start != program.end {
					condition = GraphiteMachine.run(ctx, program, $state, input, { ..limits, operations: limits.operations - $operations }, metric)
					$operations = $operations + condition.operations
					if condition.aborted or condition.stopped != 0 {
						return { state: condition.state, operations: $operations, stopped: condition.stopped, aborted: condition.aborted }
					}
					if condition.value == 0 {
						return { state: $state, operations: $operations, stopped: 0, aborted: False }
					}
				}
			}
			var $candidates = []
			if $pre >= pass.min_pre and pass.rows != 0 {
				var $row = Bytes.u16(bytes, pass.starts + 2 * (pass.max_pre - $pre))
				for s in input.slots {
					if $operations >= limits.operations {
						return { state: $state, operations: $operations, stopped: 2, aborted: False }
					}
					$operations = $operations + 1
					column = match GraphitePass.column(bytes, pass, s.glyph) {
						Found(value) => value
						Missing => break
					}
					$row = GraphitePass.transition(bytes, pass, $row, column)
					if $row == 0 {
						break
					}
					rules = GraphitePass.rules(bytes, pass, $row)
					for index in rules.start..<rules.end {
						if $operations >= limits.operations {
							return { state: $state, operations: $operations, stopped: 2, aborted: False }
						}
						$operations = $operations + 1
						rule = Bytes.u16(bytes, pass.rule_map + 2 * index)
						key = Bytes.u16(bytes, pass.sort_keys + 2 * rule)
						$candidates = $candidates.append((65535 - key).shl_wrap(16).bitwise_or(rule))
					}
					if $row >= pass.transitional {
						break
					}
				}
			}
			var $applied = False
			for candidate in Sorted.unique($candidates) {
				rule = candidate.bitwise_and(65535)
				pre = Bytes.u8(bytes, pass.pre_contexts + rule)
				length = Bytes.u16(bytes, pass.sort_keys + 2 * rule)
				if pre <= $pre and length >= pre and $pre - pre + length <= input.slots.len() {
					rule_input = { ..input, base: ($pre - pre).to_i64_wrap(), length }
					condition = ctx.table.program.programs.get(pass.programs + 1 + 2 * rule) ?? crash "prepared rule constraint"
					var $matches = True
					if condition.start != condition.end {
						for i in ($pre - pre)..<($pre - pre + length) {
							checked = GraphiteMachine.run(ctx, condition, $state, { ..rule_input, current: i.to_i64_wrap() }, { ..limits, operations: limits.operations - $operations }, metric)
							$operations = $operations + checked.operations
							if checked.aborted or checked.stopped != 0 {
								return { state: checked.state, operations: $operations, stopped: checked.stopped, aborted: checked.aborted }
							}
							if checked.value == 0 {
								$matches = False
								break
							}
						}
					}
					if $matches {
						action = ctx.table.program.programs.get(pass.programs + 2 + 2 * rule) ?? crash "prepared rule action"
						changed = GraphiteMachine.run(ctx, action, $state, rule_input, { ..limits, operations: limits.operations - $operations }, metric)
						$operations = $operations + changed.operations
						$state = changed.state
						if changed.aborted or changed.stopped != 0 {
							return { state: $state, operations: $operations, stopped: changed.stopped, aborted: changed.aborted }
						}
						var $next = changed.cursor
						var $move = changed.value.to_i64()
						if $next == 0 and changed.input < input.slots.len().to_i64_wrap() {
							$next = GraphiteMachine.initial($state, ctx.reverse)
						}
						while $move > 0 and $next != 0 {
							if $operations >= limits.operations {
								return { state: $state, operations: $operations, stopped: 2, aborted: False }
							}
							$operations = $operations + 1
							$next = GraphiteMachine.forward($state, $next, ctx.reverse)
							$move = $move - 1
						}
						while $move < 0 {
							if $operations >= limits.operations {
								return { state: $state, operations: $operations, stopped: 2, aborted: False }
							}
							$operations = $operations + 1
							$next = if ($next == 0) GraphiteMachine.initial($state, !ctx.reverse) else GraphiteMachine.backward($state, $next, ctx.reverse)
							$move = $move + 1
							if $next == 0 {
								$next = GraphiteMachine.initial($state, ctx.reverse)
								break
							}
						}
						var $high_index = 0
						var $next_index = 0
						for i in 0..<input.ids.len() {
							id = input.ids.get(i) ?? 0
							if id == $highwater {
								$high_index = i + 1
							}
							if id == $next {
								$next_index = i + 1
							}
						}
						var $advanced = $next == 0
						if $next != 0 {
							if $next_index != 0 and $high_index != 0 {
								$advanced = $next_index > $high_index
							} else {
								order = GraphiteRules.ahead($state, $highwater, $next, ctx.reverse, limits.operations - $operations)
								$operations = $operations + order.operations
								if order.stopped {
									return { state: $state, operations: $operations, stopped: 2, aborted: False }
								}
								$advanced = order.ahead
							}
						}
						if $advanced {
							$loops = 0
							$highwater = $next
						} else {
							$loops = $loops + 1
							if $loops >= pass.max_loop.max(1) {
								$next = GraphiteMachine.forward($state, $highwater, ctx.reverse)
								$highwater = $next
								$loops = 0
							}
						}
						$cursor = $next
						$applied = True
						break
					}
				}
			}
			if !$applied {
				old = $cursor
				$cursor = GraphiteMachine.forward($state, $cursor, ctx.reverse)
				if old == $highwater {
					$highwater = $cursor
					$loops = 0
				}
			}
		}
		{ state: $state, operations: $operations, stopped: 0, aborted: False }
	}

	# A returned cursor can lie beyond the checked rule window. Stable IDs
	# are not output positions after insertion, so compare active order.
	# Search both ways to keep ordinary short backtracking local; every
	# visited link is charged, and retained deleted nodes keep their links.
	ahead : GraphiteSlots, U64, U64, Bool, U64 -> { ahead : Bool, operations : U64, stopped : Bool }
	ahead = |state, from, to, reverse, budget| {
		if from == to {
			return { ahead: False, operations: 0, stopped: False }
		}
		if to == 0 {
			return { ahead: True, operations: 0, stopped: False }
		}
		var $forward = from
		var $backward = from
		var $operations = 0
		var $walked = 0
		while ($forward != 0 or $backward != 0) and $walked < state.nodes.len() {
			$walked = $walked + 1
			if $forward != 0 {
				if $operations >= budget {
					return { ahead: False, operations: $operations, stopped: True }
				}
				$operations = $operations + 1
				$forward = GraphiteMachine.forward(state, $forward, reverse)
				if $forward == to {
					return { ahead: True, operations: $operations, stopped: False }
				}
			}
			if $backward != 0 {
				if $operations >= budget {
					return { ahead: False, operations: $operations, stopped: True }
				}
				$operations = $operations + 1
				$backward = GraphiteMachine.backward(state, $backward, reverse)
				if $backward == to {
					return { ahead: False, operations: $operations, stopped: False }
				}
			}
		}
		{ ahead: False, operations: $operations, stopped: False }
	}

}

rules_silf = [0, 3, 0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 0, 0, 16, 0, 3, 0, 0, 0, 42, 0, 50, 0, 2, 0, 0, 0, 0, 1, 0, 1, 1, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 68, 0, 0, 0, 145, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 8, 0, 10, 0, 2, 0, 10, 1, 0, 0, 1, 0, 24, 0, 0, 0, 141, 0, 0, 0, 141, 0, 0, 0, 141, 0, 0, 0, 0, 0, 2, 0, 1, 0, 1, 0, 1, 0, 1, 0, 6, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 1, 0, 28, 0, 25, 49]

rules_test = |action, glyphs| {
	original = GraphiteSilf.read(rules_silf, 3, 1, 0, 4096) ?? crash "original valid rule packet"
	decoded = GraphiteCode.read(action, 0, action.len(), { classes: 1, attributes: 1, features: 0, users: 0, levels: 0, positioning: False, constraint: False }) ?? crash "original action packet"
	program = { ..original, instructions: decoded.instructions, protected_inputs: decoded.protected_inputs, programs: [{ start: 0, end: 0, max_stack: 0, protected_start: 0, protected_end: 0, copies: False }, { start: 0, end: 0, max_stack: 0, protected_start: 0, protected_end: 0, copies: False }, { start: 0, end: decoded.instructions.len(), max_stack: decoded.max_stack, protected_start: 0, protected_end: decoded.protected_inputs.len(), copies: decoded.copies }] }
	table = { ..TableGraphite.none, program, glyph_count: 3, real_glyph_count: 3 }
	sub = program.subtables.first() ?? crash "original subtable"
	pass = program.passes.first() ?? crash "original pass"
	var $state = GraphiteSlots.make(0, glyphs.len())
	for i in 0..<glyphs.len() {
		glyph = glyphs.get(i) ?? 0
		a = GraphiteSlots.append($state, { ..GraphiteSlots.no_slot, glyph, before: i.to_i64_wrap(), after: i.to_i64_wrap(), original: i.to_i64_wrap(), advance_x: TableVar.f32_from_int(600 + glyph.to_i64_wrap()) })
		$state = a.state
	}
	GraphiteRules.apply({ table, sub, defaults: [], rtl: False, reverse: False }, pass, $state, { operations: 65536, glyphs: 65536 }, |glyph, metric, _| if (metric == 8) 600 + glyph.to_i32_wrap() else 0)
}

expect {
	a = rules_test([0x1C.U8, 0, 0x19, 0x31], [1, 2, 1])
	!a.aborted and a.stopped == 0 and a.state.nodes.drop_first(1).map(|s| s.glyph) == [2, 2, 2]
}
expect {
	a = rules_test([1.U8, 1, 0x24, 0, 0x31], [1, 1])
	!a.aborted and a.stopped == 0 and a.state.nodes.drop_first(1).map(|s| GraphiteSlots.integer(s.advance_x)) == [611, 611]
}
expect {
	a = rules_test([0x20.U8, 0x31], [1, 1, 2])
	s = GraphiteSlots.get(a.state, a.state.first)
	!a.aborted and a.stopped == 0 and a.state.active == 1 and s.glyph == 2 and s.before == 2 and s.after == 2
}
expect {
	a = rules_test([0x1F.U8, 0x1C, 0, 0x19, 0x32], [1, 2])
	!a.aborted and a.stopped == 0 and a.state.active == 3 and GraphiteSlots.get(a.state, a.state.first).glyph == 2
}

## fuzz regression: successful rules returning just beyond their one-slot
## window advance the high-water mark. They must not rewind after maxLoop.
expect {
	var $ok = True
	for count in [16.U64, 64, 256] {
		a = rules_test([1.U8, 1, 0x24, 0, 0x32], List.repeat(1, count))
		$ok = $ok and !a.aborted and a.stopped == 0 and a.operations <= 32 * count and a.state.nodes.drop_first(1).all(|s| GraphiteSlots.integer(s.advance_x) == 602)
	}
	$ok
}
