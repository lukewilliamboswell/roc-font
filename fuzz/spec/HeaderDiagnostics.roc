import build.FontBuild
import font.Font

# A format 1 name table's language tag strings are each checked against
# their own length and storage reference. Two bad records stay independent
# even when a required header has already made the font unreadable.
# https://learn.microsoft.com/en-us/typography/opentype/spec/name
# https://github.com/khaledhosny/ots/blob/v9.3.0/src/name.cc
HeaderDiagnostics := {}.{
	check : {} -> Bool
	check = |_| [BadHead, MissingHhea].all(
		|header| [False, True].all(|too_long| [False, True].all(|too_far| agrees(header, too_long, too_far))),
	)
}

Header : [BadHead, MissingHhea]

agrees : Header, Bool, Bool -> Bool
agrees = |header, too_long, too_far| {
	record = { system: 3, encoding: 1, language: 0x409, id: 1, text: FontBuild.utf16("Family") }
	first = List.repeat(0x41, if (too_long) 202 else 200)
	names = FontBuild.naming([record], [first, FontBuild.utf16("en")])
	# One 12-byte name record after the header, then the 2-byte
	# language-tag count. Each language-tag record is four bytes.
	first_tag = 6 + 12 + 2
	second_tag = first_tag + 4
	name = if (too_far) FontBuild.patch(names, second_tag + 2, FontBuild.u16(65535)) else names
	(body, first_problem) = match header {
		BadHead => (FontBuild.replace(FontBuild.basic, "head", FontBuild.head(5, False)), BadUnitsPerEm)
		MissingHhea => (FontBuild.basic.drop_if(|table| table.tag == "hhea"), MissingTable("hhea"))
	}
	tables = [{ tag: "name", data: name }].concat(body)
	name_at = 12 + 16 * tables.len()
	problem_at = |relative| BadTable({ table: "name", offset: (name_at + relative).to_u32_wrap() })
	expected = [first_problem]
		.concat(if (too_long) [problem_at(first_tag)] else [])
		.concat(if (too_far) [problem_at(second_tag)] else [])
	bytes = FontBuild.file(tables)
	[False, True].all(
		|strict| match Font.from_bytes(bytes, Font.ReadOptions.{ strict }) {
			Err(problems) => problems == expected
			Ok(_) => False
		},
	)
}
