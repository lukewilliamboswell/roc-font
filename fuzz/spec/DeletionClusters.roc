import build.FontBuild
import font.Font

# HarfBuzz 14.6.0 supports an empty MultipleSubst sequence for Uniscribe
# compatibility. An independent FontTools face with the same lookups
# produced the clusters, advances and unsafe-to-break flags below.
# https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/OT/Layout/GSUB/Sequence.hh
DeletionClusters := {}.{
	check : {} -> Bool
	check = |_| {
		font = fixture({})
		for case in cases {
			features = if (case.masked) [Font.Feature.{ tag: "kern", value: 0, start: 0, end: 2 }] else []
			run = Font.shape(font, case.text, Font.ShapeOptions.{ features })
			want = {
				glyphs: [1, 2],
				clusters: case.clusters,
				advances: [{ x: case.advance, y: 0 }, { x: 500, y: 0 }],
				offsets: List.repeat({ x: 0, y: 0 }, 2),
				flags: [0, case.flag],
			}
			if run != want {
				crash "deletion in ${case.text} with kern masked = ${Str.inspect(case.masked)}: expected ${Str.inspect(want)}, got ${Str.inspect(run)}"
			}
		}
		True
	}
}

fixture : {} -> Font
fixture = |_| {
	cmap = FontBuild.cmap([
		{
			system: 3,
			encoding: 10,
			subtable: FontBuild.cmap12([
				{ first: 0x41, last: 0x42, glyph: 1 },
				{ first: 0x00F8, last: 0x00F8, glyph: 3 },
			]),
		},
	])
	gsub = FontBuild.layout(
		"latn",
		[{ tag: "ccmp", lookups: [0] }],
		[
			{ kind: 2, subtables: [FontBuild.multiple([3], [[]])] },
		],
	)
	gpos = FontBuild.layout(
		"latn",
		[{ tag: "kern", lookups: [0] }],
		[
			{ kind: 2, subtables: [FontBuild.pair1(4, 0, [{ glyph: 1, pairs: [{ second: 2, values: [-21] }] }])] },
		],
	)
	bytes = FontBuild.glyphs_font(List.repeat(500, 4), cmap, [{ tag: "GSUB", data: gsub }, { tag: "GPOS", data: gpos }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "GSUB deletion fixture did not read strictly"
}

cases : List({ text : Str, masked : Bool, clusters : List(U64), advance : I32, flag : U8 })
cases = [
	# Identical glyphs and clusters after deletion can have distinct feature
	# masks. The surviving A keeps its own mask when it acquires ø's cluster.
	{ text: "øAB", masked: False, clusters: [0, 3], advance: 479, flag: 1 },
	{ text: "AøB", masked: False, clusters: [0, 3], advance: 479, flag: 1 },
	{ text: "øAB", masked: True, clusters: [0, 3], advance: 479, flag: 1 },
	{ text: "AøB", masked: True, clusters: [0, 3], advance: 500, flag: 0 },
	{ text: "øøAB", masked: True, clusters: [0, 5], advance: 479, flag: 1 },
	{ text: "ABø", masked: False, clusters: [0, 1], advance: 479, flag: 1 },
]
