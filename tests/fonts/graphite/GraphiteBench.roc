import font.Font

## Caller font, explicit script and direction; preparation is outside timing.
GraphiteBench :: {}.{
	Prepared : { font : Font, plan : Font.ShapePlan, text : Str, script : Str, direction : Str }
	prepare : List(U8) -> Try(Prepared, Str)
	prepare = |bytes| {
		{ before: header, after: font_bytes } = bytes.split_first('\n') ?? return Err("missing benchmark header")
		header_text = Str.from_utf8(header) ?? return Err("header UTF8")
		fields = if (header_text.contains("\t")) header_text.split_on("\t") else header_text.split_on(" ")
		options = match fields {
			[raw_script, raw_direction, raw_count] => {
				raw_piece = match raw_script {
					"Latn" => "office á Tiếng Việt "
					"Mymr" => "မြန်မာ က္က င်္က "
					"Arab" => "بسم الله الرحمن الرحيم "
					_ => return Err("benchmark script requires explicit text")
				}
				{ script: raw_script, direction: raw_direction, count: raw_count, piece: raw_piece }
			}
			[raw_script, raw_direction, raw_count, raw_piece] => { script: raw_script, direction: raw_direction, count: raw_count, piece: raw_piece }
			_ => return Err("header requires script direction copies and optional text")
		}
		{ script, direction, count, piece } = options
		copies = U64.from_str(count) ?? return Err("copy count")
		if copies > 4096 {
			return Err("copy count exceeds diagnostic bound")
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

	input_checksum : Prepared -> U64
	input_checksum = |prepared| prepared.text.to_utf8().fold(5381.U64, |sum, byte| sum.shl_wrap(5).plus_wrap(sum).plus_wrap(byte.to_u64()))

	mix : U64, U64 -> U64
	mix = |hash, value| hash.bitwise_xor(value).times_wrap(1099511628211)

	run : Prepared -> Try(U64, U64)
	run = |prepared| {
		run = match Font.shape_checked(prepared.font, prepared.plan, prepared.text) {
			Ok(value) => value
			Err(_) => return Err(0)
		}
		var $sum = GraphiteBench.mix(14695981039346656037, run.glyphs.len())
		for i in 0..<run.glyphs.len() {
			point = run.advances.get(i) ?? { x: 0, y: 0 }
			offset = run.offsets.get(i) ?? { x: 0, y: 0 }
			$sum = GraphiteBench.mix($sum, (run.glyphs.get(i) ?? 0).to_u64())
			$sum = GraphiteBench.mix($sum, run.clusters.get(i) ?? 0)
			$sum = GraphiteBench.mix($sum, point.x.to_i64().to_u64_wrap())
			$sum = GraphiteBench.mix($sum, point.y.to_i64().to_u64_wrap())
			$sum = GraphiteBench.mix($sum, offset.x.to_i64().to_u64_wrap())
			$sum = GraphiteBench.mix($sum, offset.y.to_i64().to_u64_wrap())
			$sum = GraphiteBench.mix($sum, if (Font.is_unsafe_to_break(run.flags.get(i) ?? 0)) 1 else 0)
		}
		Ok($sum)
	}
}
