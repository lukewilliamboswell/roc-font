import build.FontBuild
import font.Font

# MathGlyphConstruction lists distinct variants in table order even
# when their measurements tie. Measurements and part lengths are UFWORD.
# HarfBuzz 14.6.0 agrees with this independently encoded construction.
# https://learn.microsoft.com/en-us/typography/opentype/spec/math#mathglyphconstruction-table
MathConstructionSizes := {}.{
	check : {} -> Bool
	check = |_| {
		font = Font.from_bytes(fixture({}), Font.ReadOptions.{ strict: True }) ?? crash "valid MATH construction sizes rejected"
		vertical = Font.math_variants(font, 4, Vertical)
		horizontal = Font.math_variants(font, 4, Horizontal)
		assembly = Font.math_assembly(font, 4, Vertical)
		if vertical == [{ glyph: 11, advance: 32767 }, { glyph: 13, advance: 32768 }, { glyph: 12, advance: 32768 }, { glyph: 10, advance: 65535 }]
			and horizontal == [{ glyph: 14, advance: 65535 }] and Font.math_assembly(font, 4, Horizontal) == Absent
			and Font.math_min_connector_overlap(font) == 30000 and assembly == Present({
				italic_correction: -32768,
				parts: [
					{ glyph: 19, start_connector: 0, end_connector: 40000, full_advance: 45000, extender: False },
					{ glyph: 20, start_connector: 32768, end_connector: 32769, full_advance: 65535, extender: True },
					{ glyph: 21, start_connector: 50000, end_connector: 0, full_advance: 65535, extender: False },
				],
			}) {
			True
		} else {
			crash "MATH construction sizes: ${Str.inspect((vertical, horizontal, assembly))}"
		}
	}
}

fixture : {} -> List(U8)
fixture = |_| {
	part = |glyph, start, end, full, flags| [U16(glyph), U16(start), U16(end), U16(full), U16(flags)]
	parts = part(19, 0, 40000, 45000, 0).concat(part(20, 32768, 32769, 65535, 1)).concat(part(21, 50000, 0, 65535, 0))
	assembly = FontBuild.pack([I16(-32768), U16(0), U16(3)].concat(parts))
	vertical = FontBuild.pack([Ref(assembly), U16(4), U16(11), U16(32767), U16(13), U16(32768), U16(12), U16(32768), U16(10), U16(65535)])
	horizontal = FontBuild.pack([U16(0), U16(1), U16(14), U16(65535)])
	coverage = FontBuild.coverage1([4])
	variants = FontBuild.pack([U16(30000), Ref(coverage), Ref(coverage), U16(1), U16(1), Ref(vertical), Ref(horizontal)])
	math = FontBuild.pack([U16(1), U16(0), Ref(List.repeat(0, 214)), Ref(List.repeat(0, 8)), Ref(variants)])
	FontBuild.parity_font([{ tag: "MATH", data: math }])
}
