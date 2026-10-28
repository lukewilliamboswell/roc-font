import Bytes
import TableCffData

## Checked CFF side tables. Every count-sized output is bounded by the
## caller's validated glyph/FD count before allocation.
TableCffTables :: {}.{
	charset : List(U8), U64, U64, U64 -> Try(List(U64), [Bad(U64)])
	charset = |data, at, glyphs, maximum| {
		if glyphs == 0 or glyphs > 65535 or maximum > 65926 {
			return Err(Bad(at))
		}
		var $out = List.with_capacity(glyphs)
		if at <= 2 {
			if at == 0 {
				if glyphs > 229 {
					return Err(Bad(at))
				}
				for i in 0..<glyphs {
					$out = $out.append(i)
				}
			} else {
				predefined = if (at == 1) TableCffData.expert else TableCffData.expert_subset
				if glyphs > predefined.len() {
					return Err(Bad(at))
				}
				$out = predefined.take_first(glyphs)
			}
		} else {
			if !Bytes.fits(at, 1, data.len()) {
				return Err(Bad(at))
			}
			format = Bytes.u8(data, at)
			if format > 2 {
				return Err(Bad(at))
			}
			var $cursor = at + 1
			$out = $out.append(0)
			for _ in 1..<glyphs {
				if $out.len() == glyphs {
					break
				}
				width = if (format == 0) 2 else if (format == 1) 3 else 4
				if !Bytes.fits($cursor, width, data.len()) {
					return Err(Bad($cursor))
				}
				first = Bytes.u16(data, $cursor)
				left = if (format == 0) 0 else if (format == 1) Bytes.u8(data, $cursor + 2) else Bytes.u16(data, $cursor + 2)
				if left + 1 > glyphs - $out.len() or first + left > maximum {
					return Err(Bad($cursor))
				}
				for i in 0..<(left + 1) {
					$out = $out.append(first + i)
				}
				$cursor = $cursor + width
			}
		}
		var $seen = List.repeat(False, maximum + 1)
		for sid in $out {
			if sid > maximum or ($seen.get(sid) ?? True) {
				return Err(Bad(at))
			}
			$seen = $seen.set(sid, True) ?? []
		}
		Ok($out)
	}

	encoding : List(U8), U64, List(U64) -> Try({}, [Bad(U64)])
	encoding = |data, at, sids| {
		if at <= 1 {
			return Ok({})
		}
		if !Bytes.fits(at, 2, data.len()) {
			return Err(Bad(at))
		}
		flags = Bytes.u8(data, at)
		format = flags.bitwise_and(127)
		if format > 1 {
			return Err(Bad(at))
		}
		count = Bytes.u8(data, at + 1)
		var $cursor = at + 2
		var $glyph = 1
		var $seen = List.repeat(False, 256)
		for _ in 0..<count {
			width = if (format == 0) 1 else 2
			if !Bytes.fits($cursor, width, data.len()) {
				return Err(Bad($cursor))
			}
			first = Bytes.u8(data, $cursor)
			left = if (format == 0) 0 else Bytes.u8(data, $cursor + 1)
			if first + left > 255 or $glyph + left >= sids.len() {
				return Err(Bad($cursor))
			}
			for i in first..<(first + left + 1) {
				if $seen.get(i) ?? True {
					return Err(Bad($cursor))
				}
				$seen = $seen.set(i, True) ?? []
			}
			$glyph = $glyph + left + 1
			$cursor = $cursor + width
		}
		if flags.bitwise_and(128) != 0 {
			if !Bytes.fits($cursor, 1, data.len()) {
				return Err(Bad($cursor))
			}
			supplements = Bytes.u8(data, $cursor)
			$cursor = $cursor + 1
			if !Bytes.fits($cursor, supplements * 3, data.len()) {
				return Err(Bad($cursor))
			}
			for i in 0..<supplements {
				entry = $cursor + i * 3
				code = Bytes.u8(data, entry)
				sid = Bytes.u16(data, entry + 1)
				if ($seen.get(code) ?? True) or !sids.contains(sid) {
					return Err(Bad(entry))
				}
				$seen = $seen.set(code, True) ?? []
			}
		}
		Ok({})
	}

	fd_select : List(U8), U64, U64, U64, Bool -> Try(List(U32), [Bad(U64)])
	fd_select = |data, at, glyphs, fds, cff2| {
		if glyphs > 65535 or fds == 0 or fds > 65536 or !Bytes.fits(at, 1, data.len()) {
			return Err(Bad(at))
		}
		format = Bytes.u8(data, at)
		var $out = List.with_capacity(glyphs)
		if format == 0 {
			if !Bytes.fits(at + 1, glyphs, data.len()) {
				return Err(Bad(at + 1))
			}
			for i in 0..<glyphs {
				fd = Bytes.u8(data, at + 1 + i)
				if fd >= fds {
					return Err(Bad(at + 1 + i))
				}
				$out = $out.append(fd.to_u32_wrap())
			}
		} else if format == 3 or (cff2 and format == 4) {
			wide = format == 4
			count_width = if (wide) 4 else 2
			fd_width = if (wide) 2 else 1
			entry_width = count_width + fd_width
			if !Bytes.fits(at + 1, count_width, data.len()) {
				return Err(Bad(at + 1))
			}
			count = if (wide) Bytes.u32(data, at + 1) else Bytes.u16(data, at + 1)
			start = at + 1 + count_width
			if count == 0 or count > glyphs or !Bytes.fits(start, count * entry_width + count_width, data.len()) {
				return Err(Bad(start))
			}
			var $previous = 0
			for i in 0..<count {
				entry = start + i * entry_width
				first = if (wide) Bytes.u32(data, entry) else Bytes.u16(data, entry)
				fd = if (wide) Bytes.u16(data, entry + count_width) else Bytes.u8(data, entry + count_width)
				next = if (wide) Bytes.u32(data, entry + entry_width) else Bytes.u16(data, entry + entry_width)
				if first != $previous or next <= first or next > glyphs or fd >= fds {
					return Err(Bad(entry))
				}
				for _ in first..<next {
					$out = $out.append(fd.to_u32_wrap())
				}
				$previous = next
			}
			if $previous != glyphs {
				return Err(Bad(start + count * entry_width))
			}
		} else {
			return Err(Bad(at))
		}
		Ok($out)
	}
}

expect TableCffTables.charset([0, 0, 0, 1, 0, 1, 1], 3, 3, 390) == Ok([0, 1, 2])
expect TableCffTables.charset([0, 0, 0, 0, 0, 1, 0, 1], 3, 3, 390) == Err(Bad(3))
expect TableCffTables.fd_select([3, 0, 2, 0, 0, 0, 0, 2, 1, 0, 4], 0, 4, 2, False) == Ok([0, 0, 1, 1])
expect TableCffTables.fd_select([3, 0, 1, 0, 1, 0, 0, 4], 0, 4, 1, False) == Err(Bad(3))
expect TableCffTables.encoding([0, 0, 0, 128, 1, 65, 1, 66, 0, 1], 3, [0, 1]) == Ok({})
