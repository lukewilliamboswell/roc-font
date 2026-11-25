import build.FontBuild
import font.Font

# HarfBuzz tries the next alternate subtable if the ordinal is unavailable.
# https://learn.microsoft.com/en-us/typography/opentype/spec/gsub#lookup-type-3-subtable-alternate-substitution
# https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/OT/Layout/GSUB/AlternateSet.hh
AlternateRanges := [].{
	check : {} -> Bool
	check = |{}| {
		face = fixture({})
		first = [
			Font.Feature.{ tag: "cv01", value: 2, start: 1, end: 11 },
			Font.Feature.{ tag: "cv01", start: 1, end: 3 },
			Font.Feature.{ tag: "cv01", value: 3, start: 3, end: 7 },
			# Starts inside the four-byte scalar, whose cluster is 3.
			Font.Feature.{ tag: "cv01", value: 0, start: 4, end: 7 },
			Font.Feature.{ tag: "cv01", value: 0, start: 8, end: 10 },
			Font.Feature.{ tag: "cv01", value: 3, start: 10, end: 11 },
			Font.Feature.{ tag: "salt", start: 7, end: 9 },
		]
		both = first.concat([
			Font.Feature.{ tag: "cv02", start: 7, end: 11 },
			Font.Feature.{ tag: "cv02", value: 0, start: 9, end: 10 },
		])
		clusters = [0, 1, 3, 7, 8, 9, 10]
		# The first subtable has two choices. At byte 3 the later one
		# supplies choice 3. At byte 8, only salt replaces the glyph.
		check_directions(face, first, [1, 2, 6, 3, 7, 1, 6], clusters)
		# HarfBuzz combines feature masks in the shared lookup. The
		# cv02 field pushes the ordinal beyond both shared subtables.
		# Salt still replaces the glyphs at 7 and 8.
		check_directions(face, both, [1, 2, 6, 7, 7, 1, 1], clusters)
		True
	}
}

check_directions : Font, List(Font.Feature), List(U32), List(U64) -> {}
check_directions = |face, features, glyphs, clusters| {
	rows = glyphs.map2(clusters, |glyph, cluster| (glyph, cluster))
	for rtl in [False, True] {
		options = Font.ShapeOptions.{
			script: if (rtl) "Hebr" else "Latn",
			direction: if (rtl) RightToLeft else LeftToRight,
			features,
		}
		run = Font.shape(face, "Aא😀AAAA", options)
		want = if (rtl) rows.fold([], |rev, row| rev.prepend(row)) else rows
		got = run.glyphs.map2(run.clusters, |glyph, cluster| (glyph, cluster))
		if got != want or run.flags != List.repeat(0, want.len()) {
			crash "expected ${Str.inspect(want)} without break flags, got ${Str.inspect((got, run.flags))}"
		}
	}
}

alternates : List(U64) -> List(U8)
alternates = |glyphs| FontBuild.pack([
	U16(1),
	Ref(FontBuild.coverage1([1])),
	U16(1),
	Ref(FontBuild.pack([U16(glyphs.len())].concat(glyphs.map(|glyph| U16(glyph))))),
])

fixture : {} -> Font
fixture = |{}| {
	gsub = FontBuild.layout(
		"DFLT",
		[{ tag: "cv01", lookups: [0] }, { tag: "cv02", lookups: [0] }, { tag: "salt", lookups: [1] }],
		[
			{ kind: 3, subtables: [alternates([2, 3]), alternates([4, 5, 6])] },
			{ kind: 3, subtables: [alternates([7])] },
		],
	)
	cmap = FontBuild.cmap([
		{
			system: 3,
			encoding: 10,
			subtable: FontBuild.cmap12([
				{ first: 'A', last: 'A', glyph: 1 },
				{ first: 0x05D0, last: 0x05D0, glyph: 1 },
				{ first: 0x1F600, last: 0x1F600, glyph: 1 },
			]),
		},
	])
	bytes = FontBuild.glyphs_font(List.repeat(500, 8), cmap, [{ tag: "GSUB", data: gsub }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "alternate fixture did not read strictly"
}
