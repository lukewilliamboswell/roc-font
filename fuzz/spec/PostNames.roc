import build.FontBuild
import font.Font

# OpenType 1.9.1 post format 2. A uint16 index from 258 is an ordinal
# among the Pascal strings. A name's byte offset can exceed 65535.
# https://learn.microsoft.com/en-us/typography/opentype/spec/post#version-20
PostNames := {}.{
	check : {} -> Bool
	check = |_| {
		last_index = 0x8200
		indices = [0, last_index, 257, 258, last_index]
		# The first name takes 10 bytes including its length. Each
		# intermediate name takes 2, putting the final name past 64 KiB.
		names = ["first.alt"].concat(List.repeat("x", last_index - 259)).append("last.alt")
		post_table = FontBuild.post(0x00020000, indices, names)
		cmap = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([]) }])
		bytes = FontBuild.glyphs_font(List.repeat(600, indices.len()), cmap, [{ tag: "post", data: post_table }])
		match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
			Ok(font) => {
				actual = [0, 1, 2, 3, 4].map(|glyph| Font.glyph_name(font, glyph))
				if actual == [Ok(".notdef"), Ok("last.alt"), Ok("dcroat"), Ok("first.alt"), Ok("last.alt")] {
					True
				} else {
					crash "post format 2 names: ${Str.inspect(actual)}"
				}
			}
			Err(problems) => crash "post format 2 font: ${Str.inspect(problems)}"
		}
	}
}
