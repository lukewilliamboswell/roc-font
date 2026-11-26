import build.FontBuild
import font.Font

# OpenType 1.9.1 MathGlyphInfo. Each child selects its own glyphs.
# A coverage index is local to that child, even for a shared glyph.
# https://learn.microsoft.com/en-us/typography/opentype/spec/math#mathglyphinfo-table
MathGlyphInfo := {}.{
	check : {} -> Bool
	check = |_| {
		bytes = FontBuild.parity_font([{ tag: "MATH", data: math }])
		font = Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "MATH GlyphInfo fixture was rejected"
		# Glyph 5 has row 3 in italics, row 0 in accents, and row 2 in
		# kern. Glyph 3 is extended without italics, glyph 4 the reverse.
		glyphs = [0.U32, 1, 2, 3, 4, 5, 6, 7]
		observed = glyphs.map(
			|g| (
				Font.math_italic_correction(font, g),
				Font.math_top_accent_attachment(font, g),
				Font.math_extended_shape(font, g),
				Font.math_kern_table(font, g, TopRight).values,
				Font.math_kern_table(font, g, BottomLeft).values,
			),
		)
		expected = [
			(Absent, Absent, False, [], []),
			(Present(-8), Absent, False, [], []),
			(Present(22), Absent, False, [14], []),
			(Absent, Absent, True, [0], []),
			(Present(0), Absent, False, [], []),
			(Present(47), Present(330), True, [50], [-30]),
			(Absent, Present(0), False, [], []),
			(Absent, Absent, False, [], []),
		]
		if observed == expected {
			True
		} else {
			crash "MATH GlyphInfo rows: ${Str.inspect(observed)}"
		}
	}
}

values : List(U8), List(I64) -> List(U8)
values = |coverage, amounts| FontBuild.pack([Ref(coverage), U16(amounts.len())].concat(amounts.join_map(|amount| [I16(amount), U16(0)])))

constant_kern : I64 -> FontBuild.Field
constant_kern = |amount| Ref(FontBuild.pack([U16(0), I16(amount), U16(0)]))

math : List(U8)
math = {
	italics = values(FontBuild.coverage2([{ first: 1, last: 2, index: 0 }, { first: 4, last: 5, index: 2 }]), [-8, 22, 0, 47])
	accents = values(FontBuild.coverage1([5, 6]), [330, 0])
	extended = FontBuild.coverage1([3, 5])
	kern_coverage = FontBuild.coverage2([{ first: 2, last: 3, index: 0 }, { first: 5, last: 6, index: 2 }])
	kern = FontBuild.pack([
		Ref(kern_coverage),
		U16(4),
		constant_kern(14),
		U16(0),
		U16(0),
		U16(0),
		constant_kern(0),
		U16(0),
		U16(0),
		U16(0),
		constant_kern(50),
		U16(0),
		U16(0),
		constant_kern(-30),
		U16(0),
		U16(0),
		U16(0),
		U16(0),
	])
	info = FontBuild.pack([Ref(italics), Ref(accents), Ref(extended), Ref(kern)])
	FontBuild.pack([U16(1), U16(0), Ref(List.repeat(0, 214)), Ref(info), Ref(List.repeat(0, 10))])
}
