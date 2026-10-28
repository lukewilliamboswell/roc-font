import Bytes

## Original decoder for the documented Graphite stack language. Prepared
## instructions and associations are scalar records over shared table bytes.
## Forward ContextItem branches are checked at instruction boundaries and
## both paths must have compatible stack depths.
GraphiteCode :: {}.{

	Environment : { classes : U64, attributes : U64, features : U64, users : U64, constraint : Bool }
	Instruction : { opcode : U64, a : I32, b : I32, c : I32, at : U64, end : U64, target : U64 }
	Program : { instructions : List(Instruction), max_stack : U64 }

	read : List(U8), U64, U64, Environment -> Try(Program, [Bad(U64)])
	read = |bytes, start, end, env| {
		if end > bytes.len() or end < start {
			return Err(Bad(start))
		}
		var $ops = List.with_capacity((end - start).min(64))
		var $at = start
		while $at < end {
			op = Bytes.u8(bytes, $at)
			if op > 0x42 or op == 0x1A or op == 0x2F or op == 0x39 or op == 0x3A {
				return Err(Bad($at))
			}
			if env.constraint and GraphiteCode.mutates(op) {
				return Err(Bad($at))
			}
			width = GraphiteCode.width(op)
			if !Bytes.fits($at + 1, width, end) {
				return Err(Bad($at))
			}
			var $a = 0.I32
			var $b = 0.I32
			var $c = 0.I32
			var $next = $at + 1 + width
			var $target = 0
			if op == 1 {
				$a = GraphiteCode.i8(bytes, $at + 1)
			}
			else if op == 2 or op == 0x1C or (op >= 0x23 and op <= 0x27) or op == 0x28 or op == 0x29 or op == 0x2A or op == 0x2B or op == 0x2C or op == 0x2D or op == 0x2E or (op >= 0x33 and op <= 0x36) or op == 0x42 {
				$a = Bytes.u8(bytes, $at + 1).to_i32_wrap()
			}
			else if op == 3 {
				$a = Bytes.i16(bytes, $at + 1).to_i32_wrap()
			}
			else if op == 4 or op == 0x3B or op == 0x3C or op == 0x3D {
				$a = Bytes.u16(bytes, $at + 1).to_i32_wrap()
			}
			else if op == 5 {
				$a = Bytes.u32(bytes, $at + 1).to_i32_wrap()
			}
			else if op == 0x1D or op == 0x1E or op == 0x22 or op == 0x38 {
				$a = GraphiteCode.i8(bytes, $at + 1)
			}
			else if op == 0x41 {
				$a = Bytes.i16(bytes, $at + 1).to_i32_wrap()
			}
			if op == 0x1D {
				$b = Bytes.u8(bytes, $at + 2).to_i32_wrap()
				$c = Bytes.u8(bytes, $at + 3).to_i32_wrap()
			}
			else if op == 0x38 {
				$b = Bytes.u16(bytes, $at + 2).to_i32_wrap()
				$c = Bytes.u16(bytes, $at + 4).to_i32_wrap()
			}
			else if op == 0x27 or (op >= 0x33 and op <= 0x35) {
				$b = Bytes.u8(bytes, $at + 2).to_i32_wrap()
			}
			else if (op >= 0x28 and op <= 0x2E) or op == 0x42 {
				$b = GraphiteCode.i8(bytes, $at + 2)
			}
			else if op == 0x3C or op == 0x3D {
				$b = GraphiteCode.i8(bytes, $at + 3)
			}
			else if op == 0x41 {
				$b = Bytes.i16(bytes, $at + 3).to_i32_wrap()
			}
			if op == 0x2A or op == 0x2D {
				$c = GraphiteCode.i8(bytes, $at + 3)
			}
			else if op == 0x2E {
				$c = Bytes.u8(bytes, $at + 3).to_i32_wrap()
			}
			if op == 0x21 {
				$a = Bytes.u8(bytes, $at + 1).to_i32_wrap()
				if !Bytes.fits($next, $a.to_u64_wrap(), end) {
					return Err(Bad($at))
				}
				$next = $next + $a.to_u64_wrap()
			}
			if op == 0x22 {
				$b = Bytes.u8(bytes, $at + 2).to_i32_wrap()
				$target = $next + $b.to_u64_wrap()
				if $target > end {
					return Err(Bad($at))
				}
			}
			if (op == 0x1C or op == 0x3B) and $a.to_u64_wrap() >= env.classes {
				return Err(Bad($at))
			}
			if (op == 0x1D or op == 0x38) and ($b.to_u64_wrap() >= env.classes or $c.to_u64_wrap() >= env.classes) {
				return Err(Bad($at))
			}
			if (op == 0x29 or op == 0x2C or op == 0x3C or op == 0x3D) and $a.to_u64_wrap() >= env.attributes {
				return Err(Bad($at))
			}
			if (op == 0x2B or op == 0x42) and $a.to_u64_wrap() >= env.features {
				return Err(Bad($at))
			}
			if (op == 0x2A or op == 0x2D) and ($a < 0 or $a > 11) {
				return Err(Bad($at))
			}
			if GraphiteCode.slot_attribute(op) and ($a < 0 or $a >= 78) {
				return Err(Bad($at))
			}
			if ((op >= 0x33 and op <= 0x35) or op == 0x27) and $a == 55 and $b.to_u64_wrap() >= env.users {
				return Err(Bad($at))
			}
			if op == 0x2E and $a == 55 and $c.to_u64_wrap() >= env.users {
				return Err(Bad($at))
			}
			$ops = $ops.append({ opcode: op, a: $a, b: $b, c: $c, at: $at, end: $next, target: $target })
			$at = $next
		}
		# The decoder has proved all byte widths before allocating the flow
		# arrays. The only code jump is forward; no fixed-point iteration.
		count = $ops.len()
		var $depths = List.repeat(-1.I64, count + 1)
		$depths = $depths.set(0, 0) ?? []
		var $maximum = 0.U64
		for i in 0..<count {
			instruction = $ops.get(i) ?? GraphiteCode.no_instruction
			var $instruction = instruction
			if instruction.opcode == 0x22 {
				var $lo = i + 1
				var $hi = count
				while $lo < $hi {
					mid = $lo + ($hi - $lo) // 2
					if ($ops.get(mid) ?? GraphiteCode.no_instruction).at < instruction.target {
						$lo = mid + 1
					} else {
						$hi = mid
					}
				}
				if ($lo == count and instruction.target != end) or ($lo < count and ($ops.get($lo) ?? GraphiteCode.no_instruction).at != instruction.target) {
					return Err(Bad(instruction.at))
				}
				$instruction = { ..instruction, target: $lo }
				$ops = $ops.set(i, $instruction) ?? []
			}
			depth = $depths.get(i) ?? -1
			if depth >= 0 {
				effect = GraphiteCode.effect(instruction.opcode)
				if depth < effect.pop {
					return Err(Bad(instruction.at))
				}
				next_depth = depth - effect.pop + effect.push
				$maximum = $maximum.max(next_depth.to_u64_wrap())
				if $maximum > 1024 {
					return Err(Bad(instruction.at))
				}
				if instruction.opcode == 0x22 {
					$depths = GraphiteCode.flow($depths, $instruction.target, depth + 1, instruction.at)?
				}
				if instruction.opcode < 0x30 or instruction.opcode > 0x32 {
					$depths = GraphiteCode.flow($depths, i + 1, next_depth, instruction.at)?
				}
			}
		}
		if count != 0 and ($depths.get(count) ?? -1) >= 0 {
			return Err(Bad(end))
		}
		Ok({ instructions: $ops, max_stack: $maximum })
	}

	# In an action INSERT shifts the immutable input cursor back; NEXT
	# shifts it forward. References must name an actual matched input slot,
	# including when a newly inserted output slot is current.
	check_references : List(U8), Program, U64, U64 -> Try({}, [Bad(U64)])
	check_references = |bytes, program, pre_context, length| {
		if pre_context >= length and !program.instructions.is_empty() {
			return Err(Bad((program.instructions.first() ?? GraphiteCode.no_instruction).at))
		}
		var $cursor = pre_context.to_i64_wrap()
		for instruction in program.instructions {
			op = instruction.opcode
			if op == 0x1F {
				$cursor = $cursor - 1
			}
			else if op == 0x19 or op == 0x1B {
				$cursor = $cursor + 1
			}
			else if op == 0x1D or op == 0x1E or op == 0x38 {
				position = $cursor + instruction.a.to_i64()
				if position < 0 or position >= length.to_i64_wrap() {
					return Err(Bad(instruction.at))
				}
			} else if (op >= 0x28 and op <= 0x2E) or op == 0x3C or op == 0x3D or op == 0x42 {
				position = $cursor + instruction.b.to_i64()
				if position < 0 or position >= length.to_i64_wrap() {
					return Err(Bad(instruction.at))
				}
			} else if op == 0x21 {
				for i in 0..<instruction.a.to_u64_wrap() {
					position = $cursor + GraphiteCode.i8(bytes, instruction.at + 2 + i).to_i64()
					if position < 0 or position >= length.to_i64_wrap() {
						return Err(Bad(instruction.at))
					}
				}
			}
		}
		Ok({})
	}

	no_instruction : Instruction
	no_instruction = { opcode: 0, a: 0, b: 0, c: 0, at: 0, end: 0, target: 0 }

	flow : List(I64), U64, I64, U64 -> Try(List(I64), [Bad(U64)])
	flow = |depths, index, depth, at| {
		current = depths.get(index) ?? return Err(Bad(at))
		if current >= 0 and current != depth {
			return Err(Bad(at))
		}
		Ok(depths.set(index, depth) ?? [])
	}

	i8 : List(U8), U64 -> I32
	i8 = |bytes, at| {
		value = Bytes.u8(bytes, at).to_i32_wrap()
		if (value >= 128) value - 256 else value
	}

	width : U64 -> U64
	width = |op|
		if op == 1 or op == 2 or op == 0x1C or op == 0x1E or op == 0x21 or (op >= 0x23 and op <= 0x26) or op == 0x36 {
			1
		}
		else if op == 3 or op == 4 or op == 0x22 or op == 0x27 or op == 0x28 or op == 0x29 or op == 0x2B or op == 0x2C or (op >= 0x33 and op <= 0x35) or op == 0x3B or op == 0x42 {
			2
		}
		else if op == 0x1D or op == 0x2A or op == 0x2D or op == 0x2E or op == 0x3C or op == 0x3D {
			3
		}
		else if op == 5 or op == 0x41 {
			4
		}
		else if op == 0x38 {
			5
		}
		else {
			0
		}

	mutates : U64 -> Bool
	mutates = |op| (op >= 0x19 and op <= 0x21) or (op >= 0x23 and op <= 0x27) or (op >= 0x33 and op <= 0x35) or op == 0x38 or op == 0x3B or op == 0x42

	slot_attribute : U64 -> Bool
	slot_attribute = |op| (op >= 0x23 and op <= 0x28) or op == 0x2E or (op >= 0x33 and op <= 0x35)

	effect : U64 -> { pop : I64, push : I64 }
	effect = |op|
		if (op >= 1 and op <= 5) or (op >= 0x28 and op <= 0x2E) or op == 0x36 or op == 0x37 or op == 0x3C or op == 0x3D {
			{ pop: 0, push: 1 }
		}
		else if (op >= 6 and op <= 0x0B) or op == 0x10 or op == 0x11 or (op >= 0x13 and op <= 0x18) or op == 0x3E or op == 0x3F {
			{ pop: 2, push: 1 }
		}
		else if op == 0x0C or op == 0x0D or op == 0x0E or op == 0x12 or op == 0x40 or op == 0x41 {
			{ pop: 1, push: 1 }
		}
		else if op == 0x0F {
			{ pop: 3, push: 1 }
		}
		else if (op >= 0x23 and op <= 0x27) or op == 0x30 or (op >= 0x33 and op <= 0x35) or op == 0x42 {
			{ pop: 1, push: 0 }
		}
		else {
			{ pop: 0, push: 0 }
		}
}

environment = { classes: 1, attributes: 1, features: 1, users: 0, constraint: False }
expect GraphiteCode.read([1, 5, 0x2B, 0, 0, 9, 0x23, 0, 0x32], 0, 9, environment).is_ok()
expect GraphiteCode.read([6, 0x32], 0, 2, environment).is_err()
expect GraphiteCode.read([0x3B, 0, 1, 0x32], 0, 4, environment).is_err()
expect GraphiteCode.read([5, 0, 0], 0, 3, environment).is_err()
expect GraphiteCode.read([0x39, 0x32], 0, 2, environment).is_err()
expect GraphiteCode.read([0x22, 0, 2, 1, 1, 0x30], 0, 6, { ..environment, constraint: True }).is_ok()
expect GraphiteCode.read([0x22, 0, 1, 1, 1, 0x30], 0, 6, { ..environment, constraint: True }).is_err()

expect {
	# The inserted output precedes input slot zero. Offset one names the
	# original input; offset zero names no input and must fail at reading.
	good = [0x1F.U8, 0x1E, 1, 0x19, 0x32]
	bad = [0x1F.U8, 0x1E, 0, 0x19, 0x32]
	env = { classes: 0, attributes: 0, features: 0, users: 0, constraint: False }
	a = GraphiteCode.read(good, 0, good.len(), env) ?? crash "original stack-valid fixture"
	b = GraphiteCode.read(bad, 0, bad.len(), env) ?? crash "original stack-valid fixture"
	GraphiteCode.check_references(good, a, 0, 1).is_ok() and GraphiteCode.check_references(bad, b, 0, 1).is_err()
}
