import Bytes
import GraphiteCompression

## Sparse Graphite glyph attributes (Gloc/Glat versions 1 through 3).
## Internal. Missing attributes have the format-defined value zero.
## Glyph spans, keys and values are flat; octabox spans retain their
## checked bytes for the collision interpreter.
GraphiteAttributes := {
	starts : List(U64),
	keys : List(U16),
	values : List(I16),
	box_starts : List(U64),
	bytes : List(U8),
	attribute_count : U64,
	major : U64,
}.{

	none : GraphiteAttributes
	none = { starts: [0], keys: [], values: [], box_starts: [], bytes: [], attribute_count: 0, major: 0 }

	glyph_count : GraphiteAttributes -> U64
	glyph_count = |table| table.starts.len() - 1

	Problem : { table : Str, offset : U64 }

	read : List(U8), List(U8), U64, U64 -> Try(GraphiteAttributes, [Bad(Problem), Bads(List(Problem)), OverLimit(Str)])
	read = |gloc, glat, glyphs, max_output| {
		bad = |table, offset| Err(Bad({ table, offset }))
		if glyphs > 65536 or gloc.len() < 8 {
			return bad("Gloc", 0)
		}
		version = Bytes.u32(gloc, 0)
		if version != 0x00010000 and version != 0x00010001 {
			return bad("Gloc", 0)
		}
		flags = Bytes.u16(gloc, 4)
		attributes = Bytes.u16(gloc, 6)
		# Only the defined width/name bits select layout. Unassigned bits
		# do not change the checked arrays and are tolerated by the format.
		width = if (flags.bitwise_and(1) != 0) 4 else 2
		labels = if (flags.bitwise_and(2) != 0) attributes * 2 else 0
		if !Bytes.fits(8, (glyphs + 1) * width + labels, gloc.len()) {
			return bad("Gloc", 8)
		}
		data = match GraphiteCompression.expand(glat, 0x00030000, max_output) {
			Ok(d) => d
			Err(Bad(at)) => return bad("Glat", at)
			Err(OverLimit(which)) => return Err(OverLimit(which))
		}
		major = Bytes.u16(data, 0)
		if major < 1 or major > 3 {
			return bad("Glat", 0)
		}
		header = if (major == 3) 8 else 4
		if data.len() < header {
			return bad("Glat", 0)
		}
		boxes = major == 3 and Bytes.u32(data, 4).bitwise_and(1) != 0
		offset = |g| if (width == 2) Bytes.u16(gloc, 8 + g * width) else Bytes.u32(gloc, 8 + g * width)
		# First validate all encoded runs and counts. No output allocation
		# uses an unchecked glyph/attribute count or decompressed offset.
		var $count = 0
		var $problems = []
		for g in 0..<glyphs {
			start = offset(g)
			end = offset(g + 1)
			if start < header or end < start or end > data.len() {
				$problems = $problems.append({ table: "Gloc", offset: 8 + g * width })
			} else {
				match GraphiteAttributes.attributes_at(data, start, end, boxes) {
					Err(bad_at) => {
						$problems = $problems.append({ table: "Glat", offset: bad_at })
					}
					Ok(at) => {
						if boxes {
							$problems = GraphiteAttributes.octabox_problems(data, start, at, $problems)
						}
						var $at = at
						var $previous = 0
						while $at < end {
							unit = if (major == 1) 1 else 2
							if !Bytes.fits($at, unit * 2, end) {
								$problems = $problems.append({ table: "Glat", offset: $at })
								break
							}
							first = if (unit == 1) Bytes.u8(data, $at) else Bytes.u16(data, $at)
							n = if (unit == 1) Bytes.u8(data, $at + 1) else Bytes.u16(data, $at + 2)
							if first < $previous or first + n > attributes or !Bytes.fits($at + unit * 2, n * 2, end) {
								$problems = $problems.append({ table: "Glat", offset: $at })
								break
							}
							$previous = first + n
							$count = $count + n
							$at = $at + unit * 2 + n * 2
						}
					}
				}
			}
		}
		if $problems.len() == 1 {
			return Err(Bad($problems.first() ?? crash "one read problem"))
		}
		if !$problems.is_empty() {
			return Err(Bads($problems))
		}
		var $starts = List.with_capacity(glyphs + 1)
		var $keys = List.with_capacity($count)
		var $values = List.with_capacity($count)
		var $box_starts = List.with_capacity(if (boxes) glyphs else 0)
		for g in 0..<glyphs {
			$starts = $starts.append($keys.len())
			start = offset(g)
			end = offset(g + 1)
			if boxes {
				$box_starts = $box_starts.append(start)
			}
			var $at = GraphiteAttributes.attributes_at(data, start, end, boxes) ?? end
			while $at < end {
				unit = if (major == 1) 1 else 2
				first = if (unit == 1) Bytes.u8(data, $at) else Bytes.u16(data, $at)
				n = if (unit == 1) Bytes.u8(data, $at + 1) else Bytes.u16(data, $at + 2)
				for i in 0..<n {
					$keys = $keys.append((first + i).to_u16_wrap())
					$values = $values.append(Bytes.i16(data, $at + unit * 2 + i * 2).to_i16_wrap())
				}
				$at = $at + unit * 2 + n * 2
			}
		}
		$starts = $starts.append($keys.len())
		Ok({ starts: $starts, keys: $keys, values: $values, box_starts: $box_starts, bytes: if (boxes) data else [], attribute_count: attributes, major })
	}

	attributes_at : List(U8), U64, U64, Bool -> Try(U64, U64)
	attributes_at = |bytes, start, end, boxes| {
		if !boxes {
			return Ok(start)
		}
		if !Bytes.fits(start, 6, end) {
			return Err(start)
		}
		bitmap = Bytes.u16(bytes, start)
		var $count = 0
		for i in 0..<16 {
			if bitmap.bitwise_and((1.U64).shl_wrap(i.to_u8_wrap())) != 0 {
				$count = $count + 1
			}
		}
		if !Bytes.fits(start + 6, $count * 8, end) {
			return Err(start)
		}
		Ok(start + 6 + $count * 8)
	}

	# GTF Octabox_metrics and Subbox_entry define ordered min/max pairs.
	# Equal endpoints describe degenerate boxes and remain valid. Span
	# validation has already proved every field before this pass.
	octabox_problems : List(U8), U64, U64, List(Problem) -> List(Problem)
	octabox_problems = |bytes, start, end, problems| {
		var $problems = problems
		for pair in 0..<2.U64 {
			at = start + 2 + 2 * pair
			if Bytes.u8(bytes, at) > Bytes.u8(bytes, at + 1) {
				$problems = $problems.append({ table: "Glat", offset: at })
			}
		}
		var $part = start + 6
		while $part < end {
			for pair in 0..<4.U64 {
				at = $part + 2 * pair
				if Bytes.u8(bytes, at) > Bytes.u8(bytes, at + 1) {
					$problems = $problems.append({ table: "Glat", offset: at })
				}
			}
			$part = $part + 8
		}
		$problems
	}

	get : GraphiteAttributes, U64, U64 -> I32
	get = |table, glyph, attribute| {
		if attribute >= table.attribute_count or glyph >= table.starts.len() or glyph + 1 >= table.starts.len() {
			return 0
		}
		var $lo = table.starts.get(glyph) ?? 0
		var $hi = table.starts.get(glyph + 1) ?? 0
		while $lo < $hi {
			mid = $lo + ($hi - $lo) // 2
			key = (table.keys.get(mid) ?? 0).to_u64()
			if attribute < key {
				$hi = mid
			} else if attribute > key {
				$lo = mid + 1
			} else {
				return (table.values.get(mid) ?? 0).to_i32()
			}
		}
		0
	}
}

## fuzz regression: a valid part followed by an inverted Y interval must
## never reach collision bin arithmetic after successful preparation.
expect {
	gloc = [0.U8, 1, 0, 0, 0, 0, 0, 0, 0, 8, 0, 30]
	glat = [0.U8, 3, 0, 0, 0, 0, 0, 1, 0, 3, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 192, 64, 0, 255, 0, 255]
	match GraphiteAttributes.read(gloc, glat, 1, 1024) {
		Err(Bad(problem)) => problem == { table: "Glat", offset: 24 }
		_ => False
	}
}

expect {
	gloc = [0.U8, 1, 0, 0, 0, 0, 0, 0, 0, 8, 0, 22]
	# All six independent pairs are inverted; report their exact offsets.
	glat = [0.U8, 3, 0, 0, 0, 0, 0, 1, 0, 1, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0]
	match GraphiteAttributes.read(gloc, glat, 1, 1024) {
		Err(Bads(problems)) => problems == [10.U64, 12, 14, 16, 18, 20].map(|at| { table: "Glat", offset: at })
		_ => False
	}
}

expect {
	gloc = [0.U8, 1, 0, 0, 0, 0, 0, 0, 0, 8, 0, 22]
	# Equality is a degenerate interval, not an inversion.
	glat = [0.U8, 3, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 50, 50, 100, 100, 25, 25, 30, 30]
	GraphiteAttributes.read(gloc, glat, 1, 1024).is_ok()
}

expect {
	gloc = [0, 1, 0, 0, 0, 0, 0, 3, 0, 4, 0, 10]
	glat = [0, 1, 0, 0, 1, 2, 255, 255, 0, 7]
	match GraphiteAttributes.read(gloc, glat, 1, 1024) {
		Ok(t) => GraphiteAttributes.get(t, 0, 0) == 0 and GraphiteAttributes.get(t, 0, 1) == -1 and GraphiteAttributes.get(t, 0, 2) == 7 and GraphiteAttributes.get(t, 1, 1) == 0
		Err(_) => False
	}
}

## fuzz regression: unassigned Gloc bits must not reject unchanged layouts.
expect {
	var $ok = True
	for flags in [4.U16, 8, 0x4000, 0x8000] {
		gloc = [0.U8, 1, 0, 0, flags.shr_zf_wrap(8).to_u8_wrap(), flags.to_u8_wrap(), 0, 3, 0, 4, 0, 10]
		glat = [0.U8, 1, 0, 0, 1, 2, 255, 255, 0, 7]
		$ok = $ok and (
			match GraphiteAttributes.read(gloc, glat, 1, 1024) {
				Ok(table) => GraphiteAttributes.get(table, 0, 1) == -1 and GraphiteAttributes.get(table, 0, 2) == 7
				Err(_) => False
			}
		)
	}
	$ok
}
