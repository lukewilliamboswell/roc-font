import build.FontBuild
import font.Font

# Checking the MATH version needs only the table header. The enclosing
# face reports this independent optional-table diagnostic alongside a
# broken head or missing hhea, at the file offset given by the directory.
# https://learn.microsoft.com/en-us/typography/opentype/spec/math
MathHeaderDiagnostics := {}.{
	check : {} -> Bool
	check = |_| [Healthy, BadHead, MissingHhea].all(
		|header| [False, True].all(|bad_major| agrees(header, bad_major)),
	)
}

Header : [Healthy, BadHead, MissingHhea]

agrees : Header, Bool -> Bool
agrees = |header, bad_major| {
	math = FontBuild.pack([
		U16(if (bad_major) 2 else 1),
		U16(0),
		Ref(List.repeat(0, 214)),
		Ref(List.repeat(0, 8)),
		Ref(List.repeat(0, 10)),
	])
	(body, required) = match header {
		Healthy => (FontBuild.basic, [])
		BadHead => (FontBuild.replace(FontBuild.basic, "head", FontBuild.head(5, False)), [BadUnitsPerEm])
		MissingHhea => (FontBuild.basic.drop_if(|table| table.tag == "hhea"), [MissingTable("hhea")])
	}
	tables = [{ tag: "MATH", data: math }].concat(body)
	math_at = (12 + 16 * tables.len()).to_u32_wrap()
	optional = if (bad_major) [BadTable({ table: "MATH", offset: math_at })] else []
	expected = required.concat(optional)
	bytes = FontBuild.file(tables)
	[False, True].all(
		|strict| {
			rejected = !required.is_empty() or (strict and bad_major)
			match Font.from_bytes(bytes, Font.ReadOptions.{ strict }) {
				Err(problems) => rejected and problems == expected
				Ok(font) => !rejected and Font.dropped(font) == optional and Font.has_math(font) == !bad_major
			}
		},
	)
}
