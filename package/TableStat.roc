import Bytes

## Validate the style-attribute directory used to select modern Apple
## tracking. No axis-value records are interpreted during shaping.
TableStat :: {}.{
	read : List(U8) -> Try({}, [Bad(U64)])
	read = |bytes| {
		if bytes.len() < 20 or Bytes.u16(bytes, 0) != 1 or Bytes.u16(bytes, 2) == 0 {
			return Err(Bad(0))
		}
		width = Bytes.u16(bytes, 4)
		count = Bytes.u16(bytes, 6)
		axes = Bytes.u32(bytes, 8)
		values = Bytes.u16(bytes, 12)
		array = Bytes.u32(bytes, 14)
		if width < 8 or !Bytes.fits(axes, width * count, bytes.len()) or (count != 0 and axes == 0) {
			return Err(Bad(8))
		}
		if !Bytes.fits(array, values * 2, bytes.len()) or (values != 0 and array == 0) {
			return Err(Bad(14))
		}
		for i in 0..<values {
			relative = Bytes.u16(bytes, array + i * 2)
			if relative != 0 {
				at = array + relative
				if !Bytes.fits(at, 2, bytes.len()) {
					return Err(Bad(array + i * 2))
				}
				format = Bytes.u16(bytes, at)
				length = match format {
					1 => 12
					2 => 20
					3 => 16
					4 => 8
					_ => 2
				}
				if !Bytes.fits(at, length, bytes.len()) {
					return Err(Bad(at))
				}
				if format == 4 and !Bytes.fits(at + 8, Bytes.u16(bytes, at + 2) * 6, bytes.len()) {
					return Err(Bad(at))
				}
			}
		}
		Ok({})
	}
}

expect TableStat.read([]).is_err()
expect TableStat.read([0, 1, 0, 1, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]).is_ok()
