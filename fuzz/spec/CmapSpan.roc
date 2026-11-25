import build.FontBuild
import font.Font
import fuzz.Solve

# OpenType 1.9.1 cmap, Format 4. Each range offset counts from its own
# word. The same glyph array word can serve several segments, even with
# different deltas. A stored zero bypasses the delta.
# https://learn.microsoft.com/en-us/typography/opentype/spec/cmap#format-4-segment-mapping-to-delta-values
CmapSpan := {}.{
	check : {} -> Bool
	check = |_| final_word_fits({}) and [0, 32740].all(read_at_padding)
}

# In a four-segment layout, the first two idRangeOffset fields are at
# bytes 40 and 42. The first segment uses the last two glyph words and
# the second uses three. For every legal even length with room for the
# array, both offsets must fit as uint16 and share the final glyph word.
final_word_fits : {} -> Bool
final_word_fits = |_| {
	verdict = Solve.prove_within(
		Solve.u16,
		|tail| {
			padding = tail.to_width(17)
			length = 54 + 2 * padding
			first_offset = 2 * (padding + 5)
			second_offset = 2 * (padding + 3)
			first_last = 40 + first_offset + 2
			second_last = 42 + second_offset + 4
			padding.lte(32740).implies(
				Solve.all([
					first_offset.lte(65534),
					second_offset.lte(65534),
					first_last.eq(second_last),
					(first_last + 2).eq(length),
				]),
			)
		},
		2048,
	)
	match verdict {
		Ok(Proved) => True
		other => crash "cmap format 4 range offset proof: ${Str.inspect(other)}"
	}
}

read_at_padding : U64 -> Bool
read_at_padding = |padding| {
	# A–B use the suffix [0, 3], E–G use all [1, 0, 3], and J uses
	# just [1]. The referenced slices overlap and appear in reverse
	# order. The last referenced word ends at the declared length.
	segments = FontBuild.cmap4([
		{ first: 'A', last: 'B', delta: 1, glyphs: [] },
		{ first: 'E', last: 'G', delta: 65535, glyphs: [] },
		{ first: 'J', last: 'J', delta: 2, glyphs: [] },
	])
	range_words = FontBuild.pack([U16(2 * (padding + 5)), U16(2 * (padding + 3)), U16(2 * (padding + 2))])
	array = List.repeat(0, 2 * padding).concat(FontBuild.pack([U16(1), U16(0), U16(3)]))
	patched_length = FontBuild.patch(segments, 2, FontBuild.u16(segments.len() + array.len()))
	subtable = FontBuild.patch(patched_length, 40, range_words).concat(array)
	cmap = FontBuild.cmap([{ system: 3, encoding: 1, subtable }])
	bytes = FontBuild.glyphs_font([0, 100, 200, 300, 400], cmap, [])
	font = Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "valid cmap format 4 glyph array rejected at length ${subtable.len().to_str()}"
	points = ['@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K']
	points.map(|point| Font.glyph(font, point)) == [Err(Missing), Err(Missing), Ok(4), Err(Missing), Err(Missing), Err(Missing), Err(Missing), Ok(2), Err(Missing), Err(Missing), Ok(3), Err(Missing)]
}
