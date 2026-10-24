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
## - `kerning`: pair positioning alone over the glyphs of the whole text:
##   `Font.shape_planned` with every default substitution turned off, so
##   the run keeps the mapped glyphs; the checksum folds each glyph's
##   advance change.
## - `shape`: `Font.shape_planned` on the text with the default features,
##   the plan made in `prepare`; the checksum folds glyphs, clusters and
##   advances.
##
## Queries measure at the font's default instance (every axis at its
## default), as the operations did before variations, so checksums stay
## comparable across versions and with comparators.
FontBench :: {}.{

	Prepared : { op : Str, bytes : List(U8), font : [Ready(Font), NotRead], text : Str, code_points : List(U32), glyphs : List(U32), plan : [Planned(Font.ShapePlan), NotPlanned] }

	## The default substitutions, turned off for the `kerning` operation.
	no_substitutions : List(Font.Feature)
	no_substitutions = ["rvrn", "ltra", "ltrm", "ccmp", "locl", "rlig", "liga", "clig", "calt", "rclt", "abvm", "blwm"].map(|tag| Font.Feature.{ tag, value: 0 })

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
			# Invalid UTF-8 decodes to U+FFFD, in the text the shaping operations
			# see as in the code points.
			decoded = FontBench.decode_utf8(text)
			code_points = decoded.map(|c| c.code_point)
			text_str = Str.from_utf8_lossy(text)
			if op == "read" {
				Ok({ op, bytes, font: NotRead, text: text_str, code_points: [], glyphs: [], plan: NotPlanned })
			} else {
				match Font.from_bytes(bytes, Font.ReadOptions.{}) {
					Err(problems) => Err("the font could not be read: ${Str.inspect(problems)}")
					Ok(read) => {
						font = Font.at(read, Font.Variation.{ axes: Font.axes(read).map(|a| { tag: a.tag, value: a.default }) })
						glyphs = code_points.map(|cp| Font.glyph(font, cp) ?? 0)
						if op == "cmap" or op == "advance" {
							Ok({ op, bytes, font: Ready(font), text: text_str, code_points, glyphs, plan: NotPlanned })
						} else if op == "kerning" {
							plan = Font.plan(font, Font.ShapeOptions.{ features: FontBench.no_substitutions })
							Ok({ op, bytes, font: Ready(font), text: text_str, code_points, glyphs, plan: Planned(plan) })
						} else if op == "shape" {
							Ok({ op, bytes, font: Ready(font), text: text_str, code_points, glyphs, plan: Planned(Font.plan(font, Font.ShapeOptions.{})) })
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
		match (p.op, p.font, p.plan) {
			("read", _, _) =>
				match Font.from_bytes(p.bytes, Font.ReadOptions.{}) {
					Ok(font) => Ok(Font.glyph_count(font).to_u64() + Font.units_per_em(font).to_u64())
					Err(problems) => Err(problems.len())
				}
			("cmap", Ready(font), _) => {
				var $sum = 0.U64
				for cp in p.code_points {
					match Font.glyph(font, cp) {
						Ok(g) => {
							$sum = $sum + g.to_u64() + 1
						}
						Err(Missing) => {}
					}
				}
				Ok($sum)
			}
			("advance", Ready(font), _) => {
				var $sum = 0.U64
				for g in p.glyphs {
					$sum = $sum + Font.advance(font, g).to_i64().to_u64_wrap()
				}
				Ok($sum)
			}
			("kerning", Ready(font), Planned(plan)) => Ok(FontBench.kerning(font, plan, p.code_points))
			("shape", Ready(font), Planned(plan)) => Ok(FontBench.shape(font, plan, p.text))
			_ => Err(0)
		}

	# The kerning of the code points' glyphs: each glyph's advance change,
	# folded with wrapping (kerning is often negative).
	kerning : Font, Font.ShapePlan, List(U32) -> U64
	kerning = |font, plan, code_points| {
		shaped = Font.shape_scalars(font, plan, code_points.map_with_index(|scalar, i| { scalar, offset: i.to_u32_wrap() }))
		var $sum = 0.I64
		for i in 0..<shaped.glyphs.len() {
			g = shaped.glyphs.get(i) ?? 0
			adv = (shaped.advances.get(i) ?? { x: 0, y: 0 }).x
			$sum = $sum.plus_wrap((adv - Font.advance(font, g)).to_i64())
		}
		$sum.to_u64_wrap()
	}

	shape : Font, Font.ShapePlan, Str -> U64
	shape = |font, plan, text| {
		shaped = Font.shape_planned(font, plan, text)
		var $sum = 0.U64
		for i in 0..<shaped.glyphs.len() {
			g = (shaped.glyphs.get(i) ?? 0).to_u64()
			c = (shaped.clusters.get(i) ?? 0).to_u64()
			adv = (shaped.advances.get(i) ?? { x: 0, y: 0 }).x.to_i64().to_u64_wrap()
			$sum = $sum.plus_wrap(g + c).plus_wrap(adv)
		}
		$sum
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
