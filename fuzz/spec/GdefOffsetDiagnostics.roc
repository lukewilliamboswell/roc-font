import build.FontBuild
import font.Font

# In GDEF 1.2, the nullable MarkGlyphSetsDef offset is relative to the
# GDEF start. A nonzero offset must point inside the table, past its
# header. That check needs no glyph count or horizontal metrics.
# https://learn.microsoft.com/en-us/typography/opentype/spec/gdef#gdef-header
# https://github.com/khaledhosny/ots/blob/v9.3.0/src/gdef.cc
GdefOffsetDiagnostics := {}.{
	check : {} -> Bool
	check = |_| [Healthy, MissingHhea, MissingMaxp].all(
		|face| [AbsentChild, PresentChild, InsideHeader, AtEnd].all(|offset| agrees(face, offset)),
	)
}

Face : [Healthy, MissingHhea, MissingMaxp]

Child : [AbsentChild, PresentChild, InsideHeader, AtEnd]

agrees : Face, Child -> Bool
agrees = |face, child| {
	mark_sets = FontBuild.pack([U16(1), U16(1), Ref32(FontBuild.coverage1([1]))])
	# Keep the entire child and the 14-byte header in all cases.
	pointer = match child {
		AbsentChild => 0
		PresentChild => 14
		InsideHeader => 12
		AtEnd => 14 + mark_sets.len()
	}
	data = FontBuild.pack([U32(0x00010002), Raw(List.repeat(0, 8)), U16(pointer), Raw(mark_sets)])
	(body, required) = match face {
		Healthy => (FontBuild.basic, [])
		MissingHhea => (FontBuild.basic.drop_if(|t| t.tag == "hhea"), [MissingTable("hhea")])
		MissingMaxp => (FontBuild.basic.drop_if(|t| t.tag == "maxp"), [MissingTable("maxp")])
	}
	tables = [{ tag: "GDEF", data }].concat(body)
	gdef_at = 12 + 16 * tables.len()
	field = BadTable({ table: "GDEF", offset: (gdef_at + 12).to_u32_wrap() })
	expected = if (child == InsideHeader or child == AtEnd) required.append(field) else required
	bytes = FontBuild.file(tables)
	[False, True].all(
		|strict| match Font.from_bytes(bytes, Font.ReadOptions.{ strict }) {
			Err(problems) => !expected.is_empty() and problems == expected
			Ok(font) => expected.is_empty() and Font.dropped(font).is_empty()
		},
	)
}
