## Original integer operations for the documented Graphite stack machine.
## Widening before arithmetic makes signed wrap explicit on every platform.
GraphiteArithmetic :: {}.{
	unary : U64, I32 -> I32
	unary = |op, value| match op {
		0x0C => (0.I64 - value.to_i64()).to_i32_wrap()
		0x0D => value.bitwise_and(255)
		0x0E => value.to_i16_wrap().to_i32()
		0x12 => if (value == 0) 1 else 0
		0x40 => value.bitwise_xor(-1)
		_ => crash "validated Graphite unary opcode"
	}

	binary : U64, I32, I32 -> Try(I32, [DivideZero])
	binary = |op, left, right| Ok(
		match op {
			0x06 => (left.to_i64() + right.to_i64()).to_i32_wrap()
			0x07 => (left.to_i64() - right.to_i64()).to_i32_wrap()
			0x08 => (left.to_i64() * right.to_i64()).to_i32_wrap()
			0x09 => {
				if right == 0 {
					return Err(DivideZero)
				}
				a = if (left < 0) 0.I64 - left.to_i64() else left.to_i64()
				b = if (right < 0) 0.I64 - right.to_i64() else right.to_i64()
				q = a // b
				(if ((left < 0) != (right < 0)) 0 - q else q).to_i32_wrap()
			}
			0x0A => left.min(right)
			0x0B => left.max(right)
			0x10 => if (left != 0 and right != 0) 1 else 0
			0x11 => if (left != 0 or right != 0) 1 else 0
			0x13 => if (left == right) 1 else 0
			0x14 => if (left != right) 1 else 0
			0x15 => if (left < right) 1 else 0
			0x16 => if (left > right) 1 else 0
			0x17 => if (left <= right) 1 else 0
			0x18 => if (left >= right) 1 else 0
			0x3E => left.bitwise_and(right)
			0x3F => left.bitwise_or(right)
			_ => crash "validated Graphite binary opcode"
		},
	)
}

expect GraphiteArithmetic.binary(6, 2147483647, 1) == Ok(-2147483648) and GraphiteArithmetic.binary(7, -2147483648, 1) == Ok(2147483647) and GraphiteArithmetic.binary(8, 65536, 65536) == Ok(0)
expect GraphiteArithmetic.unary(0x0C, -2147483648) == -2147483648 and GraphiteArithmetic.unary(0x0D, -1) == 255 and GraphiteArithmetic.unary(0x0E, 65535) == -1
expect {
	var $ok = True
	for a in -17.I32..<18 {
		for b in -9.I32..<10 {
			if b == 0 {
				$ok = $ok and GraphiteArithmetic.binary(9, a, b) == Err(DivideZero)
			} else {
				q = match GraphiteArithmetic.binary(9, a, b) {
					Ok(v) => v
					Err(_) => 1000
				}
				r = a - q * b
				$ok = $ok and r.abs() < b.abs() and (r == 0 or (r < 0) == (a < 0))
			}
		}
	}
	$ok
}
