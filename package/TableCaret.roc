import TableVar
import TableGlyfPoints
import TableGvar
import TableOutline
import LayoutVar

## Font-defined ligature caret positions, in their table order. A scalar
## record refers to an explicit coordinate or an outline point; queries
## preserve every record, including unavailable points on non-TrueType
## outlines. Pixel devices are validated but add nothing in font units.
TableCaret := {
	glyphs : List(U64),
	starts : List(U64),
	values : List({ point : Bool, value : I64, outer : U64, inner : U64 }),
}.{
	none : TableCaret
	none = { glyphs: [], starts: [0], values: [] }

	read : List(U8), U64, [Present(TableGlyfPoints), Absent], LayoutVar -> Try(TableCaret, [Bad(U64)])
	read = |data, glyph_count, outline_points, variation_store| {
		if !TableVar.fits(0, 12, data.len()) or TableVar.u16(data, 0) != 1 {
			return Err(Bad(0))
		}
		at = TableVar.u16(data, 8)
		if at == 0 {
			return Ok(TableCaret.none)
		}
		if !TableVar.fits(at, 4, data.len()) {
			return Err(Bad(at))
		}
		count = TableVar.u16(data, at + 2)
		if count > glyph_count or !TableVar.fits(at + 4, 2 * count, data.len()) {
			return Err(Bad(at + 2))
		}
		coverage_offset = TableVar.u16(data, at)
		if coverage_offset < 4 + 2 * count {
			return Err(Bad(at))
		}
		glyphs = TableCaret.coverage(data, at + coverage_offset, glyph_count, count)?
		var $starts = [0]
		var $values = []
		var $steps = 0.U64
		# Aliased subtables may not multiply work or allocation without a
		# bound. Match layout reading's 64 visits per input byte budget.
		limit = data.len() * 64 + 1024
		for i in 0..<count {
			offset = TableVar.u16(data, at + 4 + 2 * i)
			ligature = at + offset
			if offset < 4 + 2 * count or !TableVar.fits(ligature, 2, data.len()) {
				return Err(Bad(at + 4 + 2 * i))
			}
			n = TableVar.u16(data, ligature)
			if !TableVar.fits(ligature + 2, 2 * n, data.len()) or $steps + n > limit {
				return Err(Bad(ligature))
			}
			$steps = $steps + n
			var $point_count = 0
			var $counted_points = False
			for j in 0..<n {
				value_offset = TableVar.u16(data, ligature + 2 + 2 * j)
				value_at = ligature + value_offset
				if value_offset < 2 + 2 * n or !TableVar.fits(value_at, 4, data.len()) {
					return Err(Bad(ligature + 2 + 2 * j))
				}
				format = TableVar.u16(data, value_at)
				if format < 1 or format > 3 {
					return Err(Bad(value_at))
				}
				value = if (format == 2) TableVar.u16(data, value_at + 2).to_i64_wrap() else TableVar.i16(data, value_at + 2)
				if format == 2 {
					match outline_points {
						Present(points) => {
							if !$counted_points {
								$point_count = TableOutline.point_count(points, glyphs.get(i) ?? glyph_count)
								$steps = $steps + $point_count
								if $steps > limit {
									return Err(Bad(value_at))
								}
								$counted_points = True
							}
							if value.to_u64_wrap() >= $point_count {
								return Err(Bad(value_at + 2))
							}
						}
						Absent => {}
					}
				}
				var $outer = TableVar.no_variation
				var $inner = TableVar.no_variation
				if format == 3 {
					if !TableVar.fits(value_at + 4, 2, data.len()) {
						return Err(Bad(value_at + 4))
					}
					device_offset = TableVar.u16(data, value_at + 4)
					if device_offset != 0 {
						device = value_at + device_offset
						if !TableVar.fits(device, 6, data.len()) {
							return Err(Bad(device))
						}
						start = TableVar.u16(data, device)
						end = TableVar.u16(data, device + 2)
						device_format = TableVar.u16(data, device + 4)
						if device_format == 0x8000 {
							if !LayoutVar.valid_index(variation_store, start, end) {
								return Err(Bad(device))
							}
							$outer = start
							$inner = end
						} else {
							if device_format < 1 or device_format > 3 or end < start {
								return Err(Bad(device + 4))
							}
							words = (end - start) // (1.U64).shl_wrap((4 - device_format).to_u8_wrap()) + 1
							if !TableVar.fits(device + 6, 2 * words, data.len()) {
								return Err(Bad(device + 6))
							}
						}
					}
				}
				$values = $values.append({ point: format == 2, value, outer: $outer, inner: $inner })
			}
			$starts = $starts.append($values.len())
		}
		Ok({ glyphs, starts: $starts, values: $values })
	}

	coverage : List(U8), U64, U64, U64 -> Try(List(U64), [Bad(U64)])
	coverage = |data, at, glyph_count, expected| {
		if !TableVar.fits(at, 4, data.len()) {
			return Err(Bad(at))
		}
		format = TableVar.u16(data, at)
		count = TableVar.u16(data, at + 2)
		var $out = List.with_capacity(expected)
		if format == 1 {
			if count != expected or !TableVar.fits(at + 4, count * 2, data.len()) {
				return Err(Bad(at + 2))
			}
			for i in 0..<count {
				glyph = TableVar.u16(data, at + 4 + 2 * i)
				if glyph >= glyph_count or (i > 0 and glyph <= ($out.last() ?? 0)) {
					return Err(Bad(at + 4 + 2 * i))
				}
				$out = $out.append(glyph)
			}
		} else if format == 2 {
			if !TableVar.fits(at + 4, count * 6, data.len()) {
				return Err(Bad(at + 2))
			}
			for i in 0..<count {
				r = at + 4 + 6 * i
				first = TableVar.u16(data, r)
				last = TableVar.u16(data, r + 2)
				index = TableVar.u16(data, r + 4)
				if first > last or last >= glyph_count or index != $out.len() or $out.len() + last - first + 1 > expected or (i > 0 and first <= ($out.last() ?? 0)) {
					return Err(Bad(r))
				}
				for glyph in first..<(last + 1) {
					$out = $out.append(glyph)
				}
			}
			if $out.len() != expected {
				return Err(Bad(at + 2))
			}
		} else {
			return Err(Bad(at))
		}
		Ok($out)
	}

	positions : TableCaret, U64, LayoutVar, LayoutVar.Location, [Present({ points : TableGlyfPoints, gvar : TableGvar }), Absent], TableGvar.Location -> List([Position(F64), Unavailable])
	positions = |table, glyph, variation_store, layout_location, outlines, outline_location| {
		var $low = 0
		var $high = table.glyphs.len()
		while $low < $high {
			mid = $low + ($high - $low) // 2
			if (table.glyphs.get(mid) ?? glyph) < glyph {
				$low = mid + 1
			} else {
				$high = mid
			}
		}
		if (table.glyphs.get($low) ?? 0x100000000) != glyph {
			return []
		}
		start = table.starts.get($low) ?? 0
		end = table.starts.get($low + 1) ?? start
		needs_points = table.values.sublist({ start, len: end - start }).any(|caret| caret.point)
		# Evaluate each outline once, including aliased point carets.
		placed = if needs_points {
			match outlines {
				Present(outline) => TableGvar.points(outline.points, outline.gvar, outline_location, glyph)
				Absent => { xs: [], ys: [] }
			}
		} else {
			{ xs: [], ys: [] }
		}
		point_count = if (placed.xs.len() >= 4) placed.xs.len() - 4 else 0
		shift = placed.xs.get(point_count) ?? 0
		var $out = List.with_capacity(end - start)
		for i in start..<end {
			caret = table.values.get(i) ?? { point: False, value: 0, outer: TableVar.no_variation, inner: TableVar.no_variation }
			if caret.point {
				index = caret.value.to_u64_wrap()
				$out = $out.append(
					if index < point_count {
						Position(TableOutline.widen(TableVar.f32_sub(placed.xs.get(index) ?? 0, shift)))
					} else {
						Unavailable
					},
				)
			} else {
				delta = LayoutVar.delta(variation_store, layout_location, caret.outer, caret.inner)
				$out = $out.append(Position((caret.value + delta).to_f64()))
			}
		}
		$out
	}
}
