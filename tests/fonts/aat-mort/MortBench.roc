import font.Font

## Native caller-side read/plan/query phases. Only public package APIs.
MortBench :: {}.{
	Prepared : { font : Font, plan : Font.ShapePlan, text : Str }
	prepare : List(U8), U64 -> Try(Prepared, Str)
	prepare = |bytes, count| {
		font = match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
			Ok(ready) => ready
			Err(problems) => return Err(Str.inspect(problems))
		}
		Ok({ font, plan: Font.plan(font, Font.ShapeOptions.{ script: "Latn" }), text: Str.join_with(List.repeat("a", count), "") })
	}
	reading : List(U8) -> I64
	reading = |bytes| match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
		Ok(font) => Font.glyph_count(font).to_i64()
		Err(problems) => crash Str.inspect(problems)
	}
	run : Prepared -> I64
	run = |prepared| {
		observed = Font.shape_planned(prepared.font, prepared.plan, prepared.text)
		var $sum = 0.I64
		for i in 0..<observed.glyphs.len() {
			advance = observed.advances.get(i) ?? { x: 0, y: 0 }
			offset = observed.offsets.get(i) ?? { x: 0, y: 0 }
			$sum = $sum + (observed.glyphs.get(i) ?? 0).to_i64() + advance.x.to_i64() + advance.y.to_i64() + offset.x.to_i64() + offset.y.to_i64() + (observed.clusters.get(i) ?? 0).to_i64_wrap() + (observed.flags.get(i) ?? 0).to_i64()
		}
		$sum
	}
}
