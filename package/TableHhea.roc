import Sfnt
import Bytes

## The horizontal header (`hhea`): ascender, descender, and how many glyphs
## have their own advance width in `hmtx` (`numberOfHMetrics`).
##
## Internal. A font with no long horizontal metrics is refused, since every
## glyph's advance comes from one.
TableHhea :: {}.{

	from_tables : List(U8), List(Sfnt.Table) -> Try({ ascent : F64, descent : F64, metric_count : U64 }, [MissingTable(Str), BadTable(Str)])
	from_tables = |bytes, tables| {
		hhea = Sfnt.required(bytes, tables, "hhea", 36)?
		count = Bytes.u16(hhea, 34)
		if count == 0 {
			Err(BadTable("hhea"))
		} else {
			Ok({ ascent: Bytes.i16(hhea, 4).to_f64(), descent: Bytes.i16(hhea, 6).to_f64(), metric_count: count })
		}
	}
}
