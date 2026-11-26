import build.FontBuild
import font.Font

# OpenType 1.9.1 cmap, Windows Symbol format 4. The encoding records are
# exclusive. HarfBuzz 14.6.0 prefers the symbol record and uses the
# legacy page's alias only for an absent nominal glyph.
# https://learn.microsoft.com/en-us/typography/opentype/spec/cmap
# https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/hb-ot-cmap-table.hh
LegacyCmap := {}.{
	check : {} -> Bool
	check = |_| [Normal, ArabicSimplified, ArabicTraditional].all(agrees)
}

Page : [Normal, ArabicSimplified, ArabicTraditional]

Mapping : List((U32, U32))

private_mappings : Mapping
private_mappings = [
	(0xF041, 3),
	(0xF042, 4),
	(0xF0FF, 5),
	(0xF101, 6),
	(0xF120, 7),
	(0xF141, 8),
	(0xF14A, 9),
	(0xF220, 10),
	(0xF241, 11),
	(0xF24C, 12),
]

format4 : Mapping -> List(U8)
format4 = |mappings| FontBuild.cmap4(
	mappings.map(
		|(cp, glyph)| {
			first: cp.to_u64(),
			last: cp.to_u64(),
			delta: 65536 + glyph.to_u64() - cp.to_u64(),
			glyphs: [],
		},
	),
)

fixture : Page -> List(U8)
fixture = |page| {
	# A and Arabic alef have direct glyphs that shadow their aliases. B
	# has an explicit zero, so its ordinary symbol alias remains usable.
	symbol = format4([('A', 1), ('B', 0), (0x0627, 2)].concat(private_mappings))
	mac = FontBuild.cmap0(List.repeat(0, 0x41).append(13).concat(List.repeat(0, 0x80 - 0x42)).append(14))
	unicode = format4([('A', 14), ('C', 13)])
	cmap = FontBuild.cmap([
		{ system: 1, encoding: 0, subtable: mac },
		{ system: 3, encoding: 0, subtable: symbol },
		{ system: 3, encoding: 1, subtable: unicode },
	])
	bits = match page {
		Normal => 0
		ArabicSimplified => 0xB200
		ArabicTraditional => 0xB300
	}
	FontBuild.glyphs_font(List.repeat(500, 15), cmap, [{ tag: "OS/2", data: FontBuild.os2_page(bits) }])
}

expected : Page -> Mapping
expected = |page| {
	# Ordinary aliases cover U+00FF, while the Arabic pages use distinct
	# private-use positions for the same base and presentation forms.
	# The simplified page gives isolated and final beh the same glyph.
	(before, after) = match page {
		Normal => ([('A', 1), ('B', 4), (0x00FF, 5), (0x0627, 2)], [])
		ArabicSimplified => ([(0x0020, 7), ('A', 1), (0x0627, 2), (0x0628, 9)], [(0xFE8D, 8), (0xFE8F, 9), (0xFE90, 9)])
		ArabicTraditional => ([(0x0020, 10), ('A', 1), (0x0627, 2), (0x0628, 12)], [(0xFE8D, 11), (0xFE8F, 12)])
	}
	before.concat(private_mappings).concat(after)
}

agrees : Page -> Bool
agrees = |page| {
	font = Font.from_bytes(fixture(page), Font.ReadOptions.{ strict: True }) ?? crash "legacy cmap fixture did not read strictly"
	want = expected(page)
	listed = Font.code_points(font)
	nominal = listed.map(|cp| (cp, Font.glyph(font, cp) ?? 0))
	absent = ['C', 0x0080, 0x00C4, 0x0101, 0xFE8E]
	if listed == want.map(|(cp, _)| cp) and nominal == want and absent.all(|cp| Font.glyph(font, cp) == Err(Missing)) {
		True
	} else {
		crash "legacy cmap for ${Str.inspect(page)} expected ${Str.inspect(want)}, listed ${Str.inspect(nominal)}"
	}
}
