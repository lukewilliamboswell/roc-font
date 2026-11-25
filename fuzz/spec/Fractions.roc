import build.FontBuild
import font.Font

# U+2044 between decimal digits can activate automatic fraction forms.
# HarfBuzz requires 'frac' or both 'numr' and 'dnom', and applies explicit
# feature ranges after the automatic masks.
# https://learn.microsoft.com/en-us/typography/opentype/spec/features_fj#tag-frac
# https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/hb-ot-shape.cc#L641
Fractions := [].{
	check : {} -> Bool
	check = |{}| {
		text = "²1⁄٢⁄1/٢²"
		clusters = [0, 2, 3, 6, 8, 11, 12, 13, 15]
		unsafe = [0, 0, 1, 1, 1, 1, 0, 0, 0]
		all = fixture(All)
		pair = [1, 4, 2, 6, 2, 5, 2, 1, 1]
		latin = Font.ShapeOptions.{ script: "Latn" }
		options = Font.ShapeOptions.{
			script: "Latn",
			features: [
				Font.Feature.{ tag: "numr", value: 0, start: 2, end: 8 },
				Font.Feature.{ tag: "numr", start: 6, end: 8 },
				# Byte 7 is inside the Arabic-Indic digit, whose cluster is 6.
				Font.Feature.{ tag: "numr", value: 0, start: 7, end: 8 },
				Font.Feature.{ tag: "dnom", value: 0, start: 6, end: 8 },
				Font.Feature.{ tag: "frac", value: 0, start: 3, end: 8 },
			],
		}
		# The middle digit is the denominator of one fraction and the
		# numerator of the next. Its combined form is glyph 11.
		check_run(all, text, latin, ([1, 9, 8, 11, 8, 10, 2, 1, 1], clusters, unsafe))
		check_run(fixture(Pair), text, latin, (pair, clusters, unsafe))
		check_run(fixture(OnlyNumerators), text, latin, ([1, 1, 2, 1, 2, 1, 2, 1, 1], clusters, List.repeat(0, 9)))
		check_run(fixture(OnlyFraction), text, latin, ([1, 7, 8, 7, 8, 7, 2, 1, 1], clusters, unsafe))
		check_run(all, text, Font.ShapeOptions.{ script: "Latn", features: [Font.Feature.{ tag: "frac", value: 0 }] }, (pair, clusters, unsafe))
		check_run(all, text, options, ([1, 7, 2, 4, 8, 10, 2, 1, 1], clusters, unsafe))
		# Consecutive slashes cannot share digits across the gap.
		check_run(all, "1⁄⁄٢⁄1", latin, ([1, 2, 2, 9, 8, 10], [0, 1, 4, 7, 9, 12], [0, 0, 0, 0, 1, 1]))
		hebrew = Font.ShapeOptions.{ script: "Hebr", direction: RightToLeft }
		check_run(all, "א1⁄٢⁄1", hebrew, ([9, 8, 11, 8, 10, 3], [11, 8, 6, 3, 2, 0], [1, 1, 1, 1, 0, 0]))
		True
	}
}

FeatureSet : [All, Pair, OnlyNumerators, OnlyFraction]

# The decimal digits and the superscript share glyph 1. The two slashes
# share glyph 2. Automatic forms depend on the source characters.
fixture : FeatureSet -> Font
fixture = |selection| {
	numerator = { tag: "numr", lookups: [0] }
	denominator = { tag: "dnom", lookups: [1] }
	fraction = { tag: "frac", lookups: [2] }
	features = match selection {
		All => [denominator, fraction, numerator]
		Pair => [denominator, numerator]
		OnlyNumerators => [numerator]
		OnlyFraction => [fraction]
	}
	gsub = FontBuild.layout(
		"DFLT",
		features,
		[
			{ kind: 1, subtables: [FontBuild.single2([1], [4])] },
			{ kind: 1, subtables: [FontBuild.single2([1, 4], [5, 6])] },
			{ kind: 1, subtables: [FontBuild.single2([1, 2, 4, 5, 6], [7, 8, 9, 10, 11])] },
		],
	)
	cmap = FontBuild.cmap([
		{
			system: 3,
			encoding: 10,
			subtable: FontBuild.cmap12([
				{ first: '/', last: '/', glyph: 2 },
				{ first: '1', last: '1', glyph: 1 },
				{ first: 0xB2, last: 0xB2, glyph: 1 },
				{ first: 0x05D0, last: 0x05D0, glyph: 3 },
				{ first: 0x0662, last: 0x0662, glyph: 1 },
				{ first: 0x2044, last: 0x2044, glyph: 2 },
			]),
		},
	])
	bytes = FontBuild.glyphs_font(List.repeat(500, 12), cmap, [{ tag: "GSUB", data: gsub }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "fraction fixture did not read strictly"
}

check_run : Font, Str, Font.ShapeOptions, (List(U32), List(U64), List(U8)) -> {}
check_run = |font, text, options, expected| {
	run = Font.shape(font, text, options)
	got = (run.glyphs, run.clusters, run.flags)
	if got != expected {
		crash "for ${text}, expected ${Str.inspect(expected)}, got ${Str.inspect(got)}"
	}
}
