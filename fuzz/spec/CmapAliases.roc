import build.FontBuild
import font.Font

# Format 13 maps the whole inclusive interval to one glyph. Format 13
# under Unicode encoding 6 can coexist with a lower-priority format 12
# under Unicode encoding 4. A missing glyph in the chosen map stays
# missing; that other map is not a per-character fallback.
# https://learn.microsoft.com/en-us/typography/opentype/spec/cmap#format-13-many-to-one-range-mappings
CmapAliases := {}.{
	check : {} -> Bool
	check = |_| [False, True].all(|split| [False, True].all(|out_of_range| agrees(split, out_of_range)))
}

agrees : Bool, Bool -> Bool
agrees = |split, out_of_range| {
	adjacent = if (split) [{ first: 6, last: 6, glyph: 3 }, { first: 7, last: 7, glyph: 3 }] else [{ first: 6, last: 7, glyph: 3 }]
	# In this encoding OTS leaves group glyph IDs unchecked. Querying
	# a group past the font's count must still leave later groups usable.
	middle_glyph = if (out_of_range) 4 else 3
	groups = [
		{ first: 0, last: 1, glyph: 2 },
		{ first: 2, last: 3, glyph: 1 },
		{ first: 4, last: 5, glyph: 0 },
	].concat(adjacent).concat([
		{ first: 9, last: 10, glyph: 3 },
		{ first: 12, last: 13, glyph: middle_glyph },
		{ first: 0x10FFFD, last: 0x10FFFF, glyph: 2 },
	])
	less_preferred = FontBuild.cmap12([
		{ first: 4, last: 4, glyph: 3 },
		{ first: 8, last: 8, glyph: 1 },
		{ first: 12, last: 12, glyph: 1 },
		{ first: 0x10FFFD, last: 0x10FFFD, glyph: 1 },
	])
	cmap = FontBuild.cmap([{ system: 0, encoding: 4, subtable: less_preferred }, { system: 0, encoding: 6, subtable: FontBuild.cmap13(groups) }])
	bytes = FontBuild.glyphs_font([500, 600, 610, 620], cmap, [])
	font = Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "format 13 with a conforming format 12 record rejected"
	low = [(0, 2), (1, 2), (2, 1), (3, 1), (6, 3), (7, 3), (9, 3), (10, 3)]
	middle = if (out_of_range) [] else [(12, 3), (13, 3)]
	high = [(0x10FFFD, 2), (0x10FFFE, 2), (0x10FFFF, 2)]
	present = low.concat(middle).concat(high)
	holes = [4, 5, 8, 11, 14, 0x10FFFC, 0x110000, 0xFFFFFFFF].concat(if (out_of_range) [12, 13] else [])
	Font.code_points(font) == present.map(|(cp, _)| cp)
		and present.all(|(cp, glyph)| Font.glyph(font, cp) == Ok(glyph))
		and holes.all(|cp| Font.glyph(font, cp) == Err(Missing))
}
