import Sfnt
import Bytes

## TrueType outlines (`glyf`, located through `loca`): the horizontal extent
## of each glyph, from the `xMin` and `xMax` of its glyph header. Outlines
## themselves are not read.
##
## Internal. A glyph with an empty or too-short entry has no extent, stored
## as `left` greater than `right`. A font without both tables (CFF
## outlines) has no extents. A `loca` too short for every glyph, or an entry
## that runs backwards or past `glyf`, makes `loca` a bad table.
TableGlyf :: {}.{

	from_tables : List(U8), List(Sfnt.Table), Bool, U64 -> Try(List({ left : I16, right : I16 }), [BadTable(Str)])
	from_tables = |bytes, tables, long_offsets, count_of_glyphs| {
		none = { left: 1, right: 0 }
		match (Sfnt.table(bytes, tables, "loca", 0), Sfnt.table(bytes, tables, "glyf", 0)) {
			(Bad, _) => Err(BadTable("loca"))
			(_, Bad) => Err(BadTable("glyf"))
			(Found(loca), Found(glyf)) => {
				size = if (long_offsets) 4 else 2
				if !Bytes.fits(0, size * (count_of_glyphs + 1), loca.len()) {
					Err(BadTable("loca"))
				} else {
					offset = |g| if (long_offsets) Bytes.u32(loca, 4 * g) else 2 * Bytes.u16(loca, 2 * g)
					var $ink = List.with_capacity(count_of_glyphs)
					var $bad = False
					for g in 0..<count_of_glyphs {
						start = offset(g)
						end = offset(g + 1)
						if end < start or end > glyf.len() {
							$bad = True
							$ink = $ink.append(none)
						} else if end - start >= 10 {
							$ink = $ink.append({ left: Bytes.i16(glyf, start + 2).to_i16_wrap(), right: Bytes.i16(glyf, start + 6).to_i16_wrap() })
						} else {
							$ink = $ink.append(none)
						}
					}
					if ($bad) Err(BadTable("loca")) else Ok($ink)
				}
			}
			_ => Ok(List.repeat(none, count_of_glyphs))
		}
	}
}
