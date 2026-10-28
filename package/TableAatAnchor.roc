import Bytes
import AatLookup

## Validated AAT anchor points. Missing glyphs and point indices are
## explicit absence, never a point borrowed from another glyph.
TableAatAnchor := { bytes : List(U8), lookup : AatLookup, data : U64, glyphs : U64 }.{
	Problem : { offset : U64 }
	Point : { x : I32, y : I32 }
	none : TableAatAnchor
	none = { bytes: [], lookup: AatLookup.empty, data: 0, glyphs: 0 }
	read : List(U8), U64 -> Try(TableAatAnchor, List(Problem))
	read = |bytes, glyphs| {
		bad = |at| Err([{ offset: at }])
		if glyphs > 65536 or !Bytes.fits(0, 12, bytes.len()) {
			return bad(0)
		}
		var $problems = []
		if Bytes.u16(bytes, 0) != 0 {
			$problems = $problems.append({ offset: 0 })
		}
		if Bytes.u16(bytes, 2) != 0 {
			$problems = $problems.append({ offset: 2 })
		}
		lookup_at = Bytes.u32(bytes, 4)
		data = Bytes.u32(bytes, 8)
		lookup = if lookup_at == 0 {
			AatLookup.empty
		} else if lookup_at < 12 {
			$problems = $problems.append({ offset: 4 })
			AatLookup.empty
		} else match AatLookup.read(bytes, lookup_at, glyphs, 2) {
			Ok(v) => v
			Err(Bad(at)) => {
				$problems = $problems.append({ offset: at })
				AatLookup.empty
			}
		}
		if data < 12 or !Bytes.fits(data, 0, bytes.len()) {
			$problems = $problems.append({ offset: 8 })
		}
		if !$problems.is_empty() {
			return Err($problems)
		}
		pool = AatLookup.value_pool(lookup)
		for segment in AatLookup.segments(lookup) {
			if segment.first < glyphs {
				count = if segment.array {
					(segment.last + 1).min(glyphs) - segment.first
				} else 1
				for index in 0..<count {
					offset = if (segment.array) (pool.get(segment.value + index) ?? 0).to_u64() else segment.value
					at = data + offset
					if !Bytes.fits(at, 4, bytes.len()) {
						$problems = $problems.append({ offset: at })
					} else {
						points = Bytes.u32(bytes, at)
						if !Bytes.fits(at + 4, points * 4, bytes.len()) {
							$problems = $problems.append({ offset: at })
						}
					}
				}
			}
		}
		if ($problems.is_empty()) Ok({ bytes, lookup, data, glyphs }) else Err($problems)
	}
	anchor : TableAatAnchor, U64, U64 -> [Present(Point), Absent]
	anchor = |table, glyph, index| {
		if glyph >= table.glyphs {
			return Absent
		}
		match AatLookup.get(table.lookup, glyph) {
			Missing => Absent
			Found(offset) => {
				at = table.data + offset.to_u64()
				if index >= Bytes.u32(table.bytes, at) {
					Absent
				} else {
					point = at + 4 + index * 4
					Present({ x: Bytes.i16(table.bytes, point).to_i32_wrap(), y: Bytes.i16(table.bytes, point + 2).to_i32_wrap() })
				}
			}
		}
	}
}

expect TableAatAnchor.anchor(TableAatAnchor.none, 0, 0) == Absent
expect match TableAatAnchor.read([], 0) {
	Err(ps) => ps == [{ offset: 0 }]
	Ok(_) => False
}
expect {
	bytes = [0.U8, 0, 0, 0, 0, 0, 0, 12, 0, 0, 0, 20, 0, 8, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 50, 255, 156]
	match TableAatAnchor.read(bytes, 3) {
		Ok(t) => TableAatAnchor.anchor(t, 0, 0) == Absent and TableAatAnchor.anchor(t, 1, 0) == Present({ x: 50, y: -100 }) and TableAatAnchor.anchor(t, 1, 1) == Absent
		Err(_) => False
	}
}

expect match TableAatAnchor.read([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12], 3) {
	Ok(t) => TableAatAnchor.anchor(t, 1, 0) == Absent
	Err(_) => False
}
expect match TableAatAnchor.read([0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 12], 3) {
	Err(ps) => ps == [{ offset: 0 }, { offset: 2 }]
	Ok(_) => False
}
