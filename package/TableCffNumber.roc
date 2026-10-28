import Bytes

## CFF DICT and Type2 number decoding. The bounded decimal spelling is
## converted once during preparation; charstrings use exact integers or
## signed16.16 values. No host locale or textual font names are involved.
TableCffNumber :: {}.{
	limit : F64
	limit = 1267650600228229401496703205376.F64
	within_limit : F64 -> Bool
	within_limit = |v| v >= 0 - TableCffNumber.limit and v <= TableCffNumber.limit

	is_number : U64, Bool -> Bool
	is_number = |byte, dict| byte == 28 or byte >= 32 or (dict and (byte == 29 or byte == 30))

	read : List(U8), U64, U64, Bool -> Try({ value : F64, next : U64 }, [Bad(U64), OverLimit])
	read = |data, at, end, dict| {
		if at >= end or end > data.len() {
			return Err(Bad(at))
		}
		b = Bytes.u8(data, at)
		if b >= 32 and b <= 246 {
			Ok({ value: b.to_i64_wrap().to_f64() - 139, next: at + 1 })
		} else if b >= 247 and b <= 254 {
			if end - at < 2 {
				return Err(Bad(at))
			}
			n = (b - (if (b <= 250) 247 else 251)) * 256 + Bytes.u8(data, at + 1) + 108
			Ok({ value: if (b <= 250) n.to_f64() else 0 - n.to_f64(), next: at + 2 })
		} else if b == 28 {
			if end - at < 3 {
				return Err(Bad(at))
			}
			Ok({ value: Bytes.i16(data, at + 1).to_f64(), next: at + 3 })
		} else if (dict and b == 29) or (!dict and b == 255) {
			if end - at < 5 {
				return Err(Bad(at))
			}
			n = Bytes.u32(data, at + 1).to_i64_wrap()
			signed = if (n >= 2147483648) n - 4294967296 else n
			Ok({ value: if (dict) signed.to_f64() else signed.to_f64() / 65536, next: at + 5 })
		} else if dict and b == 30 {
			TableCffNumber.decimal(data, at, end)
		} else {
			Err(Bad(at))
		}
	}

	decimal : List(U8), U64, U64 -> Try({ value : F64, next : U64 }, [Bad(U64), OverLimit])
	decimal = |data, at, end| {
		var $text = []
		var $cursor = at + 1
		var $done = False
		while $cursor < end and !$done {
			byte = Bytes.u8(data, $cursor)
			$cursor = $cursor + 1
			for shift in [4.U8, 0] {
				if !$done {
					nibble = byte.shr_zf_wrap(shift).bitwise_and(15)
					if nibble == 15 {
						$done = True
					} else if nibble <= 9 {
						$text = $text.append((48 + nibble).to_u8_wrap())
					} else if nibble == 10 {
						$text = $text.append(46)
					} else if nibble == 11 {
						$text = $text.append(101)
					} else if nibble == 12 {
						$text = $text.append(101).append(45)
					} else if nibble == 14 {
						$text = $text.append(45)
					} else {
						return Err(Bad($cursor - 1))
					}
					if $text.len() > 512 {
						return Err(OverLimit)
					}
				}
			}
		}
		if !$done or $text.is_empty() {
			return Err(Bad(at))
		}
		match F64.from_str(Str.from_utf8_lossy($text)) {
			Ok(v) => if TableCffNumber.within_limit(v) {
				Ok({ value: v, next: $cursor })
			} else {
				Err(OverLimit)
			}
			Err(_) => Err(Bad(at))
		}
	}

	## Outward envelope for addition of bounded CFF2 values. The factor is
	## 1+2^-50, leaving slack for bound and coordinate rounding; addition covers
	## zero/subnormal cases without changing ordinary font-unit envelopes.
	add_bound : F64, F64 -> F64
	add_bound = |a, b| (a + b) * 1.0000000000000009 + 0.000000000000000000000000000001
}

expect TableCffNumber.read([32], 0, 1, False) == Ok({ value: -107, next: 1 })
expect TableCffNumber.read([254, 255], 0, 2, False) == Ok({ value: -1131, next: 2 })
expect TableCffNumber.read([255, 255, 255, 128, 0], 0, 5, False) == Ok({ value: -0.5, next: 5 })
expect TableCffNumber.read([30, 0x0A, 0x00, 0x1F], 0, 4, True) == Ok({ value: 0.001, next: 4 })
expect TableCffNumber.read([30, 0x1C, 0x3F], 0, 3, True) == Ok({ value: 0.001, next: 3 })
expect TableCffNumber.read([30, 0x1D, 0xFF], 0, 3, True) == Err(Bad(1))
expect TableCffNumber.read([255], 0, 1, True) == Err(Bad(0))
