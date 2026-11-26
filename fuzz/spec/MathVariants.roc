import build.FontBuild
import font.Font
import fuzz.Solve

# OpenType 1.9.1, Device table and MathVariants.
# https://learn.microsoft.com/en-us/typography/opentype/spec/chapter2#device-and-variationindex-tables
# https://learn.microsoft.com/en-us/typography/opentype/spec/math#mathvariants-table
MathVariants := [].{
	check : {} -> Bool
	check = |{}| [(1, 8), (2, 4), (3, 2)].all(
		|(format, per_word)| words_fit(per_word)
			and constructions(format, per_word, 1)
			and constructions(format, per_word + 1, 2),
	)
}

# Inclusive uint16 PPEM endpoints give at most 65536 entries. Prove the
# reader's formula selects the least number of packed 16-bit words that
# covers every entry, including when the final word is completely full.
words_fit : U64 -> Bool
words_fit = |per_word| {
	verdict = Solve.prove_within(
		{ first: Solve.u16, last: Solve.u16 }.Solve,
		|v| {
			first = v.first.to_width(17)
			last = v.last.to_width(17)
			width = Solve.Uint.from_u64(per_word).to_width(17)
			span = last - first
			words = span // width + 1
			count = span + 1
			first.lte(last).implies(
				Solve.all([(words * width).gte(count), ((words - 1) * width).lt(count)]),
			)
		},
		3000,
	)
	match verdict {
		Ok(Proved) => True
		other => crash "MATH Device word-count proof for ${per_word.to_str()}: ${Str.inspect(other)}"
	}
}

variant : U64, U64 -> List(U8)
variant = |glyph, advance| FontBuild.pack([U16(0), U16(1), U16(glyph), U16(advance)])

assembled : I64, U64, List(U8) -> List(U8)
assembled = |italic, first, device| {
	assembly = FontBuild.pack([
		I16(italic),
		Ref(device),
		U16(2),
		U16(first),
		U16(0),
		U16(30),
		U16(120),
		U16(0),
		U16(first + 1),
		U16(30),
		U16(0),
		U16(160),
		U16(1),
	])
	FontBuild.pack([Ref(assembly), U16(0)])
}

fixture : U64, U64, U64 -> List(U8)
fixture = |format, count, words| {
	vertical = FontBuild.coverage2([{ first: 2, last: 2, index: 0 }, { first: 4, last: 5, index: 1 }])
	horizontal = FontBuild.coverage1([1, 4])
	varied = FontBuild.pack([U16(0), U16(0), U16(0x8000)])
	pixel = FontBuild.pack([U16(10), U16(9 + count), U16(format)].concat(List.repeat(U16(0xFFFF), words)))
	# The horizontal Device is the last subtable and ends with the MATH
	# table. There is no following payload to hide a one-word over-count.
	variants = FontBuild.pack([
		U16(20),
		Ref(vertical),
		Ref(horizontal),
		U16(3),
		U16(2),
		Ref(variant(11, 700)),
		Ref(assembled(12, 6, varied)),
		Ref(variant(12, 800)),
		Ref(variant(13, 900)),
		Ref(assembled(-9, 8, pixel)),
	])
	math = FontBuild.pack([U16(1), U16(0), Ref(List.repeat(0, 214)), Ref(List.repeat(0, 8)), Ref(variants)])
	store = FontBuild.variation_store(1, [[{ start: 0, peak: 16384, end: 16384 }]], [{ regions: [0], rows: [[40]] }])
	FontBuild.parity_font([
		{ tag: "fvar", data: FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 900 }]) },
		{ tag: "GDEF", data: FontBuild.gdef_store(store) },
		{ tag: "MATH", data: math },
	])
}

assembly_is : Font, Font.MathDirection, U32, I64 -> Bool
assembly_is = |font, direction, first, italic|
	Font.math_assembly(font, 4, direction) == Present({
		italic_correction: italic,
		parts: [
			{ glyph: first, start_connector: 0, end_connector: 30, full_advance: 120, extender: False },
			{ glyph: first + 1, start_connector: 30, end_connector: 0, full_advance: 160, extender: True },
		],
	})

constructions : U64, U64, U64 -> Bool
constructions = |format, count, words| {
	base = match Font.from_bytes(fixture(format, count, words), Font.ReadOptions.{ strict: True }) {
		Ok(value) => value
		Err(problems) => crash "MATH rejected ${count.to_str()} PPEM values in ${words.to_str()} words of format ${format.to_str()}: ${Str.inspect(problems)}"
	}
	peak = Font.at(base, Font.Variation.{ weight: Black })
	half = Font.at(peak, Font.Variation.{ weight: Weight(650) })
	reset = Font.at(half, Font.Variation.{})
	[2, 4, 5].map(|g| Font.math_variants(base, g, Vertical)) == [[{ glyph: 11, advance: 700 }], [], [{ glyph: 12, advance: 800 }]]
		and [1, 2, 4].map(|g| Font.math_variants(base, g, Horizontal)) == [[{ glyph: 13, advance: 900 }], [], []]
		and [(base, 12), (peak, 52), (half, 32), (reset, 12)].all(
			|(font, expected)| assembly_is(font, Vertical, 6, expected) and assembly_is(font, Horizontal, 8, -9),
		)
}
