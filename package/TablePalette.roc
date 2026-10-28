import Bytes

## CPAL color palettes. Internal. Checked byte spans preserve non-premultiplied
## sRGB channels, overlapping palettes and explicit missing name IDs.
TablePalette := {
	bytes : List(U8),
	entries : U64,
	count : U64,
	colors_at : U64,
	types_at : U64,
	labels_at : U64,
	entry_labels_at : U64,
}.{
	Color : { red : U8, green : U8, blue : U8, alpha : U8 }
	Palette : { index : U32, light_background : Bool, dark_background : Bool, name_id : [Present(U16), Absent] }

	none : TablePalette
	none = { bytes: [], entries: 0, count: 0, colors_at: 0, types_at: 0, labels_at: 0, entry_labels_at: 0 }

	palette_count : TablePalette -> U32
	palette_count = |table| table.count.to_u32_wrap()

	entry_count : TablePalette -> U32
	entry_count = |table| table.entries.to_u32_wrap()

	palettes : TablePalette -> List(Palette)
	palettes = |table| {
		var $out = List.with_capacity(table.count)
		for i in 0..<table.count {
			flags = if (table.types_at == 0) 0 else Bytes.u32(table.bytes, table.types_at + 4 * i)
			name_id = TablePalette.name_id(table.bytes, table.labels_at, i)
			$out = $out.append({ index: i.to_u32_wrap(), light_background: flags.bitwise_and(1) != 0, dark_background: flags.bitwise_and(2) != 0, name_id })
		}
		$out
	}

	name_id : List(U8), U64, U64 -> [Present(U16), Absent]
	name_id = |bytes, at, index| {
		if at == 0 {
			return Absent
		}
		id = Bytes.u16(bytes, at + 2 * index)
		if (id == 65535) Absent else Present(id.to_u16_wrap())
	}

	palette_name_id : TablePalette, U32 -> [Present(U16), Absent]
	palette_name_id = |table, palette| if (palette.to_u64() >= table.count) Absent else TablePalette.name_id(table.bytes, table.labels_at, palette.to_u64())

	entry_name_id : TablePalette, U32 -> [Present(U16), Absent]
	entry_name_id = |table, entry| if (entry.to_u64() >= table.entries) Absent else TablePalette.name_id(table.bytes, table.entry_labels_at, entry.to_u64())

	color : TablePalette, U32, U32 -> [Present(Color), Absent]
	color = |table, palette, entry| {
		if palette.to_u64() >= table.count or entry.to_u64() >= table.entries {
			return Absent
		}
		first = Bytes.u16(table.bytes, 12 + 2 * palette.to_u64())
		at = table.colors_at + 4 * (first + entry.to_u64())
		Present({ red: Bytes.u8(table.bytes, at + 2).to_u8_wrap(), green: Bytes.u8(table.bytes, at + 1).to_u8_wrap(), blue: Bytes.u8(table.bytes, at).to_u8_wrap(), alpha: Bytes.u8(table.bytes, at + 3).to_u8_wrap() })
	}

	colors : TablePalette, U32 -> [Present(List(Color)), Absent]
	colors = |table, palette| {
		if palette.to_u64() >= table.count {
			return Absent
		}
		var $out = List.with_capacity(table.entries)
		for entry in 0..<table.entries {
			# The loop and checked palette prove both indices are in bounds.
			match TablePalette.color(table, palette, entry.to_u32_wrap()) {
				Present(c) => {
					$out = $out.append(c)
				}
				Absent => crash "a checked CPAL palette index became unavailable"
			}
		}
		Present($out)
	}

	## All offsets are relative to CPAL. Counts are checked against byte
	## spans before allocating, and all independent palette references and
	## optional arrays are reported in one result.
	read : List(U8) -> Try(TablePalette, List(U64))
	read = |bytes| {
		size = bytes.len()
		if !Bytes.fits(0, 12, size) {
			return Err([0])
		}
		version = Bytes.u16(bytes, 0)
		if version > 1 {
			return Err([0])
		}
		entries = Bytes.u16(bytes, 2)
		count = Bytes.u16(bytes, 4)
		color_count = Bytes.u16(bytes, 6)
		colors_at = Bytes.u32(bytes, 8)
		fixed_end = 12 + 2 * count
		header_end = fixed_end + (if (version == 1) 12 else 0)
		if !Bytes.fits(0, header_end, size) {
			return Err([4])
		}
		var $problems = []
		if entries == 0 {
			$problems = $problems.append(2)
		}
		if count == 0 {
			$problems = $problems.append(4)
		}
		if !Bytes.fits(colors_at, 4 * color_count, size) {
			$problems = $problems.append(8)
		}
		for i in 0..<count {
			at = 12 + 2 * i
			first = Bytes.u16(bytes, at)
			if first > color_count or entries > color_count - first {
				$problems = $problems.append(at)
			}
		}
		types_at = if (version == 1) Bytes.u32(bytes, fixed_end) else 0
		labels_at = if (version == 1) Bytes.u32(bytes, fixed_end + 4) else 0
		entry_labels_at = if (version == 1) Bytes.u32(bytes, fixed_end + 8) else 0
		if types_at != 0 {
			if !Bytes.fits(types_at, 4 * count, size) {
				$problems = $problems.append(fixed_end)
			} else {
				for i in 0..<count {
					at = types_at + 4 * i
					if Bytes.u32(bytes, at).bitwise_and(0xFFFFFFFC) != 0 {
						$problems = $problems.append(at)
					}
				}
			}
		}
		if labels_at != 0 and !Bytes.fits(labels_at, 2 * count, size) {
			$problems = $problems.append(fixed_end + 4)
		}
		if entry_labels_at != 0 and !Bytes.fits(entry_labels_at, 2 * entries, size) {
			$problems = $problems.append(fixed_end + 8)
		}
		if !$problems.is_empty() {
			return Err($problems)
		}
		Ok({ bytes, entries, count, colors_at, types_at, labels_at, entry_labels_at })
	}
}

# Original two-palette fixture; both palettes deliberately share a color.
palette_fixture : List(U8)
palette_fixture = [0, 0, 0, 2, 0, 2, 0, 3, 0, 0, 0, 16, 0, 0, 0, 1, 3, 2, 1, 255, 6, 5, 4, 128, 9, 8, 7, 0]

expect match TablePalette.read(palette_fixture) {
	Ok(table) => TablePalette.palette_count(table) == 2 and TablePalette.color(table, 0, 1) == TablePalette.color(table, 1, 0) and TablePalette.color(table, 1, 1) == Present({ red: 7, green: 8, blue: 9, alpha: 0 })
	Err(_) => False
}
expect match TablePalette.read([]) {
	Err(offsets) => offsets == [0]
	Ok(_) => False
}
expect TablePalette.colors(TablePalette.none, 0) == Absent

# Original CPAL1fixture has explicit flags, palette and entry label IDs.
palette_v1 : List(U8)
palette_v1 = [0, 1, 0, 2, 0, 1, 0, 2, 0, 0, 0, 26, 0, 0, 0, 0, 0, 34, 0, 0, 0, 38, 0, 0, 0, 40, 3, 2, 1, 255, 6, 5, 4, 128, 0, 0, 0, 3, 1, 0, 1, 1, 255, 255]

expect match TablePalette.read(palette_v1) {
	Ok(table) => TablePalette.palettes(table) == [{ index: 0, light_background: True, dark_background: True, name_id: Present(256) }] and TablePalette.entry_name_id(table, 0) == Present(257) and TablePalette.entry_name_id(table, 1) == Absent and TablePalette.color(table, 0, 2) == Absent and TablePalette.colors(table, 1) == Absent
	Err(_) => False
}
expect match TablePalette.read(palette_v1.take_first(43)) {
	Err(_) => True
	Ok(_) => False
}
expect match TablePalette.read(palette_fixture.take_first(27)) {
	Err(_) => True
	Ok(_) => False
}
