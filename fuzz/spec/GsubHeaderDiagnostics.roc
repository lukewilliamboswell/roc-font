import build.FontBuild
import font.Font

# The GSUB header has its own version and list offsets. Glyph counts
# only matter after the reader follows those offsets.
# https://learn.microsoft.com/en-us/typography/opentype/spec/gsub
GsubHeaderDiagnostics := {}.{
	check : {} -> Bool
	check = |_| {
		lookup = { kind: 1, subtables: [FontBuild.single2([1], [2])] }
		valid = FontBuild.layout("latn", [{ tag: "liga", lookups: [0] }], [lookup])
		invalid_glyph = { kind: 1, subtables: [FontBuild.single2([1], [99])] }
		needs_count = FontBuild.layout("latn", [{ tag: "liga", lookups: [0] }], [invalid_glyph])
		faults = [
			{ data: FontBuild.patch(valid, 0, FontBuild.u16(2)), relative: 0 },
			{ data: FontBuild.patch(valid.take_first(10), 2, FontBuild.u16(1)), relative: 0 },
			{ data: FontBuild.patch(valid, 6, FontBuild.u16(65535)), relative: 6 },
		]
		# A healthy GSUB is readable, including when the unrelated face
		# prerequisites instead make preparation fail.
		agrees(valid, True, Absent) and agrees(valid, False, Absent)
			and agrees(needs_count, False, Absent)
			and faults.all(|f| [True, False].all(|has_maxp| agrees(f.data, has_maxp, Present(f.relative))))
	}
}

agrees : List(U8), Bool, [Present(U64), Absent] -> Bool
agrees = |gsub, has_maxp, fault| {
	body = if (has_maxp) FontBuild.basic else FontBuild.basic.drop_if(|table| table.tag == "maxp")
	tables = [{ tag: "GSUB", data: gsub }].concat(body)
	at = 12 + 16 * tables.len()
	required = if (has_maxp) [] else [MissingTable("maxp")]
	expected = match fault {
		Absent => required
		Present(relative) => required.append(BadTable({ table: "GSUB", offset: (at + relative).to_u32_wrap() }))
	}
	[False, True].all(
		|strict| match Font.from_bytes(FontBuild.file(tables), Font.ReadOptions.{ strict }) {
			Ok(_) if expected.is_empty() => True
			Err(problems) if problems == expected => True
			Ok(_) => crash "GSUB header diagnostics: accepted with expected problems ${Str.inspect(expected)}"
			Err(problems) => crash "GSUB header diagnostics: expected ${Str.inspect(expected)}, got ${Str.inspect(problems)}"
		},
	)
}
