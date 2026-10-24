import Sfnt
import Bytes

## TrueType outlines (`glyf`, located through `loca`): the bounding box of
## each glyph at the default location, as HarfBuzz reports it without
## variations: the glyph header's height and width, placed with its left
## edge at the glyph's left side bearing in `hmtx` (or at `xMin` for a
## glyph `hmtx` has no bearing for). Outlines themselves are not read here
## (`TableGlyfPoints` reads them for variable fonts).
##
## Internal. A glyph with an empty or too-short entry, or no contours, has
## no box, stored as `x_min` greater than `x_max`. A font without both
## tables (CFF outlines) has no boxes. A `loca` too short for every glyph, or an entry that runs
## backwards or past `glyf`, makes `loca` a bad table; the problem's offset
## is the first bad entry's.
TableGlyf :: {}.{

	Bounds : { x_min : I32, y_min : I32, x_max : I32, y_max : I32 }

	none : Bounds
	none = { x_min: 1, y_min: 0, x_max: 0, y_max: 0 }

	## The boxes of `count_of_glyphs` glyphs, with `metric_count` long
	## metrics in `hmtx` (from `hhea`).
	from_tables : List(U8), List(Sfnt.Table), Bool, U64, U64 -> Try(List(Bounds), [BadTable({ table : Str, offset : U32 })])
	from_tables = |bytes, tables, long_offsets, count_of_glyphs, metric_count| {
		# `hmtx` (reading has checked it), found by its tag as a number.
		var $hmtx = []
		for t in tables {
			if t.tag == 0x686D7478 and Bytes.fits(t.offset, t.length, bytes.len()) and $hmtx.is_empty() {
				$hmtx = bytes.sublist({ start: t.offset, len: t.length })
			}
		}
		hmtx = $hmtx
		long = metric_count.min(count_of_glyphs)
		match (Sfnt.located(bytes, tables, "loca", 0), Sfnt.located(bytes, tables, "glyf", 0)) {
			(Bad(at), _) => Err(Sfnt.bad("loca", at))
			(_, Bad(at)) => Err(Sfnt.bad("glyf", at))
			(Found(loca_found), Found({ data: glyf, offset: _ })) => {
				loca = loca_found.data
				size = if (long_offsets) 4 else 2
				if !Bytes.fits(0, size * (count_of_glyphs + 1), loca.len()) {
					Err(Sfnt.bad("loca", loca_found.offset))
				} else {
					offset = |g| if (long_offsets) Bytes.u32(loca, 4 * g) else 2 * Bytes.u16(loca, 2 * g)
					var $boxes = List.with_capacity(count_of_glyphs)
					var $bad_at = 0
					for g in 0..<count_of_glyphs {
						start = offset(g)
						end = offset(g + 1)
						if end < start or end > glyf.len() {
							if $bad_at == 0 {
								$bad_at = loca_found.offset + size * (g + 1)
							}
							$boxes = $boxes.append(TableGlyf.none)
						} else if end - start >= 10 and Bytes.u16(glyf, start) != 0 {
							x0 = Bytes.i16(glyf, start + 2)
							y0 = Bytes.i16(glyf, start + 4)
							x1 = Bytes.i16(glyf, start + 6)
							y1 = Bytes.i16(glyf, start + 8)
							# HarfBuzz's bearing: present for glyphs `hmtx` stores one for.
							bearing_at = if (g < long) 4 * g + 2 else 4 * long + 2 * (g - long)
							left = if (Bytes.fits(bearing_at, 2, hmtx.len())) Bytes.i16(hmtx, bearing_at) else x0.min(x1)
							$boxes = $boxes.append({ x_min: left.to_i32_wrap(), y_min: y0.min(y1).to_i32_wrap(), x_max: (left + x0.max(x1) - x0.min(x1)).to_i32_wrap(), y_max: y0.max(y1).to_i32_wrap() })
						} else {
							$boxes = $boxes.append(TableGlyf.none)
						}
					}
					# A bad entry's offset is never 0: `loca` follows the directory.
					if ($bad_at != 0) Err(Sfnt.bad("loca", $bad_at)) else Ok($boxes)
				}
			}
			_ => Ok(List.repeat(TableGlyf.none, count_of_glyphs))
		}
	}
}
