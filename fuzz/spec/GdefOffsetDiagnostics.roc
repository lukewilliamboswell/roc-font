import build.FontBuild
import font.Font

# The nullable mark set and item store offsets use the GDEF start.
# A nonzero offset must point inside the table, past its header.
# That check needs no glyph count or horizontal metrics.
# https://learn.microsoft.com/en-us/typography/opentype/spec/gdef#gdef-header
# https://github.com/khaledhosny/ots/blob/v9.3.0/src/gdef.cc
GdefOffsetDiagnostics := {}.{
	check : {} -> Bool
	check = |_| [Healthy, MissingHhea, MissingMaxp].all(
		|face| [MarkSets, ItemStore].all(
			|kind| {
				offsets = [AbsentChild, PresentChild, InsideHeader, AtEnd]
				cases = if (kind == ItemStore) offsets.append(HighWord) else offsets
				cases.all(|offset| agrees(face, kind, offset))
			},
		),
	)
}

Face : [Healthy, MissingHhea, MissingMaxp]

Kind : [MarkSets, ItemStore]

Child : [AbsentChild, PresentChild, InsideHeader, AtEnd, HighWord]

agrees : Face, Kind, Child -> Bool
agrees = |face, kind, child| {
	(header_len, field_at, payload) = match kind {
		MarkSets => (14, 12, FontBuild.pack([U16(1), U16(1), Ref32(FontBuild.coverage1([1]))]))
		ItemStore => (18, 14, FontBuild.variation_store(0, [], []))
	}
	pointer = match child {
		AbsentChild => 0
		PresentChild => header_len
		InsideHeader => header_len - 2
		AtEnd => header_len + payload.len()
		# Truncating the offset to 16 bits would find a valid store.
		HighWord => 65536 + header_len
	}
	data = match kind {
		MarkSets => FontBuild.pack([U32(0x00010002), Raw(List.repeat(0, 8)), U16(pointer), Raw(payload)])
		ItemStore => FontBuild.pack([U32(0x00010003), Raw(List.repeat(0, 10)), U32(pointer), Raw(payload)])
	}
	(body, required) = match face {
		Healthy => (FontBuild.basic, [])
		MissingHhea => (FontBuild.basic.drop_if(|t| t.tag == "hhea"), [MissingTable("hhea")])
		MissingMaxp => (FontBuild.basic.drop_if(|t| t.tag == "maxp"), [MissingTable("maxp")])
	}
	tables = [{ tag: "GDEF", data }].concat(body)
	gdef_at = 12 + 16 * tables.len()
	field = BadTable({ table: "GDEF", offset: (gdef_at + field_at).to_u32_wrap() })
	expected = if (child == PresentChild or child == AbsentChild) required else required.append(field)
	bytes = FontBuild.file(tables)
	[False, True].all(
		|strict| match Font.from_bytes(bytes, Font.ReadOptions.{ strict }) {
			Err(problems) => !expected.is_empty() and problems == expected
			Ok(font) => expected.is_empty() and Font.dropped(font).is_empty()
		},
	)
}
