import Bytes

## Graphite replacement classes. A linear class preserves output order;
## an indexed class maps sorted glyph IDs to their original class positions.
GraphiteClasses :: {}.{

	Class : { start : U64, count : U64, linear : Bool, max_index : U64 }

	read : List(U8), U64, U64, U64, U64 -> Try(List(Class), [Bad(U64)])
	read = |bytes, start, end, version, glyph_count| {
		if end > bytes.len() or !Bytes.fits(start, 4, end) {
			return Err(Bad(start))
		}
		count = Bytes.u16(bytes, start)
		linear_count = Bytes.u16(bytes, start + 2)
		if linear_count > count {
			return Err(Bad(start + 2))
		}
		width = if (version >= 0x00040000) 4 else 2
		if !Bytes.fits(start + 4, (count + 1) * width, end) {
			return Err(Bad(start + 4))
		}
		offset = |i| if (width == 4) Bytes.u32(bytes, start + 4 + i * width) else Bytes.u16(bytes, start + 4 + i * width)
		minimum = 4 + (count + 1) * width
		if offset(0) < minimum or !Bytes.fits(start, offset(count), end) {
			return Err(Bad(start + 4))
		}
		var $classes = List.with_capacity(count)
		for i in 0..<count {
			first = offset(i)
			last = offset(i + 1)
			if first < minimum or last < first or !Bytes.fits(start, last, end) {
				return Err(Bad(start + 4 + i * width))
			}
			at = start + first
			limit = start + last
			if i < linear_count {
				if (last - first) % 2 != 0 {
					return Err(Bad(at))
				}
				n = (last - first) // 2
				for j in 0..<n {
					if Bytes.u16(bytes, at + 2 * j) >= glyph_count {
						return Err(Bad(at + 2 * j))
					}
				}
				$classes = $classes.append({ start: at, count: n, linear: True, max_index: if (n == 0) 0 else n - 1 })
			} else {
				if !Bytes.fits(at, 8, limit) {
					return Err(Bad(at))
				}
				n = Bytes.u16(bytes, at)
				if !Bytes.fits(at + 8, n * 4, limit) {
					return Err(Bad(at))
				}
				var $previous = 0
				var $maximum = 0
				for j in 0..<n {
					field = at + 8 + 4 * j
					glyph = Bytes.u16(bytes, field)
					if glyph >= glyph_count or (j != 0 and glyph <= $previous) {
						return Err(Bad(field))
					}
					$previous = glyph
					$maximum = $maximum.max(Bytes.u16(bytes, field + 2))
				}
				$classes = $classes.append({ start: at + 8, count: n, linear: False, max_index: $maximum })
			}
		}
		Ok($classes)
	}

	index : List(U8), Class, U64 -> [Found(U64), Missing]
	index = |bytes, class, glyph| {
		if class.linear {
			for i in 0..<class.count {
				if Bytes.u16(bytes, class.start + 2 * i) == glyph {
					return Found(i)
				}
			}
			Missing
		} else {
			var $lo = 0
			var $hi = class.count
			while $lo < $hi {
				mid = $lo + ($hi - $lo) // 2
				at = class.start + mid * 4
				candidate = Bytes.u16(bytes, at)
				if glyph < candidate {
					$hi = mid
				} else if glyph > candidate {
					$lo = mid + 1
				} else {
					return Found(Bytes.u16(bytes, at + 2))
				}
			}
			Missing
		}
	}

	glyph : List(U8), Class, U64 -> [Found(U64), Missing]
	glyph = |bytes, class, position| {
		if class.linear {
			if (position < class.count) Found(Bytes.u16(bytes, class.start + 2 * position)) else Missing
		} else {
			# Indexed input classes need not contain every original position.
			for i in 0..<class.count {
				if Bytes.u16(bytes, class.start + 4 * i + 2) == position {
					return Found(Bytes.u16(bytes, class.start + 4 * i))
				}
			}
			Missing
		}
	}
}

# Original two-class table: output[7,3], input{3->1,7->0}.
classes = [0, 2, 0, 1, 0, 10, 0, 14, 0, 30, 0, 7, 0, 3, 0, 2, 0, 2, 0, 1, 0, 0, 0, 3, 0, 1, 0, 7, 0, 0]
expect {
	match GraphiteClasses.read(classes, 0, classes.len(), 0x00030000, 8) {
		Ok(values) => {
			linear = values.get(0) ?? crash "checked first class"
			positioned = values.get(1) ?? crash "checked second class"
			GraphiteClasses.index(classes, linear, 3) == Found(1) and GraphiteClasses.index(classes, positioned, 7) == Found(0) and GraphiteClasses.glyph(classes, linear, 0) == Found(7) and GraphiteClasses.glyph(classes, positioned, 1) == Found(3) and GraphiteClasses.glyph(classes, linear, 2) == Missing
		}
		Err(_) => False
	}
}
expect GraphiteClasses.read(classes.drop_last(1), 0, classes.len() - 1, 0x00030000, 8).is_err()
expect GraphiteClasses.read(classes.set(27, 3) ?? [], 0, classes.len(), 0x00030000, 8).is_err()
