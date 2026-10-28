import font.Font

## Pure reusable work for matched native timing and allocation runs.
AatBench :: {}.{
	Prepared : { font : Font, plan : Font.ShapePlan, text : Str, script : Str }
	prepare : List(U8) -> Try(Prepared, Str)
	prepare = |bytes| {
		{ before: header, after: font_bytes } = bytes.split_first('\n') ?? { before: [], after: [] }
		mode = header.first() ?? '0'
		copies = (U64.from_str(Str.from_utf8(header.drop_first(1)) ?? "") ?? 1).min(4096)
		font = Font.from_bytes(font_bytes, Font.ReadOptions.{ strict: True }) ?? crash "benchmark fixture rejected"
		script = if (mode == '6') "Taml" else "Latn"
		piece = if (mode == '6') "தமிழ் மொழி" else if (mode == '5') "a\u(0301)b" else "ab"
		Ok({ font, script, plan: Font.plan(font, Font.ShapeOptions.{ script, direction: LeftToRight, point_size: 24 }), text: Str.join_with(List.repeat(piece, copies), "") })
	}
	input_checksum : Prepared -> U64
	input_checksum = |prepared| prepared.text.to_utf8().fold(5381.U64, |sum, byte| sum.shl_wrap(5).plus_wrap(sum).plus_wrap(byte.to_u64()))
	run : Prepared -> Try(U64, U64)
	run = |prepared| {
		glyph_run = Font.shape_planned(prepared.font, prepared.plan, prepared.text)
		var $sum = 0.U64
		for i in 0..<glyph_run.glyphs.len() {
			advance = glyph_run.advances.get(i) ?? { x: 0, y: 0 }
			offset = glyph_run.offsets.get(i) ?? { x: 0, y: 0 }
			$sum = $sum.plus_wrap((glyph_run.glyphs.get(i) ?? 0).to_u64()).plus_wrap(glyph_run.clusters.get(i) ?? 0).plus_wrap(advance.x.to_i64().to_u64_wrap()).plus_wrap(advance.y.to_i64().to_u64_wrap()).plus_wrap(offset.x.to_i64().to_u64_wrap()).plus_wrap(offset.y.to_i64().to_u64_wrap())
		}
		Ok($sum)
	}
}
