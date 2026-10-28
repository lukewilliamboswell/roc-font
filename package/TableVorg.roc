import Sfnt
import Bytes

## Explicit CFF vertical origins. TrueType callers ignore this table.
TableVorg := { default_y : I32, glyphs : List(U16), origins : List(I16) }.{

	from_tables : List(U8), List(Sfnt.Table), U64 -> Try([Present(TableVorg), Absent], Sfnt.Bad)
	from_tables = |bytes, tables, glyph_count|
		match Sfnt.located(bytes, tables, "VORG", 8) {
			Missing => Ok(Absent)
			Bad(at) => Err(Sfnt.bad("VORG", at))
			Found({ data, offset }) => {
				if Bytes.u32(data, 0) != 0x00010000 {
					return Err(Sfnt.bad("VORG", offset))
				}
				count = Bytes.u16(data, 6)
				if !Bytes.fits(8, 4 * count, data.len()) {
					return Err(Sfnt.bad("VORG", offset + 6))
				}
				var $glyphs = List.with_capacity(count)
				var $origins = List.with_capacity(count)
				var $previous = 0
				for i in 0..<count {
					at = 8 + 4 * i
					glyph = Bytes.u16(data, at)
					if glyph >= glyph_count or (i != 0 and glyph <= $previous) {
						return Err(Sfnt.bad("VORG", offset + at))
					}
					$glyphs = $glyphs.append(glyph.to_u16_wrap())
					$origins = $origins.append(Bytes.i16(data, at + 2).to_i16_wrap())
					$previous = glyph
				}
				Ok(Present({ default_y: Bytes.i16(data, 4).to_i32_wrap(), glyphs: $glyphs, origins: $origins }))
			}
		}

	origin : TableVorg, U64 -> I32
	origin = |table, glyph| {
		var $lo = 0
		var $hi = table.glyphs.len()
		while $lo < $hi {
			mid = $lo + ($hi - $lo) // 2
			if (table.glyphs.get(mid) ?? 0).to_u64() < glyph {
				$lo = mid + 1
			} else {
				$hi = mid
			}
		}
		if table.glyphs.get($lo) == Ok(glyph.to_u16_wrap()) and glyph <= 65535 {
			(table.origins.get($lo) ?? 0).to_i32()
		} else table.default_y
	}
}

vorg = [0, 1, 0, 0, 3, 32, 0, 2, 0, 1, 3, 132, 0, 3, 2, 188]

tables = [{ tag: Sfnt.tag_of("VORG"), offset: 0, length: 16 }]
expect {
	match TableVorg.from_tables(vorg, tables, 4) {
		Ok(Present(table)) => TableVorg.origin(table, 0) == 800 and TableVorg.origin(table, 1) == 900 and TableVorg.origin(table, 2) == 800 and TableVorg.origin(table, 3) == 700 and TableVorg.origin(table, 65537) == 800
		_ => False
	}
}
expect TableVorg.from_tables(vorg.drop_last(1), tables, 4).is_err()
expect TableVorg.from_tables(vorg.set(13, 1) ?? [], tables, 4).is_err()
expect TableVorg.from_tables(vorg, tables, 3).is_err()
