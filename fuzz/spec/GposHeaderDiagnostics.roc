import build.FontBuild
import font.Font

# GPOS script, feature and lookup list headers have no glyph dependency.
GposHeaderDiagnostics := {}.{
	check : {} -> Bool
	check = |_| {
		empty = FontBuild.pack([U32(0x00010000), Ref([0, 0]), Ref([0, 0]), Ref([0, 0])])
		outside = FontBuild.patch(empty, 6, FontBuild.u16(65535))
		[Healthy, MissingHhea, MissingMaxp].all(
			|header|
				agrees(header, empty, Absent)
					and agrees(header, empty.take_first(8), Present(0))
					and agrees(header, outside, Present(65535)),
		)
	}
}

Header : [Healthy, MissingHhea, MissingMaxp]

agrees : Header, List(U8), [Present(U64), Absent] -> Bool
agrees = |header, gpos, fault| {
	(body, required) = match header {
		Healthy => (FontBuild.basic, [])
		MissingHhea => (FontBuild.basic.drop_if(|t| t.tag == "hhea"), [MissingTable("hhea")])
		MissingMaxp => (FontBuild.basic.drop_if(|t| t.tag == "maxp"), [MissingTable("maxp")])
	}
	tables = [{ tag: "GPOS", data: gpos }].concat(body)
	at = 12 + 16 * tables.len()
	expected = match fault {
		Absent => required
		Present(relative) => required.append(BadTable({ table: "GPOS", offset: (at + relative).to_u32_wrap() }))
	}
	[False, True].all(
		|strict| match Font.from_bytes(FontBuild.file(tables), Font.ReadOptions.{ strict }) {
			Ok(_) if expected.is_empty() => True
			Err(problems) if problems == expected => True
			Ok(_) => crash "GPOS accepted with expected problems ${Str.inspect(expected)}"
			Err(problems) => crash "GPOS diagnostics: expected ${Str.inspect(expected)}, got ${Str.inspect(problems)}"
		},
	)
}
