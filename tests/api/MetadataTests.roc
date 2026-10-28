import font.Font
import build.FontBuild

## Original font facts used by embedding and subsetting consumers.
MetadataTests :: {}.{}

expect {
	names = FontBuild.naming(
		[
			{ system: 3, encoding: 1, language: 0x409, id: 1, text: FontBuild.utf16("Legacy Family") },
			{ system: 3, encoding: 1, language: 0x409, id: 4, text: FontBuild.utf16("Full Font Name") },
			{ system: 3, encoding: 1, language: 0x409, id: 6, text: FontBuild.utf16("Font-PostScript") },
		],
		[],
	)
	tables = FontBuild.basic.append({ tag: "name", data: names }).append({ tag: "TEST", data: [1, 2, 3, 4] })
	match Font.from_bytes(FontBuild.file(tables), Font.ReadOptions.{}) {
		Ok(font) => Font.full_name(font) == Ok("Full Font Name") and Font.postscript_name(font) == Ok("Font-PostScript") and Font.legacy_family_name(font) == Ok("Legacy Family") and Font.table_bytes(font, "TEST") == Present([1, 2, 3, 4]) and Font.table_bytes(font, "name") == Present(names) and Font.table_bytes(font, "missing") == Absent and Font.table_bytes(font, "") == Absent and Font.table_bytes(font, "NONE") == Absent and Font.tables(font).len() == tables.len()
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(FontBuild.file(FontBuild.basic), Font.ReadOptions.{}) {
		Ok(font) => Font.embedding_flags(font) == Absent and Font.full_name(font) == Err(Missing) and Font.postscript_name(font) == Err(Missing) and Font.legacy_family_name(font) == Err(Missing) and Font.stored_header_metrics(font) == { ascent: 800, descent: -200, line_gap: 0 } and Font.stored_left_side_bearing(font, 4) == Absent
		Err(_) => False
	}
}

# The last long advance is shared; each later glyph retains its own signed
# side bearing. These values are stored design facts even after Font.at.
expect {
	metrics = FontBuild.hmtx([500]).concat(FontBuild.u16(65531)).concat(FontBuild.u16(17)).concat(FontBuild.u16(65527))
	tables = FontBuild.replace(FontBuild.replace(FontBuild.basic, "hhea", FontBuild.hhea(800, -200, 1)), "hmtx", metrics)
	os2 = FontBuild.patch(FontBuild.os2_page(0), 8, FontBuild.u16(0x108))
	match Font.from_bytes(FontBuild.file(tables.append({ tag: "OS/2", data: os2 })), Font.ReadOptions.{}) {
		Ok(font) => [0, 1, 2, 3].map(|id| Font.stored_left_side_bearing(font, id)) == [Present(0), Present(-5), Present(17), Present(-9)] and [0, 1, 2, 3].map(|id| Font.advance(font, id)) == [500, 500, 500, 500] and Font.embedding_flags(font) == Present(0x108)
		Err(_) => False
	}
}

# All side bearings must be present even when glyph outlines are absent.
expect {
	tables = FontBuild.replace(FontBuild.replace(FontBuild.basic, "hhea", FontBuild.hhea(800, -200, 1)), "hmtx", FontBuild.hmtx([500]))
	match Font.from_bytes(FontBuild.file(tables), Font.ReadOptions.{}) {
		Ok(_) => False
		Err(problems) => problems.any(
			|p| match p {
				BadTable({ table, offset: _ }) => table == "hmtx"
				_ => False
			},
		)
	}
}

# Raw tables are original input even when lenient reading drops one.
expect {
	kern = [0, 1, 0, 0]
	match Font.from_bytes(FontBuild.file(FontBuild.basic.append({ tag: "kern", data: kern })), Font.ReadOptions.{}) {
		Ok(font) => !Font.dropped(font).is_empty() and Font.table_bytes(font, "kern") == Present(kern)
		Err(_) => False
	}
}
