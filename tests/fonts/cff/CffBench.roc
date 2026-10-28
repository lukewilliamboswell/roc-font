import font.Font

## Dedicated caller work: an already read CFF font, glyph2, and either
## cubic path extraction or control-point extents. A checksum consumes
## every coordinate so the native optimizer cannot discard geometry.
CffBench :: {}.{
	read : List(U8) -> Try(Font, Str)
	read = |bytes| match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
		Ok(font) => Ok(font)
		Err(problems) => Err(Str.inspect(problems))
	}
	query : Font, U8 -> F64
	query = |font, mode| {
		if mode == 1 {
			match Font.extents(font, 2) {
				Extents(box) => box.x_min.to_f64() + box.x_max.to_f64() + box.y_min.to_f64() + box.y_max.to_f64()
				_ => 0
			}
		} else {
			var $sum = 0.F64
			match Font.outline(font, 2) {
				Unknown => {}
				Outline(commands) => for command in commands {
					$sum = $sum + match command {
						MoveTo(point) | LineTo(point) => point.x + point.y
						QuadraticTo(curve) => curve.control.x + curve.control.y + curve.end.x + curve.end.y
						CubicTo(curve) => curve.control1.x + curve.control1.y + curve.control2.x + curve.control2.y + curve.end.x + curve.end.y
						Close => 0
					}
				}
			}
			$sum
		}
	}
	reading : List(U8) -> F64
	reading = |bytes| match CffBench.read(bytes) {
		Ok(font) => Font.glyph_count(font).to_f64()
		Err(message) => crash message
	}
}
