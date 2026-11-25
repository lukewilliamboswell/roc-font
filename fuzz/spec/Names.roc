import build.FontBuild
import font.Font

# OpenType 1.9.1, Name Records and InstanceRecord.
# https://learn.microsoft.com/en-us/typography/opentype/spec/name#name-records
# https://learn.microsoft.com/en-us/typography/opentype/spec/fvar#instancerecord
# An instance takes its display name from the subfamily name ID. The
# optional PostScript name follows the coordinates and affects the stride.
Names := {}.{
	check : {} -> Bool
	check = |_| [False, True].all(|postscript| [False, True].all(|both_encodings| agrees(postscript, both_encodings)))
}

naming : Bool -> List(U8)
naming = |both_encodings| {
	# Sorted by platform, encoding, language, and name ID. The two
	# English Unicode records for ID 260 have equal preference.
	record = |system, encoding, language, id, name| { system, encoding, language, id, text: FontBuild.utf16(name) }
	earlier = if (both_encodings) [record(0, 3, 0x8001, 260, "Bold")] else []
	records = earlier.concat([
		record(0, 4, 0x8000, 260, "Fett"),
		record(0, 4, 0x8001, 260, "Heavy"),
		record(3, 1, 0x0407, 16, "Schrift"),
		record(3, 1, 0x0409, 1, "Legacy Family"),
		record(3, 1, 0x0409, 2, "Regular"),
		record(3, 1, 0x0409, 3, "Legacy Family Regular 1.0"),
		record(3, 1, 0x0409, 4, "Legacy Family Regular"),
		record(3, 1, 0x0409, 5, "Version 1.0"),
		record(3, 1, 0x0409, 6, "LegacyFamily-Regular"),
		record(3, 1, 0x0409, 17, "Book"),
		record(3, 1, 0x0409, 256, "Weight"),
		record(3, 1, 0x0409, 258, "Light"),
		record(3, 1, 0x0409, 261, "LegacyFamily-Bold"),
		record(3, 1, 0x0409, 262, "LegacyFamily-Light"),
		record(3, 1, 0x0809, 258, "Light British"),
	])
	FontBuild.naming(records, ["de", "eN-GB"].map(FontBuild.utf16))
}

fvar : Bool -> List(U8)
fvar = |postscript| {
	axes = FontBuild.fvar([{ tag: "wght", min: 300, default: 400, max: 700 }])
	header = FontBuild.patch(axes, 12, FontBuild.pack([U16(3), U16(if (postscript) 10 else 8)]))
	instance = |id, weight, ps_id| FontBuild.pack(
		[U16(id), U16(0), U32(weight * 65536)].concat(if (postscript) [U16(ps_id)] else []),
	)
	header.concat(instance(260, 700, 261)).concat(instance(17, 400, 6)).concat(instance(258, 300, 262))
}

agrees : Bool, Bool -> Bool
agrees = |postscript, both_encodings| {
	# Make a complete TrueType fixture so the name table can also be read
	# through the public API in strict mode.
	characters = (FontBuild.basic.find_first(|t| t.tag == "cmap") ?? crash "basic fixture has a cmap").data
	triangle = FontBuild.simple_glyph([[{ x: 0, y: 0, on: True }, { x: 100, y: 0, on: True }, { x: 0, y: 100, on: True }]])
	bytes = FontBuild.outline_font(
		[[], triangle, [], []],
		[500, 600, 700, 800],
		[0, 0, 0, 0],
		4,
		False,
		characters,
		[
			{ tag: "fvar", data: fvar(postscript) },
			{ tag: "name", data: naming(both_encodings) },
			{ tag: "OS/2", data: FontBuild.os2({ use_typo: False, typo_ascent: 800, typo_descent: -200, win_ascent: 800, win_descent: 200 }) },
			{ tag: "post", data: FontBuild.post(0x00030000, [], []) },
		],
	)
	match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
		Err(problems) => crash "name fixture: ${Str.inspect(problems)}"
		Ok(font) => {
			bold = if (both_encodings) "Bold" else "Heavy"
			expected = [
				{ name: bold, axes: [{ tag: "wght", value: 700 }] },
				{ name: "Book", axes: [{ tag: "wght", value: 400 }] },
				{ name: "Light", axes: [{ tag: "wght", value: 300 }] },
			]
			Font.family_name(font) == Ok("Schrift") and Font.instances(font) == expected
		}
	}
}
