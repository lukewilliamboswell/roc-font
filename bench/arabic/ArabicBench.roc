import font.Font

## Shared pure work for native timing and allocation diagnostics.
ArabicBench :: {}.{
	Prepared : { font : Font, plan : Font.ShapePlan, text : Str, script : Str }
	prepare : List(U8) -> Try(Prepared, Str)
	prepare = |bytes| {
		{ before: header, after: remaining } = bytes.split_first('\n') ?? { before: [], after: [] }
		copies = (U64.from_str(Str.from_utf8(header) ?? "") ?? 1).min(4096)
		{ before: script_bytes, after: font_bytes } = remaining.split_first('\n') ?? { before: [], after: [] }
		script = Str.from_utf8(script_bytes) ?? ""
		if script != "Arab" and script != "Syrc" {
			return Err("expected Arab or Syrc header")
		}
		font = match Font.from_bytes(font_bytes, Font.ReadOptions.{}) {
			Ok(value) => value
			Err(problems) => crash Str.inspect(problems)
		}
		piece = if (script == "Syrc") "\u(070F)ܐܒܕܪ " else "ببب لاب "

		Ok({ font, script, plan: Font.plan(font, Font.ShapeOptions.{ script, direction: RightToLeft }), text: Str.join_with(List.repeat(piece, copies), "") })
	}
	input_checksum : Prepared -> U64
	input_checksum = |prepared| prepared.text.to_utf8().fold(5381.U64, |sum, byte| sum.shl_wrap(5).plus_wrap(sum).plus_wrap(byte.to_u64()))

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
