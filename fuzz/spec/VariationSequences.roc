import build.FontBuild
import font.Font

# cmap format 14 stores unsigned 24-bit bases and unsigned 8-bit range
# counts. Both selector pointers are relative to the subtable. Arrange
# the same child tables in two orders so their offsets, rather than their
# order of appearance, determine which selector uses each table.
# https://learn.microsoft.com/en-us/typography/opentype/spec/cmap#format-14-unicode-variation-sequences
VariationSequences := {}.{
	check : {} -> Bool
	check = |_| [False, True].all(agrees)
}

subtable : Bool -> List(U8)
subtable = |interleaved| {
	vs17_default = FontBuild.pack([U32(1), Raw([0, 0x4E, 0, 0])])
	vs17_overrides = FontBuild.pack([U32(1), Raw([0x02, 0x4E, 0]), U16(6)])
	vs256_default = FontBuild.pack([U32(1), Raw([0x02, 0, 1, 255])])
	vs256_overrides = FontBuild.pack([
		U32(3),
		Raw([0, 0x4E, 0]),
		U16(7),
		Raw([0x02, 0x4E, 0]),
		U16(8),
		Raw([0x02, 0xA6, 0xDF]),
		U16(9),
	])
	# The two defaults have equal length. In the second layout the
	# second selector's default comes first, but its overrides still
	# end the subtable exactly.
	tables = if (interleaved) [vs256_default, vs17_overrides, vs17_default, vs256_overrides] else [vs17_default, vs17_overrides, vs256_default, vs256_overrides]
	body = tables.join_map(|table| table)
	FontBuild.pack([
		U16(14),
		U32(32 + body.len()),
		U32(2),
		Raw([0x0E, 0x01, 0x00]),
		U32(if (interleaved) 49 else 32),
		U32(40),
		Raw([0x0E, 0x01, 0xEF]),
		U32(if (interleaved) 32 else 49),
		U32(57),
		Raw(body),
	])
}

agrees : Bool -> Bool
agrees = |interleaved| {
	nominal = FontBuild.cmap12([
		{ first: 0x20, last: 0x20, glyph: 5 },
		{ first: 0x4E00, last: 0x4E00, glyph: 1 },
		{ first: 0x20000, last: 0x20000, glyph: 2 },
		{ first: 0x20001, last: 0x20100, glyph: 256 },
		{ first: 0x20101, last: 0x20101, glyph: 3 },
		{ first: 0x24E00, last: 0x24E00, glyph: 4 },
	])
	cmap = FontBuild.cmap([{ system: 0, encoding: 5, subtable: subtable(interleaved) }, { system: 3, encoding: 10, subtable: nominal }])
	bytes = FontBuild.glyphs_font(FontBuild.counting(512).map(|g| 500 + g), cmap, [])
	font = Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "valid supplementary variation table rejected"
	# The out-of-range bases still have nominal glyphs. The zero-width
	# space left for the unsupported selector distinguishes these runs
	# from a supported default sequence with the same nominal glyph.
	samples = [
		("\u(4E00)\u(E0100)", [1]),
		("\u(24E00)\u(E0100)", [6]),
		("\u(4E00)\u(E01EF)", [7]),
		("\u(24E00)\u(E01EF)", [8]),
		("\u(2A6DF)\u(E01EF)", [9]),
		("\u(20000)\u(E01EF)", [2, 5]),
		("\u(20001)\u(E01EF)", [256]),
		("\u(20081)\u(E01EF)", [384]),
		("\u(20100)\u(E01EF)", [511]),
		("\u(20101)\u(E01EF)", [3, 5]),
	]
	samples.all(
		|(source, glyphs)| {
			run = Font.shape(font, source, Font.ShapeOptions.{ direction: LeftToRight })
			advances = glyphs.map_with_index(|g, i| { x: if (i == 0) 500 + g.to_i32_wrap() else 0, y: 0 })
			run.glyphs == glyphs and run.advances == advances and run.clusters == List.repeat(0, glyphs.len())
		},
	)
}
