import font.Font

## The operations every benchmark program measures, shared by the timing
## driver (`font.roc`) and the allocation diagnostic (`alloc.roc`).
##
## A case file is two header lines and then data:
##
## ```
## <operation>\n
## <font length in bytes>\n
## <font bytes><text bytes>
## ```
##
## `prepare` does everything that is not the operation itself (reading the
## font for queries, decoding the text into code points, mapping code points
## to glyphs), so the timed region and the measured allocation region hold
## only the operation. `run` performs it once and folds the whole result into
## a checksum, so no work can be skipped.
##
## Operations:
##
## - `read`: `Font.from_bytes` on the font bytes.
## - `cmap`: `Font.glyph` for every code point of the text.
## - `advance`: `Font.advance` for the glyph of every code point.
## - `kerning`: `Font.kerning` over the glyphs of the whole text.
## - `shape`: the whole pipeline from text: decode UTF-8, map characters to
##   glyphs, `Font.substitute`, then advances and `Font.kerning`.
FontBench :: {}.{

	Prepared : { op : Str, bytes : List(U8), font : Font, text : List(U8), code_points : List(U32), glyphs : List(U64) }

	prepare : List(U8) -> Try(Prepared, Str)
	prepare = |input| {
		{ before: op_bytes, after: rest } = input.split_first('\n') ?? { before: [], after: [] }
		{ before: length_bytes, after: data } = rest.split_first('\n') ?? { before: [], after: [] }
		op = Str.from_utf8(op_bytes) ?? ""
		length = U64.from_str(Str.from_utf8(length_bytes) ?? "") ?? 0
		if length > data.len() {
			Err("the case file is shorter than its font length")
		} else {
			{ before: bytes, others: text } = data.split_at(length)
			if op == "read" {
				Ok({ op, bytes, font: Font.empty, text, code_points: [], glyphs: [] })
			} else {
				match Font.from_bytes(bytes) {
					Err(problems) => Err("the font could not be read: ${Str.inspect(problems)}")
					Ok(font) => {
						code_points = FontBench.decode_utf8(text).map(|c| c.code_point)
						glyphs = code_points.map(|cp| Font.glyph(font, cp) ?? 0)
						if op == "cmap" or op == "advance" or op == "kerning" or op == "shape" {
							Ok({ op, bytes, font, text, code_points, glyphs })
						} else {
							Err("unknown operation ${op}")
						}
					}
				}
			}
		}
	}

	## One operation; `Ok` with its checksum when it succeeded.
	run : Prepared -> Try(U64, U64)
	run = |p|
		match p.op {
			"read" =>
				match Font.from_bytes(p.bytes) {
					Ok(font) => Ok(Font.glyph_total(font) + F64.to_u64_wrap(Font.units_per_em(font)))
					Err(problems) => Err(problems.len())
				}
			"cmap" => {
				var $sum = 0.U64
				for cp in p.code_points {
					match Font.glyph(p.font, cp) {
						Ok(g) => {
							$sum = $sum + g + 1
						}
						Err(Missing) => {}
					}
				}
				Ok($sum)
			}
			"advance" => {
				var $sum = 0.U64
				for g in p.glyphs {
					$sum = $sum + F64.to_u64_wrap(Font.advance(p.font, g))
				}
				Ok($sum)
			}
			"kerning" => Ok(FontBench.sum_f64(Font.kerning(p.font, p.glyphs)))
			"shape" => Ok(FontBench.shape(p.font, p.text))
			_ => Err(0)
		}

	shape : Font, List(U8) -> U64
	shape = |font, text| {
		items = FontBench.decode_utf8(text).map(|c| { glyph: Font.glyph(font, c.code_point) ?? 0, cluster: c.offset })
		shaped = Font.substitute(font, items)
		glyphs = shaped.map(|item| item.glyph)
		kerned = Font.kerning(font, glyphs)
		var $sum = 0.U64
		for item in shaped {
			$sum = $sum.plus_wrap(item.glyph + item.cluster + F64.to_u64_wrap(Font.advance(font, item.glyph)))
		}
		$sum.plus_wrap(FontBench.sum_f64(kerned))
	}

	# Kerning adjustments are whole font units, often negative; fold them
	# with wrapping so the checksum is total.
	sum_f64 : List(F64) -> U64
	sum_f64 = |values| {
		var $sum = 0.I64
		for v in values {
			$sum = $sum.plus_wrap(F64.to_i64_wrap(v))
		}
		I64.to_u64_wrap($sum)
	}

	## Code points of UTF-8 text with the byte offset each starts at. A byte
	## that does not start a well-formed sequence decodes to U+FFFD.
	decode_utf8 : List(U8) -> List({ code_point : U32, offset : U64 })
	decode_utf8 = |bytes| {
		count = bytes.len()
		var $out = List.with_capacity(count)
		var $i = 0
		while $i < count {
			b0 = (bytes.get($i) ?? 0).to_u32()
			width = if (b0 < 0x80) 1 else if (b0 >= 0xC2 and b0 < 0xE0) 2 else if (b0 >= 0xE0 and b0 < 0xF0) 3 else if (b0 >= 0xF0 and b0 < 0xF5) 4 else 0
			if width == 0 or $i + width > count {
				$out = $out.append({ code_point: 0xFFFD, offset: $i })
				$i = $i + 1
			} else {
				var $cp = if (width == 1) b0 else if (width == 2) b0.bitwise_and(0x1F) else if (width == 3) b0.bitwise_and(0x0F) else b0.bitwise_and(0x07)
				var $ok = True
				var $k = 1
				while $k < width {
					b = (bytes.get($i + $k) ?? 0).to_u32()
					if b.bitwise_and(0xC0) != 0x80 {
						$ok = False
					}
					$cp = $cp * 64 + b.bitwise_and(0x3F)
					$k = $k + 1
				}
				min = if (width == 2) 0x80 else if (width == 3) 0x800 else 0x10000
				if $ok and (width == 1 or $cp >= min) and $cp <= 0x10FFFF and !($cp >= 0xD800 and $cp <= 0xDFFF) {
					$out = $out.append({ code_point: $cp, offset: $i })
					$i = $i + width
				} else {
					$out = $out.append({ code_point: 0xFFFD, offset: $i })
					$i = $i + 1
				}
			}
		}
		$out
	}
}
