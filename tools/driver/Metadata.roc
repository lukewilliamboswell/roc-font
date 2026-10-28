import rf.Font

## Stable notation for the original font facts used by PDF consumers.
Metadata :: {}.{
	serialize : Font -> Str
	serialize = |font| {
		name = |value| match value {
			Ok(text) => Str.join_with(text.to_utf8().map(|b| b.to_u64().to_str()), ",")
			Err(Missing) => "-"
		}
		embedding = match Font.embedding_flags(font) {
			Present(flags) => flags.to_str()
			Absent => "-"
		}
		b = Font.stored_bounds(font)
		h = Font.stored_header_metrics(font)
		var $bearings = []
		for id in 0..<Font.glyph_count(font) {
			$bearings = $bearings.append(
				match Font.stored_left_side_bearing(font, id) {
					Present(value) => value.to_str()
					Absent => "-"
				},
			)
		}
		var $tables = []
		for entry in Font.tables(font) {
			tag_bytes = [entry.tag.shr_zf_wrap(24), entry.tag.shr_zf_wrap(16), entry.tag.shr_zf_wrap(8), entry.tag].map(|n| n.bitwise_and(255).to_u8_wrap())
			# The fixture corpus uses conventional ASCII table tags.
			tag = Str.from_utf8(tag_bytes) ?? ""
			hash = match Font.table_bytes(font, tag) {
				Present(data) => data.fold(14695981039346656037.U64, |acc, byte| (acc.bitwise_xor(byte.to_u64()).to_u128() * 1099511628211).to_u64_wrap())
				Absent => 0
			}
			$tables = $tables.append("${entry.tag.to_str()},${entry.offset.to_str()},${entry.length.to_str()},${hash.to_str()}")
		}
		"metadata:${name(Font.legacy_family_name(font))};${name(Font.full_name(font))};${name(Font.postscript_name(font))};${embedding};${b.x_min.to_str()},${b.y_min.to_str()},${b.x_max.to_str()},${b.y_max.to_str()};${h.ascent.to_str()},${h.descent.to_str()},${h.line_gap.to_str()};${Str.join_with($bearings, ",")};${Str.join_with($tables, "|")}"
	}
}
