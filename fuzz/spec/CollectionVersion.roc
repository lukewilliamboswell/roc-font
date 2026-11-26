import build.FontBuild
import font.Font

# OpenType 1.9.1 TTC Header v2.0. The face offsets come first, followed
# by three null DSIG fields for an unsigned collection.
# https://learn.microsoft.com/en-us/typography/opentype/spec/otff#ttc-header
CollectionVersion := {}.{
	check : {} -> Bool
	check = |_| layout_check({}) and header_check({})

	layout_check : {} -> Bool
	layout_check = |_| {
		# Face 1 has its table data before its directory. The directory
		# can end exactly at EOF and the other face can still read when
		# this directory is one byte short.
		whole = fixture
		short = whole.drop_last(1)
		Font.face_count(whole) == Ok(2) and Font.face_count(short) == Ok(2)
			and [False, True].all(
				|strict| reads(whole, 0, 600, strict) and reads(whole, 1, 670, strict) and reads(short, 0, 600, strict)
					and rejects(short, 1, [NotAFont], strict)
					and rejects(whole, 2, [NoSuchFace({ face: 2, count: 2 })], strict),
			)
	}

	header_check : {} -> Bool
	header_check = |_| {
		unknown_version = FontBuild.patch(fixture, 4, FontBuild.u32(0x00030000))
		# The two face offsets fit at byte 20. The descriptor ends at 32.
		incomplete_descriptor = fixture.take_first(31)
		# OTS ignores the descriptor's values once all three fields fit.
		descriptor = FontBuild.pack([Tag("DSIG"), U32(16), U32(fixture.len())])
		ignored_descriptor = FontBuild.patch(fixture, 20, descriptor)
		Font.face_count(unknown_version) == Err(NotAFont)
			and Font.face_count(incomplete_descriptor) == Err(NotAFont)
			and Font.face_count(ignored_descriptor) == Ok(2)
			and [False, True].all(
				|strict| rejects(unknown_version, 0, [NotAFont], strict)
					and reads(ignored_descriptor, 0, 600, strict)
					and reads(ignored_descriptor, 1, 670, strict),
			)
	}

}

reads : List(U8), U32, I32, Bool -> Bool
reads = |bytes, face, advance, strict|
	match Font.from_bytes(bytes, Font.ReadOptions.{ face, strict }) {
		Ok(font) => Font.glyph(font, 'A') == Ok(1) and Font.advance(font, 1) == advance
		Err(problems) => crash "TTC version 2 face ${face.to_str()}: ${Str.inspect(problems)}"
	}

rejects : List(U8), U32, List(Font.Problem), Bool -> Bool
rejects = |bytes, face, expected, strict|
	match Font.from_bytes(bytes, Font.ReadOptions.{ face, strict }) {
		Ok(_) => False
		Err(problems) => problems == expected
	}

shift_table_offsets : List(U8), U64 -> List(U8)
shift_table_offsets = |file, delta| {
	var $shifted = file
	for i in 0..<FontBuild.basic.len() {
		at = 20 + 16 * i
		local = file.sublist({ start: at, len: 4 }).fold(0, |word, byte| 256 * word + byte.to_u64())
		$shifted = FontBuild.patch($shifted, at, FontBuild.u32(local + delta))
	}
	$shifted
}

fixture : List(U8)
fixture = {
	header_size = 32
	directory_size = 12 + 16 * FontBuild.basic.len()
	first = shift_table_offsets(FontBuild.file(FontBuild.basic), header_size)
	second_body = header_size + first.len()
	tables = FontBuild.replace(FontBuild.basic, "hmtx", FontBuild.hmtx([500, 670, 700, 800]))
	second = shift_table_offsets(FontBuild.file(tables), second_body - directory_size)
	second_directory = second_body + second.len() - directory_size
	header = FontBuild.pack([Tag("ttcf"), U32(0x00020000), U32(2), U32(header_size), U32(second_directory), U32(0), U32(0), U32(0)])
	header.concat(first).concat(second.drop_first(directory_size)).concat(second.take_first(directory_size))
}
