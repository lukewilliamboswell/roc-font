import build.FontBuild
import font.Font
import fuzz.Solve

# OpenType cmap format 10. A uint32 start and count describe an array
# of uint16 glyphs. Roc bounds the whole span to Unicode before it
# reads the array. Only the selected map supplies nominal glyphs.
# https://learn.microsoft.com/en-us/typography/opentype/spec/cmap#format-10-trimmed-array
TrimmedCmap := {}.{
	check : {} -> Bool
	check = |_| {
		span_bound({})
			and [0x41, 0x10FFFC].all(agrees)
			and rejects(0x10FFFD, [3, 0, 1, 2])
			and rejects(0xFFFFFFFF, [3])
	}
}

# The 33-bit sum holds both complete uint32 fields. An independent
# formulation budgets the number of codes remaining after the first,
# and includes only starts at or below the end of Unicode. Bytes are
# checked separately: a 20-byte header, then two bytes per array entry.
span_bound : {} -> Bool
span_bound = |_| {
	verdict = Solve.prove_within(
		{ first: Solve.u32, count: Solve.u32 }.Solve,
		|v| {
			first = v.first.to_width(33)
			count = v.count.to_width(33)
			limit = Solve.Uint.from_u64(0x110000).to_width(33)
			allows = Solve.all([first.lte(limit), count.lte(limit - first)])
			ends_inside = (first + count).lte(limit)
			Solve.all([allows.implies(ends_inside), ends_inside.implies(allows)])
		},
		1024,
	)
	match verdict {
		Ok(Proved) => True
		other => crash "format 10 span bound: ${Str.inspect(other)}"
	}
}

fixture : U64, List(U64) -> List(U8)
fixture = |first, glyphs| {
	full = { system: 0, encoding: 4, subtable: FontBuild.cmap10(first, glyphs) }
	# B is mapped in the BMP subtable but lies in the hole in the
	# low format 10 fixture, and outside its high counterpart.
	bmp = { system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 'B', last: 'B', delta: 0, glyphs: [2] }]) }
	FontBuild.glyphs_font([500, 600, 700, 800], FontBuild.cmap([full, bmp]), [])
}

agrees : U64 -> Bool
agrees = |first| {
	font = Font.from_bytes(fixture(first, [3, 0, 1, 2]), Font.ReadOptions.{ strict: True }) ?? crash "valid format 10 span rejected"
	base = first.to_u32_wrap()
	codes = [base - 1, base, base + 1, base + 2, base + 3, base + 4]
	actual = codes.map(|cp| Font.glyph(font, cp))
	actual == [Err(Missing), Ok(3), Err(Missing), Ok(1), Ok(2), Err(Missing)]
		and Font.glyph(font, 'B') == Err(Missing)
		and Font.code_points(font) == [base, base + 2, base + 3]
}

rejects : U64, List(U64) -> Bool
rejects = |first, glyphs| {
	match Font.from_bytes(fixture(first, glyphs), Font.ReadOptions.{ strict: True }) {
		Err([BadTable({ table: "cmap", offset: _ })]) => True
		_ => False
	}
}
