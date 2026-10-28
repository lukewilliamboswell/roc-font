import font.Font
AatPositionBench :: {}.{
	Prepared : { font : Font, plan : Font.ShapePlan, text : Str }
	prepare : List(U8) -> Prepared
	prepare = |bytes| {
		{ before: header, after: data } = bytes.split_first('\n') ?? { before: [], after: [] }
		copies = (U64.from_str(Str.from_utf8(header) ?? "") ?? 1).min(4096)
		font = match Font.from_bytes(data, Font.ReadOptions.{ strict: True }) {
			Ok(f) => f
			Err(ps) => crash Str.inspect(ps)
		}
		{ font, plan: Font.plan(font, Font.ShapeOptions.{ script: "Latn", language: "en", direction: LeftToRight }), text: Str.join_with(List.repeat("ab", copies), "") }
	}
	run : Prepared -> U64
	run = |p| {
		run = Font.shape_planned(p.font, p.plan, p.text)
		var $sum = 0.U64
		for i in 0..<run.glyphs.len() {
			advance = run.advances.get(i) ?? { x: 0, y: 0 }
			offset = run.offsets.get(i) ?? { x: 0, y: 0 }
			$sum = $sum.plus_wrap((run.glyphs.get(i) ?? 0).to_u64()).plus_wrap(run.clusters.get(i) ?? 0).plus_wrap(advance.x.to_i64().to_u64_wrap()).plus_wrap(advance.y.to_i64().to_u64_wrap()).plus_wrap(offset.x.to_i64().to_u64_wrap()).plus_wrap(offset.y.to_i64().to_u64_wrap())
		}
		$sum
	}
}
