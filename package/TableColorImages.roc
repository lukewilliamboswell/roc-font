import Bytes

## Encoded image assets in SVG, sbix and CBDT/CBLC. Prepared records hold
## only scalars and spans into the original table bytes. Pixel metrics stay
## in native strike pixels; SVG documents retain their font - coordinate
## system. No decoder, rasterizer, strike - selection policy or file I/O.
## Every container reference is validated eagerly, including every sbix
## duplicate chain. Encoded XML/image content itself is not decoded here.
TableColorImages := {
	data : List(U8),
	entries : List(Entry),
	strike_records : List({ fact : Strike, start : U64, end : U64 }),
}.{
	Problem : [Bad({ table : Str, offset : U64 })]
	SvgEncoding : [Utf8, Gzip]
	Format : [Png, Jpeg, Tiff, Pdf, Mask, Other(U32)]
	BearingAdvance : { bearing_x : I16, bearing_y : I16, advance : U16 }
	BitmapMetrics : { width : U8, height : U8, horizontal : [Present(BearingAdvance), Absent], vertical : [Present(BearingAdvance), Absent] }
	Placement : [Sbix({ origin_x : I16, origin_y : I16, source_glyph : U32 }), Bitmap(BitmapMetrics)]
	Image : { format : Format, bytes : List(U8), placement : Placement }
	SvgDocument : { bytes : List(U8), encoding : SvgEncoding, first_glyph : U32, last_glyph : U32 }
	LineMetrics : { ascender : I16, descender : I16, width_max : U8, caret_slope_numerator : I16, caret_slope_denominator : I16, caret_offset : I16, min_origin_side_bearing : I16, min_advance_side_bearing : I16, max_before_baseline : I16, min_after_baseline : I16 }
	Strike : [Sbix({ ppem : U16, ppi : U16, draw_outlines : Bool }), ColorBitmap({ ppem_x : U8, ppem_y : U8, bit_depth : U8, flags : U8, first_glyph : U32, last_glyph : U32, horizontal : LineMetrics, vertical : LineMetrics })]
	Entry : { first : U64, last : U64, start : U64, len : U64, format : U32, placement : Placement }
	none : TableColorImages
	none = { data: [], entries: [], strike_records: [] }

	empty_placement : Placement
	empty_placement = Sbix({ origin_x: 0, origin_y: 0, source_glyph: 0 })
	empty_entry : Entry
	empty_entry = { first: 0, last: 0, start: 0, len: 0, format: 0, placement: TableColorImages.empty_placement }
	bad = |table, offset| Err(Bad({ table, offset }))
	i8 : List(U8), U64 -> I16
	i8 = |data, at| {
		value = Bytes.u8(data, at).to_i16_wrap()
		if value >= 128 {
			value - 256
		} else {
			value
		}
	}

	read_svg : List(U8), U64 -> Try(TableColorImages, Problem)
	read_svg = |data, glyph_count| {
		if !Bytes.fits(0, 10, data.len()) or Bytes.u16(data, 0) != 0 or Bytes.u32(data, 6) != 0 {
			return TableColorImages.bad("SVG ", 0)
		}
		at = Bytes.u32(data, 2)
		if at < 10 or !Bytes.fits(at, 2, data.len()) {
			return TableColorImages.bad("SVG ", 2)
		}
		count = Bytes.u16(data, at)
		if count == 0 or !Bytes.fits(at + 2, count * 12, data.len()) {
			return TableColorImages.bad("SVG ", at)
		}
		var $entries = List.with_capacity(count)
		var $last = 0
		for i in 0..<count {
			record = at + 2 + i * 12
			first = Bytes.u16(data, record)
			last = Bytes.u16(data, record + 2)
			offset = Bytes.u32(data, record + 4)
			length = Bytes.u32(data, record + 8)
			if first > last or last >= glyph_count or (i > 0 and first <= $last) {
				return TableColorImages.bad("SVG ", record)
			}
			if offset < 2 + count * 12 or length == 0 or !Bytes.fits(at + offset, length, data.len()) {
				return TableColorImages.bad("SVG ", record + 4)
			}
			# A gzip wrapper must identify deflate; leave its stream encoded.
			if length >= 2 and Bytes.u16(data, at + offset) == 0x1F8B and (length < 3 or Bytes.u8(data, at + offset + 2) != 8) {
				return TableColorImages.bad("SVG ", at + offset)
			}
			$entries = $entries.append({ first, last, start: at + offset, len: length, format: 0, placement: TableColorImages.empty_placement })
			$last = last
		}
		Ok({ data, entries: $entries, strike_records: [] })
	}

	svg : TableColorImages, U64 -> [Present(SvgDocument), Absent]
	svg = |table, glyph| match TableColorImages.find(table.entries, 0, table.entries.len(), glyph) {
		Absent => Absent
		Present(entry) => Present({
			bytes: table.data.sublist({ start: entry.start, len: entry.len }),
			encoding: if entry.len >= 3 and Bytes.u16(table.data, entry.start) == 0x1F8B {
				Gzip
			} else {
				Utf8
			},
			first_glyph: entry.first.to_u32_wrap(),
			last_glyph: entry.last.to_u32_wrap(),
		})
	}

	format_for_tag : U32 -> Format
	format_for_tag = |tag| match tag {
		0x706E6720 => Png
		0x6A706720 => Jpeg
		0x74696666 => Tiff
		0x70646620 => Pdf
		0x6D61736B => Mask
		_ => Other(tag)
	}
	strikes : TableColorImages -> List(Strike)
	strikes = |table| table.strike_records.map(|record| record.fact)
	bitmap : TableColorImages, U64, U64 -> [Present(Image), Absent]
	bitmap = |table, strike, glyph| match table.strike_records.get(strike) {
		Err(_) => Absent
		Ok(record) => match TableColorImages.find(table.entries, record.start, record.end, glyph) {
			Absent => Absent
			Present(entry) => Present({ format: TableColorImages.format_for_tag(entry.format), bytes: table.data.sublist({ start: entry.start, len: entry.len }), placement: entry.placement })
		}
	}
	find : List(Entry), U64, U64, U64 -> [Present(Entry), Absent]
	find = |entries, start, end, glyph| {
		var $low = start
		var $high = end
		while $low < $high {
			mid = $low + ($high - $low) // 2
			entry = entries.get(mid) ?? TableColorImages.empty_entry
			if glyph < entry.first {
				$high = mid
			} else if glyph > entry.last {
				$low = mid + 1
			} else {
				return Present(entry)
			}
		}
		Absent
	}

	## Resolve aliases once. Kinds0/1/2/3 are absent/image/dupe/visiting.
	## Every duplicate is visited once, so even a chain of numGlyphs aliases
	## takes linear work. Queries never walk the graph. Resolved origins are
	## those of the source image, matching FreeType's sbix retry semantics.
	read_sbix : List(U8), U64 -> Try(TableColorImages, Problem)
	read_sbix = |data, glyph_count| {
		if !Bytes.fits(0, 8, data.len()) or Bytes.u16(data, 0) != 1 or (Bytes.u16(data, 2) != 1 and Bytes.u16(data, 2) != 3) {
			return TableColorImages.bad("sbix", 0)
		}
		count = Bytes.u32(data, 4)
		if !Bytes.fits(8, count * 4, data.len()) {
			return TableColorImages.bad("sbix", 4)
		}
		var $entries = []
		var $strikes = List.with_capacity(count)
		for strike in 0..<count {
			base = Bytes.u32(data, 8 + 4 * strike)
			if base < 8 + 4 * count or !Bytes.fits(base, 4 + (glyph_count + 1) * 4, data.len()) {
				return TableColorImages.bad("sbix", 8 + 4 * strike)
			}
			ppem = Bytes.u16(data, base)
			ppi = Bytes.u16(data, base + 2)
			if ppem == 0 {
				return TableColorImages.bad("sbix", base)
			}
			var $raw = List.with_capacity(glyph_count)
			# Charge alias - strike amplification to actual table bytes, even when
			# several strike offsets point at the same offset array.
			if (strike + 1) * glyph_count > data.len() * 8 {
				return TableColorImages.bad("sbix", base)
			}
			for glyph in 0..<glyph_count {
				start = Bytes.u32(data, base + 4 + 4 * glyph)
				end = Bytes.u32(data, base + 8 + 4 * glyph)
				if start < 4 + (glyph_count + 1) * 4 or end < start or !Bytes.fits(base + start, end - start, data.len()) {
					return TableColorImages.bad("sbix", base + 4 + 4 * glyph)
				}
				if start == end {
					$raw = $raw.append({ kind: 0.U8, target: 0.U64, entry: { ..TableColorImages.empty_entry, first: glyph, last: glyph } })
				} else {
					if end - start < 8 {
						return TableColorImages.bad("sbix", base + start)
					}
					tag = Bytes.u32(data, base + start + 4).to_u32_wrap()
					duplicate = tag == 0x64757065
					if duplicate and end - start != 10 {
						return TableColorImages.bad("sbix", base + start + 8)
					}
					target = if duplicate {
						Bytes.u16(data, base + start + 8)
					} else {
						glyph
					}
					if target >= glyph_count {
						return TableColorImages.bad("sbix", base + start + 8)
					}
					entry = { first: glyph, last: glyph, start: base + start + 8, len: end - start - 8, format: tag, placement: Sbix({ origin_x: Bytes.i16(data, base + start).to_i16_wrap(), origin_y: Bytes.i16(data, base + start + 2).to_i16_wrap(), source_glyph: glyph.to_u32_wrap() }) }
					$raw = $raw.append({
						kind: if duplicate {
							2
						} else {
							1
						},
						target,
						entry,
					})
				}
			}
			fallback = { kind: 0.U8, target: 0.U64, entry: TableColorImages.empty_entry }
			for glyph in 0..<glyph_count {
				if ($raw.get(glyph) ?? fallback).kind == 2 {
					var $path = []
					var $current = glyph
					var $steps = 0.U64
					while $steps <= glyph_count {
						$steps = $steps + 1
						value = $raw.get($current) ?? fallback
						if value.kind == 3 or value.kind == 0 {
							return TableColorImages.bad("sbix", value.entry.start)
						}
						if value.kind == 1 {
							break
						}
						# Current glyph indices are validated in the first pass.
						$raw = $raw.set($current, { ..value, kind: 3 }) ?? []
						$path = $path.append($current)
						$current = value.target
					}
					source = $raw.get($current) ?? fallback
					if source.kind != 1 {
						return TableColorImages.bad("sbix", base)
					}
					for index in $path {
						$raw = $raw.set(index, { kind: 1, target: $current, entry: { ..source.entry, first: index, last: index } }) ?? []
					}
				}
			}
			first_entry = $entries.len()
			for value in $raw {
				if value.kind == 1 {
					$entries = $entries.append(value.entry)
				}
			}
			$strikes = $strikes.append({ fact: Sbix({ ppem: ppem.to_u16_wrap(), ppi: ppi.to_u16_wrap(), draw_outlines: Bytes.u16(data, 2) == 3 }), start: first_entry, end: $entries.len() })
		}
		Ok({ data, entries: $entries, strike_records: $strikes })
	}

	line_metrics : List(U8), U64 -> LineMetrics
	line_metrics = |data, at| { ascender: TableColorImages.i8(data, at), descender: TableColorImages.i8(data, at + 1), width_max: Bytes.u8(data, at + 2).to_u8_wrap(), caret_slope_numerator: TableColorImages.i8(data, at + 3), caret_slope_denominator: TableColorImages.i8(data, at + 4), caret_offset: TableColorImages.i8(data, at + 5), min_origin_side_bearing: TableColorImages.i8(data, at + 6), min_advance_side_bearing: TableColorImages.i8(data, at + 7), max_before_baseline: TableColorImages.i8(data, at + 8), min_after_baseline: TableColorImages.i8(data, at + 9) }
	big_metrics : List(U8), U64 -> BitmapMetrics
	big_metrics = |data, at| { height: Bytes.u8(data, at).to_u8_wrap(), width: Bytes.u8(data, at + 1).to_u8_wrap(), horizontal: Present({ bearing_x: TableColorImages.i8(data, at + 2), bearing_y: TableColorImages.i8(data, at + 3), advance: Bytes.u8(data, at + 4).to_u16_wrap() }), vertical: Present({ bearing_x: TableColorImages.i8(data, at + 5), bearing_y: TableColorImages.i8(data, at + 6), advance: Bytes.u8(data, at + 7).to_u16_wrap() }) }
	empty_metrics : BitmapMetrics
	empty_metrics = { width: 0, height: 0, horizontal: Absent, vertical: Absent }

	read_cbdt : List(U8), List(U8), U64 -> Try(TableColorImages, Problem)
	read_cbdt = |locations, data, glyph_count| {
		if !Bytes.fits(0, 8, locations.len()) or Bytes.u32(locations, 0) != 0x30000 {
			return TableColorImages.bad("CBLC", 0)
		}
		if !Bytes.fits(0, 4, data.len()) or Bytes.u32(data, 0) != 0x30000 {
			return TableColorImages.bad("CBDT", 0)
		}
		count = Bytes.u32(locations, 4)
		if !Bytes.fits(8, count * 48, locations.len()) {
			return TableColorImages.bad("CBLC", 4)
		}
		var $entries = []
		var $strikes = List.with_capacity(count)
		var $work = 0.U64
		for strike in 0..<count {
			at = 8 + strike * 48
			array = Bytes.u32(locations, at)
			size = Bytes.u32(locations, at + 4)
			ranges = Bytes.u32(locations, at + 8)
			first = Bytes.u16(locations, at + 40)
			last = Bytes.u16(locations, at + 42)
			flags = Bytes.u8(locations, at + 47)
			if first > last or last >= glyph_count {
				return TableColorImages.bad("CBLC", at + 40)
			}
			if array < 8 + count * 48 or !Bytes.fits(array, size, locations.len()) or !Bytes.fits(0, ranges * 8, size) {
				return TableColorImages.bad("CBLC", at)
			}
			if Bytes.u8(locations, at + 44) == 0 or Bytes.u8(locations, at + 45) == 0 or flags == 0 or flags > 3 {
				return TableColorImages.bad("CBLC", at + 44)
			}
			depth = Bytes.u8(locations, at + 46)
			if depth != 1 and depth != 2 and depth != 4 and depth != 8 and depth != 32 {
				return TableColorImages.bad("CBLC", at + 46)
			}
			first_entry = $entries.len()
			var $previous = 0
			for r in 0..<ranges {
				record = array + r * 8
				lo = Bytes.u16(locations, record)
				hi = Bytes.u16(locations, record + 2)
				relative = Bytes.u32(locations, record + 4)
				if lo > hi or lo < first or hi > last or (r > 0 and lo <= $previous) {
					return TableColorImages.bad("CBLC", record)
				}
				if relative < ranges * 8 or !Bytes.fits(relative, 8, size) {
					return TableColorImages.bad("CBLC", record + 4)
				}
				sub = array + relative
				format = Bytes.u16(locations, sub)
				image_format = Bytes.u16(locations, sub + 2)
				image_base = Bytes.u32(locations, sub + 4)
				if image_base < 4 or image_base > data.len() {
					return TableColorImages.bad("CBLC", sub + 4)
				}
				if image_format < 17 or image_format > 19 {
					return TableColorImages.bad("CBLC", sub + 2)
				}
				available = array + size
				var $glyphs = []
				var $offsets = []
				var $shared = TableColorImages.empty_metrics
				if format == 1 or format == 3 {
					n = hi - lo + 1
					width = if format == 1 {
						4
					} else {
						2
					}
					if !Bytes.fits(sub + 8, (n + 1) * width, available) {
						return TableColorImages.bad("CBLC", sub + 8)
					}
					$work = $work + n
					if $work > (locations.len() + data.len()) * 8 {
						return TableColorImages.bad("CBLC", sub)
					}
					$glyphs = List.with_capacity(n)
					$offsets = List.with_capacity(n + 1)
					for i in 0..<(n + 1) {
						$offsets = $offsets.append(
							if width == 4 {
								Bytes.u32(locations, sub + 8 + i * 4)
							} else {
								Bytes.u16(locations, sub + 8 + i * 2)
							},
						)
						if i < n {
							$glyphs = $glyphs.append(lo + i)
						}
					}
				} else if format == 2 or format == 5 {
					if !Bytes.fits(sub + 8, 12, available) {
						return TableColorImages.bad("CBLC", sub + 8)
					}
					image_size = Bytes.u32(locations, sub + 8)
					if image_size == 0 {
						return TableColorImages.bad("CBLC", sub + 8)
					}
					$shared = TableColorImages.big_metrics(locations, sub + 12)
					n = if format == 2 {
						hi - lo + 1
					} else {
						if !Bytes.fits(sub + 20, 4, available) {
							return TableColorImages.bad("CBLC", sub + 20)
						}
						Bytes.u32(locations, sub + 20)
					}
					if n > hi - lo + 1 or (format == 5 and !Bytes.fits(sub + 24, n * 2, available)) {
						return TableColorImages.bad("CBLC", sub + 20)
					}
					if !Bytes.fits(image_base, n * image_size, data.len()) {
						return TableColorImages.bad("CBDT", image_base)
					}
					$work = $work + n
					if $work > (locations.len() + data.len()) * 8 {
						return TableColorImages.bad("CBLC", sub)
					}
					$glyphs = List.with_capacity(n)
					$offsets = List.with_capacity(n + 1)
					for i in 0..<(n + 1) {
						$offsets = $offsets.append(i * image_size)
						if i < n {
							$glyphs = $glyphs.append(
								if format == 2 {
									lo + i
								} else {
									Bytes.u16(locations, sub + 24 + i * 2)
								},
							)
						}
					}
				} else if format == 4 {
					if !Bytes.fits(sub + 8, 4, available) {
						return TableColorImages.bad("CBLC", sub + 8)
					}
					n = Bytes.u32(locations, sub + 8)
					if n > hi - lo + 1 or !Bytes.fits(sub + 12, (n + 1) * 4, available) {
						return TableColorImages.bad("CBLC", sub + 8)
					}
					$work = $work + n
					if $work > (locations.len() + data.len()) * 8 {
						return TableColorImages.bad("CBLC", sub)
					}
					$glyphs = List.with_capacity(n)
					$offsets = List.with_capacity(n + 1)
					for i in 0..<(n + 1) {
						$offsets = $offsets.append(Bytes.u16(locations, sub + 14 + i * 4))
						if i < n {
							$glyphs = $glyphs.append(Bytes.u16(locations, sub + 12 + i * 4))
						}
					}
				} else {
					return TableColorImages.bad("CBLC", sub)
				}
				if image_format == 19 and format != 2 and format != 5 {
					return TableColorImages.bad("CBLC", sub + 2)
				}
				if ($offsets.last() ?? 0) > data.len() - image_base {
					return TableColorImages.bad("CBDT", image_base)
				}
				var $last_glyph = 0
				for i in 0..<$glyphs.len() {
					glyph = $glyphs.get(i) ?? lo
					start = $offsets.get(i) ?? 0
					end = $offsets.get(i + 1) ?? 0
					if glyph < lo or glyph > hi or (i > 0 and glyph <= $last_glyph) {
						return TableColorImages.bad("CBLC", sub)
					}
					if end < start or !Bytes.fits(image_base + start, end - start, data.len()) {
						return TableColorImages.bad("CBDT", image_base + start)
					}
					if end > start {
						entry = TableColorImages.png_record(data, image_base + start, end - start, image_format, flags, $shared, glyph)?
						$entries = $entries.append(entry)
					}
					$last_glyph = glyph
				}
				$previous = hi
			}
			fact = ColorBitmap({ ppem_x: Bytes.u8(locations, at + 44).to_u8_wrap(), ppem_y: Bytes.u8(locations, at + 45).to_u8_wrap(), bit_depth: depth.to_u8_wrap(), flags: flags.to_u8_wrap(), first_glyph: first.to_u32_wrap(), last_glyph: last.to_u32_wrap(), horizontal: TableColorImages.line_metrics(locations, at + 16), vertical: TableColorImages.line_metrics(locations, at + 28) })
			$strikes = $strikes.append({ fact, start: first_entry, end: $entries.len() })
		}
		Ok({ data, entries: $entries, strike_records: $strikes })
	}

	png_record : List(U8), U64, U64, U64, U64, BitmapMetrics, U64 -> Try(Entry, Problem)
	png_record = |data, at, len, format, flags, shared, glyph| {
		metric_size = if format == 17 {
			5
		} else if format == 18 {
			8
		} else {
			0
		}
		if len < metric_size + 4 {
			return TableColorImages.bad("CBDT", at)
		}
		length = Bytes.u32(data, at + metric_size)
		if !Bytes.fits(metric_size + 4, length, len) {
			return TableColorImages.bad("CBDT", at + metric_size)
		}
		metrics = if format == 18 {
			TableColorImages.big_metrics(data, at)
		} else if format == 19 {
			shared
		} else {
			if flags != 1 and flags != 2 {
				return TableColorImages.bad("CBDT", at)
			}
			axis = { bearing_x: TableColorImages.i8(data, at + 2), bearing_y: TableColorImages.i8(data, at + 3), advance: Bytes.u8(data, at + 4).to_u16_wrap() }
			{
				height: Bytes.u8(data, at).to_u8_wrap(),
				width: Bytes.u8(data, at + 1).to_u8_wrap(),
				horizontal: if flags == 1 {
					Present(axis)
				} else {
					Absent
				},
				vertical: if flags == 2 {
					# Small vertical metrics store top then left, unlike the
					# big record. Expose both with x=left and y=top.
					Present({ bearing_x: axis.bearing_y, bearing_y: axis.bearing_x, advance: axis.advance })
				} else {
					Absent
				},
			}
		}
		Ok({ first: glyph, last: glyph, start: at + metric_size + 4, len: length, format: 0x706E6720, placement: Bitmap(metrics) })
	}
}
