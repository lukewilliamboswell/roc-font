import Bytes

## Checked CFF INDEX spans. Prepared records contain only scalar offsets
## into the original table, avoiding one retained list per subroutine/FD.
TableCffIndex :: {}.{
	Span : { start : U64, end : U64 }
	Index : { count : U64, offsets : U64, width : U64, data : U64, next : U64 }

	read : List(U8), U64, Bool -> Try(Index, [Bad(U64)])
	read = |bytes, at, cff2| {
		size = bytes.len()
		count_size = if (cff2) 4 else 2
		if !Bytes.fits(at, count_size, size) {
			return Err(Bad(at))
		}
		count = if (cff2) Bytes.u32(bytes, at) else Bytes.u16(bytes, at)
		if count == 0 {
			return Ok({ count: 0, offsets: at + count_size, width: 0, data: at + count_size, next: at + count_size })
		}
		if !Bytes.fits(at + count_size, 1, size) {
			return Err(Bad(at + count_size))
		}
		width = Bytes.u8(bytes, at + count_size)
		if width < 1 or width > 4 {
			return Err(Bad(at + count_size))
		}
		offsets = at + count_size + 1
		# A U32 count plus one, times at most four, fits U64. Check the
		# complete offset array before the loop or any count-sized allocation.
		if !Bytes.fits(offsets, (count + 1) * width, size) {
			return Err(Bad(offsets))
		}
		data = offsets + (count + 1) * width
		var $previous = 1
		for i in 0..<(count + 1) {
			entry_at = offsets + i * width
			relative = TableCffIndex.offset(bytes, entry_at, width)
			if (i == 0 and relative != 1) or relative < $previous or relative - 1 > size - data {
				return Err(Bad(entry_at))
			}
			$previous = relative
		}
		Ok({ count, offsets, width, data, next: data + $previous - 1 })
	}

	offset : List(U8), U64, U64 -> U64
	offset = |bytes, at, width| {
		var $out = 0
		for i in 0..<width {
			$out = $out * 256 + Bytes.u8(bytes, at + i)
		}
		$out
	}

	## Callers proved i < count when preparing the charstring's execution.
	span : List(U8), Index, U64 -> Span
	span = |bytes, index, i| {
		first = TableCffIndex.offset(bytes, index.offsets + i * index.width, index.width)
		last = TableCffIndex.offset(bytes, index.offsets + (i + 1) * index.width, index.width)
		{ start: index.data + first - 1, end: index.data + last - 1 }
	}

	empty : Index
	empty = { count: 0, offsets: 0, width: 0, data: 0, next: 0 }
}

expect TableCffIndex.read([0, 0], 0, False) == Ok({ count: 0, offsets: 2, width: 0, data: 2, next: 2 })
expect TableCffIndex.read([0, 0, 0, 0], 0, True) == Ok({ count: 0, offsets: 4, width: 0, data: 4, next: 4 })
expect {
	bytes = [0, 2, 1, 1, 1, 3, 42, 43]
	match TableCffIndex.read(bytes, 0, False) {
		Ok(index) => TableCffIndex.span(bytes, index, 0) == { start: 6, end: 6 } and TableCffIndex.span(bytes, index, 1) == { start: 6, end: 8 } and index.next == 8
		Err(_) => False
	}
}
expect TableCffIndex.read([0, 1, 0], 0, False) == Err(Bad(2))
expect TableCffIndex.read([0, 1, 1, 0, 1], 0, False) == Err(Bad(3))
expect TableCffIndex.read([0, 1, 1, 1, 3, 0], 0, False) == Err(Bad(4))
