import font.Font

## Shared pure work for native timing and allocation diagnostics.
ComplexBench :: {}.{
	Prepared : { font : Font, plan : Font.ShapePlan, text : Str }
	prepare : List(U8) -> Try(Prepared, Str)
	prepare = |bytes| {
		{ before: header, after: font_bytes } = bytes.split_first('\n') ?? { before: [], after: [] }
		copies = (U64.from_str(Str.from_utf8(header) ?? "") ?? 1).min(4096)
		font = match Font.from_bytes(font_bytes, Font.ReadOptions.{}) {
			Ok(value) => value
			Err(problems) => crash Str.inspect(problems)
		}
		Ok({ font, plan: Font.plan(font, Font.ShapeOptions.{ script: "Deva", language: "hi" }), text: Str.join_with(List.repeat("र्कि क्षिं हिन्दी ", copies), "") })
	}
	run : Prepared -> Try(U64, U64)
	run = |prepared| {
		glyph_run = Font.shape_planned(prepared.font, prepared.plan, prepared.text)
		var $sum = 0.U64
		for i in 0..<glyph_run.glyphs.len() {
			point = glyph_run.advances.get(i) ?? { x: 0, y: 0 }
			offset = glyph_run.offsets.get(i) ?? { x: 0, y: 0 }
			$sum = $sum.plus_wrap((glyph_run.glyphs.get(i) ?? 0).to_u64()).plus_wrap(glyph_run.clusters.get(i) ?? 0).plus_wrap(point.x.to_i64().to_u64_wrap()).plus_wrap(point.y.to_i64().to_u64_wrap()).plus_wrap(offset.x.to_i64().to_u64_wrap()).plus_wrap(offset.y.to_i64().to_u64_wrap())
		}
		Ok($sum)
	}
}
