import font.Font

## Caller font, explicit script and direction; preparation is outside timing.
GraphiteBench :: {}.{
	Prepared : { font : Font, plan : Font.ShapePlan, text : Str, script : Str, direction : Str }
	prepare : List(U8) -> Try(Prepared, Str)
	prepare = |bytes| {
		{ before: header, after: font_bytes } = bytes.split_first('\n') ?? return Err("missing benchmark header")
		fields = (Str.from_utf8(header) ?? return Err("header UTF8")).split_on(" ")
		match fields {
			[script, direction, count] => {
				copies = U64.from_str(count) ?? return Err("copy count")
				if copies > 4096 {
					return Err("copy count exceeds diagnostic bound")
				}
				piece = match script {
					"Latn" => "office á Tiếng Việt "
					"Mymr" => "မြန်မာ က္က င်္က "
					"Arab" => "بسم الله الرحمن الرحيم "
					_ => return Err("benchmark script")
				}
				font = Font.from_bytes(font_bytes, Font.ReadOptions.{}) ?? return Err("caller font rejected")
				plan = Font.plan(
					font,
					Font.ShapeOptions.{
						script,
						direction: match direction {
							"ltr" => LeftToRight
							"rtl" => RightToLeft
							_ => return Err("benchmark direction")
						},
					},
				)
				if Font.shaping_engine(plan) != Graphite {
					return Err("benchmark requires the actual Graphite backend")
				}
				Ok({ font, plan, text: Str.join_with(List.repeat(piece, copies), ""), script, direction })
			}
			_ => Err("header requires script direction copies")
		}
	}

	input_checksum : Prepared -> U64
	input_checksum = |prepared| prepared.text.to_utf8().fold(5381.U64, |sum, byte| sum.shl_wrap(5).plus_wrap(sum).plus_wrap(byte.to_u64()))

	run : Prepared -> Try(U64, U64)
	run = |prepared| {
		run = match Font.shape_checked(prepared.font, prepared.plan, prepared.text) {
			Ok(value) => value
			Err(_) => return Err(0)
		}
		var $sum = 0.U64
		for i in 0..<run.glyphs.len() {
			point = run.advances.get(i) ?? { x: 0, y: 0 }
			offset = run.offsets.get(i) ?? { x: 0, y: 0 }
			$sum = $sum.plus_wrap((run.glyphs.get(i) ?? 0).to_u64()).plus_wrap(run.clusters.get(i) ?? 0).plus_wrap(point.x.to_i64().to_u64_wrap()).plus_wrap(point.y.to_i64().to_u64_wrap()).plus_wrap(offset.x.to_i64().to_u64_wrap()).plus_wrap(offset.y.to_i64().to_u64_wrap())
		}
		Ok($sum)
	}
}
