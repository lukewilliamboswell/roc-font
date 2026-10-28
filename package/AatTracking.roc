import Bytes
import TableVar

## Apple tracking in font units. The font's normal track is interpolated
## at a point size; scaling and rounding to pixels remain the caller's job.
AatTracking := { bytes : List(U8), horizontal : U64, vertical : U64 }.{
	none : AatTracking
	none = { bytes: [], horizontal: 0, vertical: 0 }

	read : List(U8) -> Try(AatTracking, [Bad(U64)])
	read = |bytes| {
		if bytes.len() < 12 or Bytes.u16(bytes, 0) != 1 or Bytes.u16(bytes, 4) != 0 {
			return Err(Bad(0))
		}
		for at in [Bytes.u16(bytes, 6), Bytes.u16(bytes, 8)] {
			if at != 0 {
				if !Bytes.fits(at, 8, bytes.len()) {
					return Err(Bad(at))
				}
				tracks = Bytes.u16(bytes, at)
				sizes = Bytes.u16(bytes, at + 2)
				size_at = Bytes.u32(bytes, at + 4)
				if !Bytes.fits(at + 8, tracks * 8, bytes.len()) or !Bytes.fits(size_at, sizes * 4, bytes.len()) {
					return Err(Bad(at))
				}
				var $previous_size = -2147483649
				for i in 0..<sizes {
					value = AatTracking.fixed(bytes, size_at + i * 4)
					if value < $previous_size {
						return Err(Bad(size_at + i * 4))
					}
					$previous_size = value
				}
				var $previous_track = -2147483649
				for i in 0..<tracks {
					entry = at + 8 + i * 8
					value = AatTracking.fixed(bytes, entry)
					if value <= $previous_track {
						return Err(Bad(entry))
					}
					$previous_track = value
					if !Bytes.fits(Bytes.u16(bytes, entry + 6), sizes * 2, bytes.len()) {
						return Err(Bad(entry + 6))
					}
				}
			}
		}
		Ok({ bytes, horizontal: Bytes.u16(bytes, 6), vertical: Bytes.u16(bytes, 8) })
	}

	fixed : List(U8), U64 -> I64
	fixed = |bytes, at| Bytes.u32(bytes, at).to_i32_wrap().to_i64()
	float : List(U8), U64 -> U32
	float = |bytes, at| TableVar.f32_from_ratio(AatTracking.fixed(bytes, at).to_i128(), 65536)

	value : AatTracking, Bool, Dec -> I64
	value = |table, vertical, size| {
		at = if (vertical) table.vertical else table.horizontal
		if at == 0 {
			return 0
		}
		count = Bytes.u16(table.bytes, at)
		if count == 0 {
			return 0
		}
		ptem = TableVar.f32_from_ratio(Dec.to_attos(if (size > 0) size else 12), 1_000_000_000_000_000_000)
		var $low = 0
		var $high = count - 1
		while $low + 1 < count and !TableVar.f32_lt(0, AatTracking.float(table.bytes, at + 8 + ($low + 1) * 8)) {
			$low = $low + 1
		}
		while $high > 0 and !TableVar.f32_lt(AatTracking.float(table.bytes, at + 8 + ($high - 1) * 8), 0) {
			$high = $high - 1
		}
		a = AatTracking.at_size(table.bytes, at, $low, ptem)
		if $low == $high {
			return TableVar.f32_round_half_up(a).max(-2147483648).min(2147483647)
		}
		b = AatTracking.at_size(table.bytes, at, $high, ptem)
		x = AatTracking.float(table.bytes, at + 8 + $low * 8)
		y = AatTracking.float(table.bytes, at + 8 + $high * 8)
		t = TableVar.f32_div(TableVar.f32_sub(0, x), TableVar.f32_sub(y, x))
		TableVar.f32_round_half_up(TableVar.f32_add(a, TableVar.f32_mul(t, TableVar.f32_sub(b, a)))).max(-2147483648).min(2147483647)
	}

	at_size : List(U8), U64, U64, U32 -> U32
	at_size = |bytes, at, track, ptem| {
		count = Bytes.u16(bytes, at + 2)
		if count == 0 {
			return 0
		}
		sizes = Bytes.u32(bytes, at + 4)
		values = Bytes.u16(bytes, at + 8 + track * 8 + 6)
		var $i = 0
		while $i < count and TableVar.f32_lt(AatTracking.float(bytes, sizes + $i * 4), ptem) {
			$i = $i + 1
		}
		if $i == 0 {
			return TableVar.f32_from_int(Bytes.i16(bytes, values))
		}
		if $i == count {
			return TableVar.f32_from_int(Bytes.i16(bytes, values + (count - 1) * 2))
		}
		s1 = AatTracking.float(bytes, sizes + $i * 4)
		v1 = TableVar.f32_from_int(Bytes.i16(bytes, values + $i * 2))
		if s1 == ptem {
			return v1
		}
		s0 = AatTracking.float(bytes, sizes + ($i - 1) * 4)
		v0 = TableVar.f32_from_int(Bytes.i16(bytes, values + ($i - 1) * 2))
		if s0 == s1 {
			return TableVar.f32_mul(TableVar.f32_add(v0, v1), TableVar.f32_half)
		}
		t = TableVar.f32_div(TableVar.f32_sub(ptem, s0), TableVar.f32_sub(s1, s0))
		TableVar.f32_add(v0, TableVar.f32_mul(t, TableVar.f32_sub(v1, v0)))
	}
}

expect AatTracking.read([]).is_err()
expect AatTracking.value(AatTracking.none, False, 12) == 0
