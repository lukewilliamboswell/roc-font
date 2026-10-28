import Sfnt
import Bytes

## Checked vertical advances and top bearings, with the last-long-metric rule.
TableVmtx :: {}.{

	Metrics : { advances : List(U16), bearings : List(I16) }

	from_tables : List(U8), List(Sfnt.Table), U64, U64 -> Try(Metrics, [MissingTable(Str), BadTable({ table : Str, offset : U32 })])
	from_tables = |bytes, tables, metric_count, glyph_count| {
		# The header proves at least one long metric, even for an empty font.
		if metric_count == 0 or metric_count > glyph_count {
			return Err(Sfnt.bad("vmtx", 0))
		}
		data = Sfnt.required(bytes, tables, "vmtx", 4 * metric_count + 2 * (glyph_count - metric_count))?.data
		var $advances = List.with_capacity(glyph_count)
		var $bearings = List.with_capacity(glyph_count)
		for glyph in 0..<glyph_count {
			$advances = $advances.append(Bytes.u16(data, 4 * glyph.min(metric_count - 1)).to_u16_wrap())
			at = if (glyph < metric_count) 4 * glyph + 2 else 4 * metric_count + 2 * (glyph - metric_count)
			$bearings = $bearings.append(Bytes.i16(data, at).to_i16_wrap())
		}
		Ok({ advances: $advances, bearings: $bearings })
	}
}

metrics = [3, 232, 0, 50, 4, 176, 255, 246, 0, 20]

tables = [{ tag: Sfnt.tag_of("vmtx"), offset: 0, length: 10 }]
expect TableVmtx.from_tables(metrics, tables, 2, 3) == Ok({ advances: [1000, 1200, 1200], bearings: [50, -10, 20] })
expect TableVmtx.from_tables(metrics.drop_last(1), tables, 2, 3) == Err(Sfnt.bad("vmtx", 0))
expect TableVmtx.from_tables(metrics, tables, 4, 3) == Err(Sfnt.bad("vmtx", 0))
expect TableVmtx.from_tables(metrics, tables, 0, 3) == Err(Sfnt.bad("vmtx", 0))
