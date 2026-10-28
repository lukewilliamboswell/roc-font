import TableCffBlend
import TableCffNumber

## Type 2's calculator and transient storage. CFF2 does not invoke these
## obsolete operators. Each glyph starts its own deterministic random stream.
TableCffCalc :: {}.{
	State : { args : List(TableCffBlend.Arg), transient : List(F64), written : U32, seed : U32 }
	init : U32 -> State
	init = |seed| { args: [], transient: [], written: 0, seed }
	next_random : U32 -> U32
	next_random = |seed| {
		a = seed.bitwise_xor(seed.shl_wrap(13))
		b = a.bitwise_xor(a.shr_zf_wrap(17))
		b.bitwise_xor(b.shl_wrap(5))
	}
	integer : F64 -> Try(I64, [Bad])
	integer = |v| {
		i = v.to_i64_try() ?? return Err(Bad)
		if i.to_f64() == v {
			Ok(i)
		} else {
			Err(Bad)
		}
	}
	apply : State, U64 -> Try(State, [Bad, OverLimit])
	apply = |state, op| {
		{ args, transient, written, seed } = state
		n = args.len()
		# Caller bounds the stack; arithmetic operands cannot be blended.
		var $args = args
		var $transient = transient
		var $written = written
		var $seed = seed
		unary = op == 261 or op == 265 or op == 270 or op == 274 or op == 282
		binary = op == 259 or op == 260 or op == 266 or op == 267 or op == 268 or op == 271 or op == 280
		if unary or binary {
			needed = if (binary) 2 else 1
			if n < needed {
				return Err(Bad)
			}
			b = $args.get(n - 1) ?? TableCffBlend.arg(0)
			a = if (binary) $args.get(n - 2) ?? TableCffBlend.arg(0) else b
			if a.variable or b.variable {
				return Err(Bad)
			}
			var $v = 0.F64
			if op == 259 {
				$v = if (a.value != 0 and b.value != 0) 1 else 0
			}
			else if op == 260 {
				$v = if (a.value != 0 or b.value != 0) 1 else 0
			}
			else if op == 261 {
				$v = if (b.value == 0) 1 else 0
			}
			else if op == 265 {
				$v = if (b.value < 0) 0 - b.value else b.value
			}
			else if op == 266 {
				$v = a.value + b.value
			}
			else if op == 267 {
				$v = a.value - b.value
			}
			else if op == 268 {
				if b.value == 0 {
					return Err(Bad)
				}
				$v = a.value / b.value
			}
			else if op == 270 {
				$v = 0 - b.value
			}
			else if op == 271 {
				$v = if (a.value == b.value) 1 else 0
			}
			else if op == 280 {
				$v = a.value * b.value
			}
			else if op == 282 {
				if b.value < 0 {
					return Err(Bad)
				}
				$v = b.value.sqrt()
			}
			# drop has no result; all other arithmetic must remain finite.
			if !TableCffNumber.within_limit($v) {
				return Err(OverLimit)
			}
			$args = $args.take_first(n - needed)
			if op != 274 {
				$args = $args.append(TableCffBlend.arg($v))
			}
		} else if op == 276 {
			if n < 2 {
				return Err(Bad)
			}
			index = TableCffCalc.integer(($args.get(n - 1) ?? TableCffBlend.arg(0)).value)?
			if index < 0 or index >= 32 {
				return Err(Bad)
			}
			v = $args.get(n - 2) ?? TableCffBlend.arg(0)
			if v.variable {
				return Err(Bad)
			}
			if $transient.is_empty() {
				$transient = List.repeat(0, 32)
			}
			$transient = $transient.set(index.to_u64_wrap(), v.value) ?? []
			$written = $written.bitwise_or((1.U32).shl_wrap(index.to_u8_wrap()))
			$args = $args.take_first(n - 2)
		} else if op == 277 {
			if n < 1 {
				return Err(Bad)
			}
			index = TableCffCalc.integer(($args.get(n - 1) ?? TableCffBlend.arg(0)).value)?
			if index < 0 or index >= 32 or $written.bitwise_and((1.U32).shl_wrap(index.to_u8_wrap())) == 0 {
				return Err(Bad)
			}
			$args = $args.set(n - 1, TableCffBlend.arg($transient.get(index.to_u64_wrap()) ?? 0)) ?? []
		} else if op == 278 {
			if n < 4 {
				return Err(Bad)
			}
			a = $args.get(n - 4) ?? TableCffBlend.arg(0)
			b = $args.get(n - 3) ?? TableCffBlend.arg(0)
			v1 = $args.get(n - 2) ?? TableCffBlend.arg(0)
			v2 = $args.get(n - 1) ?? TableCffBlend.arg(0)
			$args = $args.take_first(n - 4).append(if (v1.value <= v2.value) a else b)
		} else if op == 279 {
			v = ($seed.bitwise_and(65535).to_u64() + 1).to_f64() / 65536
			$args = $args.append(TableCffBlend.arg(v))
			$seed = TableCffCalc.next_random($seed)
		} else if op == 283 {
			if n < 1 {
				return Err(Bad)
			}
			last = $args.last() ?? TableCffBlend.arg(0)
			$args = $args.append(last)
		} else if op == 284 {
			if n < 2 {
				return Err(Bad)
			}
			a = $args.get(n - 2) ?? TableCffBlend.arg(0)
			b = $args.get(n - 1) ?? TableCffBlend.arg(0)
			$args = $args.set(n - 2, b) ?? []
			$args = $args.set(n - 1, a) ?? []
		} else if op == 285 {
			if n < 2 {
				return Err(Bad)
			}
			index = TableCffCalc.integer(($args.last() ?? TableCffBlend.arg(0)).value)?
			# Type 2 defines clamping for index, unlike subroutine indices.
			clamped = if (index < 0) 0 else if (index.to_u64_wrap() >= n - 1) n - 2 else index.to_u64_wrap()
			selected = $args.get(n - 2 - clamped) ?? TableCffBlend.arg(0)
			$args = $args.set(n - 1, selected) ?? []
		} else if op == 286 {
			if n < 2 {
				return Err(Bad)
			}
			count = TableCffCalc.integer(($args.get(n - 2) ?? TableCffBlend.arg(0)).value)?
			shift = TableCffCalc.integer(($args.last() ?? TableCffBlend.arg(0)).value)?
			if count < 0 or count.to_u64_wrap() > n - 2 {
				return Err(Bad)
			}
			$args = $args.take_first(n - 2)
			if count > 1 {
				length = count.to_u64_wrap()
				rotation = ((shift % count) + count) % count
				# At most 48 operands, no input-sized or recursive permutation.
				for _ in 0..<rotation.to_u64_wrap() {
					last = $args.last() ?? TableCffBlend.arg(0)
					for j in 1..<length {
						value = $args.get(n - 2 - 1 - j) ?? TableCffBlend.arg(0)
						$args = $args.set(n - 2 - j, value) ?? []
					}
					$args = $args.set(n - 2 - length, last) ?? []
				}
			}
		} else {
			return Err(Bad)
		}
		if $args.len() > 48 {
			return Err(OverLimit)
		}
		Ok({ args: $args, transient: $transient, written: $written, seed: $seed })
	}
}

expect {
	state = { ..TableCffCalc.init(987654321), args: [TableCffBlend.arg(7), TableCffBlend.arg(2)] }
	match TableCffCalc.apply(state, 268) {
		Ok(result) => result.args.map(|a| a.value) == [3.5]
		Err(_) => False
	}
}
expect {
	state = { ..TableCffCalc.init(1), args: [1, 2, 3, 3, 1].map(TableCffBlend.arg) }
	match TableCffCalc.apply(state, 286) {
		Ok(result) => result.args.map(|a| a.value) == [3, 1, 2]
		Err(_) => False
	}
}
expect TableCffCalc.next_random(1) == 270369
expect {
	match TableCffCalc.apply(TableCffCalc.init(1), 279) {
		Ok(result) => result.seed == 270369 and result.args.map(|a| a.value) == [2.F64 / 65536]
		Err(_) => False
	}
}
