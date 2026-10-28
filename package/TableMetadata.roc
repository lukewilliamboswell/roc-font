import Bytes
import Sfnt

## Original table bytes and design metrics of an already checked sfnt face.
## Internal. The table directory and required metrics have been validated
## before construction. Values here describe the stored design, independent
## of the location selected for shaping.
TableMetadata := {
	bytes : List(U8),
	tables : List(Sfnt.Table),
	glyph_count : U64,
	metric_count : U64,
}.{

	## Original bytes of a table. Unknown and dropped tables remain original
	## bytes, not a sanitized font. A tag must contain exactly four bytes.
	table : TableMetadata, Str -> [Present(List(U8)), Absent]
	table = |source, tag|
		if tag.to_utf8().len() != 4 {
			Absent
		} else {
			match Sfnt.table(source.bytes, source.tables, tag, 0) {
				Found(data) => Present(data)
				_ => Absent
			}
		}

	## Original table directory, in file order; tags are unsigned big-endian
	## numbers so even non-text tags retain their exact bytes.
	directory : TableMetadata -> List({ tag : U32, offset : U32, length : U32 })
	directory = |source| source.tables.map(|t| { tag: t.tag.to_u32_wrap(), offset: t.offset.to_u32_wrap(), length: t.length.to_u32_wrap() })

	embedding_flags : TableMetadata -> [Present(U16), Absent]
	embedding_flags = |source|
		match TableMetadata.table(source, "OS/2") {
			Present(data) => Present(Bytes.u16(data, 8).to_u16_wrap())
			Absent => Absent
		}

	left_side_bearing : TableMetadata, U64 -> [Present(I32), Absent]
	left_side_bearing = |source, glyph|
		if glyph >= source.glyph_count {
			Absent
		} else {
			match TableMetadata.table(source, "hmtx") {
				Present(data) => {
					long = source.metric_count.min(source.glyph_count)
					at = if glyph < long {
						4 * glyph + 2
					} else {
						4 * long + 2 * (glyph - long)
					}
					Present(Bytes.i16(data, at).to_i32_wrap())
				}
				Absent => Absent
			}
		}

	bounds : TableMetadata -> { x_min : I32, y_min : I32, x_max : I32, y_max : I32 }
	bounds = |source| {
		# Every successfully read face has a checked head of at least 54 bytes.
		data = match TableMetadata.table(source, "head") {
			Present(found) => found
			Absent => []
		}
		{ x_min: Bytes.i16(data, 36).to_i32_wrap(), y_min: Bytes.i16(data, 38).to_i32_wrap(), x_max: Bytes.i16(data, 40).to_i32_wrap(), y_max: Bytes.i16(data, 42).to_i32_wrap() }
	}
}
