import build.FontBuild
import font.Font

# The offset width comes from head and the number of offsets from maxp.
# Their ordering uses neither hhea nor the bearings it locates.
# https://learn.microsoft.com/en-us/typography/opentype/spec/loca
LocaHeaderDiagnostics := {}.{
	check : {} -> Bool
	check = |_| [Healthy, MissingHhea, BadHhea, MissingHead, MissingMaxp].all(
		|header| [False, True].all(|long| [InOrder, Reversed, MissingEnd].all(|fault| agrees(header, long, fault))),
	)
}

Header : [Healthy, MissingHhea, BadHhea, MissingHead, MissingMaxp]

Fault : [InOrder, Reversed, MissingEnd]

agrees : Header, Bool, Fault -> Bool
agrees = |header, long, fault| {
	glyphs = [[], FontBuild.outline(10, 30), FontBuild.outline(5, 45), []]
	outlines = FontBuild.outlines(glyphs, long)
	size = if (long) 4 else 2
	# Glyph 2 starts after the first nonempty glyph. Moving its end
	# back to zero keeps both offsets in glyf but reverses their order.
	later = 3 * size
	loca = match fault {
		InOrder => outlines.loca
		Reversed => FontBuild.patch(outlines.loca, later, List.repeat(0, size))
		MissingEnd => outlines.loca.drop_last(size)
	}
	core = FontBuild.replace(FontBuild.basic, "head", FontBuild.head(1000, long)).drop_if(
		|table| table.tag == "hhea" or (header == MissingHead and table.tag == "head") or (header == MissingMaxp and table.tag == "maxp"),
	)
	hhea = if (header == MissingHhea) [] else [{ tag: "hhea", data: FontBuild.hhea(800, -200, if (header == BadHhea) 0 else 4) }]
	tables = [{ tag: "loca", data: loca }].concat(hhea).append({ tag: "glyf", data: outlines.glyf }).concat(core)
	loca_at = 12 + 16 * tables.len()
	hhea_at = loca_at + (loca.len() + 3) // 4 * 4
	bad = |table, at| BadTable({ table, offset: at.to_u32_wrap() })
	required = match header {
		Healthy => []
		MissingHhea => [MissingTable("hhea")]
		BadHhea => [bad("hhea", hhea_at + 34)]
		MissingHead => [MissingTable("head")]
		MissingMaxp => [MissingTable("maxp")]
	}
	known_offsets = header != MissingHead and header != MissingMaxp
	expected = match fault {
		Reversed if known_offsets => required.append(bad("loca", loca_at + later))
		MissingEnd if known_offsets => required.append(bad("loca", loca_at))
		_ => required
	}
	bytes = FontBuild.file(tables)
	[False, True].all(
		|strict| match Font.from_bytes(bytes, Font.ReadOptions.{ strict }) {
			Ok(font) => expected.is_empty() and Font.dropped(font).is_empty()
			Err(problems) => !expected.is_empty() and problems == expected
		},
	)
}
