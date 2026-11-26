import build.FontBuild
import font.Font

# The GDEF prefix identifies the version and which optional offsets
# must be present. Neither check needs head, hhea or a glyph count.
# A class definition's glyph ID does need the glyph count.
# https://learn.microsoft.com/en-us/typography/opentype/spec/gdef#gdef-header
GdefHeaderDiagnostics := {}.{
	check : {} -> Bool
	check = |_| {
		[Healthy, BadHead, MissingHhea, MissingMaxp].all(
			|header| [V10, V13, ForbiddenMinor, ShortV13].all(|gdef| agrees(header, gdef)),
		)
			and agrees(Healthy, PastGlyphCount)
			and agrees(MissingMaxp, PastGlyphCount)
	}
}

FaceHeader : [Healthy, BadHead, MissingHhea, MissingMaxp]

Gdef : [V10, V13, ForbiddenMinor, ShortV13, PastGlyphCount]

agrees : FaceHeader, Gdef -> Bool
agrees = |header, gdef| {
	(data, invalid_at) = match gdef {
		V10 => (FontBuild.pack([U32(0x00010000), Raw(List.repeat(0, 8))]), None)
		V13 => (FontBuild.pack([U32(0x00010003), Raw(List.repeat(0, 14))]), None)
		ForbiddenMinor => (FontBuild.pack([U32(0x00010001), Raw(List.repeat(0, 8))]), At(0))
		ShortV13 => (FontBuild.pack([U32(0x00010003), Raw(List.repeat(0, 12))]), At(0))
		PastGlyphCount => {
			# Class definition format 1. Glyph 4 is the first excess
			# glyph on the four-glyph fixture, at byte 14 of GDEF.
			classes = FontBuild.pack([U16(1), U16(4), U16(1), U16(1)])
			wanted = if (header == MissingMaxp) None else At(14)
			(FontBuild.pack([U32(0x00010000), Ref(classes), Raw(List.repeat(0, 6))]), wanted)
		}
	}
	(body, required) = match header {
		Healthy => (FontBuild.basic, [])
		BadHead => (FontBuild.replace(FontBuild.basic, "head", FontBuild.head(5, False)), [BadUnitsPerEm])
		MissingHhea => (FontBuild.basic.drop_if(|table| table.tag == "hhea"), [MissingTable("hhea")])
		MissingMaxp => (FontBuild.basic.drop_if(|table| table.tag == "maxp"), [MissingTable("maxp")])
	}
	tables = [{ tag: "GDEF", data }].concat(body)
	gdef_at = 12 + 16 * tables.len()
	expected = match invalid_at {
		None => required
		At(delta) => required.append(BadTable({ table: "GDEF", offset: (gdef_at + delta).to_u32_wrap() }))
	}
	bytes = FontBuild.file(tables)
	[False, True].all(
		|strict| match Font.from_bytes(bytes, Font.ReadOptions.{ strict }) {
			Err(problems) => !expected.is_empty() and problems == expected
			Ok(font) => expected.is_empty() and Font.dropped(font).is_empty()
		},
	)
}
