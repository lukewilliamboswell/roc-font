import font.Font
VariationBench :: {}.{
	Prepared : { font : Font, mode : U8 }
	prepare : List(U8) -> Prepared
	prepare = |bytes| {
		{ before: header, after: data } = bytes.split_first('\n') ?? { before: [], after: [] }
		font = match Font.from_bytes(data, Font.ReadOptions.{ strict: True }) {
			Ok(f) => f
			Err(ps) => crash Str.inspect(ps)
		}
		mode = if (header == "axis".to_utf8()) 1 else if (header == "avar".to_utf8()) 2 else 0
		{ font: if (mode > 0) font else Font.at(font, Font.Variation.{ axes: [{ tag: "wght", value: 1 }] }), mode }
	}
	run : Prepared -> U64
	run = |prepared| {
		if prepared.mode > 0 {
			moved = Font.at(prepared.font, Font.Variation.{ axes: if (prepared.mode == 1) [{ tag: "0000", value: 0.5 }] else [{ tag: "wght", value: 0.5 }, { tag: "wdth", value: 0.5 }] })
			Font.coordinates(moved).fold(0.U64, |sum, c| sum.plus_wrap(c.value.to_i64().to_u64_wrap()))
		} else Font.advance(prepared.font, 1).to_i64().to_u64_wrap()
	}
}
