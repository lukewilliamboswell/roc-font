import build.FontBuild
import font.Font

# HarfBuzz 14.6.0 uses each LangSys required feature at every cluster,
# including when user feature settings mask its tag. FeatureVariations
# can still replace the required feature's lookup list in either table.
RequiredFeatureVariations := {}.{
	check : {} -> Bool
	check = |_| {
		font = fixture({})
		var $at = font
		for (weight, glyph, advance, x) in [(400, 3, 780, 13), (600, 4, 880, 13), (700, 4, 830, 29), (400, 3, 780, 13)] {
			$at = Font.at($at, Font.Variation.{ weight: Weight(weight) })
			for mask in masks {
				run = Font.shape($at, "ABAB", Font.ShapeOptions.{ script: "Latn", clusters: Characters, features: mask })
				if run.glyphs != [glyph, 2, glyph, 2] or run.clusters != [0, 1, 2, 3] or run.flags != [0, 1, 1, 1]
					or run.advances != [{ x: advance, y: 0 }, { x: 700, y: 0 }, { x: advance, y: 0 }, { x: 700, y: 0 }]
					or run.offsets != [{ x, y: 0 }, { x: 0, y: 0 }, { x, y: 0 }, { x: 0, y: 0 }] {
					crash "required layout feature at ${weight.to_str()} with ${Str.inspect(mask)}: ${Str.inspect(run)}"
				}
			}
		}
		True
	}
}

masks : List(List(Font.Feature))
masks = [
	[],
	[Font.Feature.{ tag: "calt", value: 0 }, Font.Feature.{ tag: "kern", value: 0 }],
	[Font.Feature.{ tag: "calt", value: 0, start: 0, end: 1 }, Font.Feature.{ tag: "kern", value: 0, start: 2, end: 3 }],
]

required_layout : Str, I64, List({ kind : U64, subtables : List(List(U8)) }) -> List(U8)
required_layout = |tag, min, lookups| {
	variations = FontBuild.feature_variations([{ conditions: [{ axis: 0, min, max: 16384 }], substitutions: [{ feature: 0, lookups: [1] }] }])
	layout = FontBuild.layout_varied("latn", [{ tag, lookups: [0] }], lookups, variations)
	# After the 14-byte layout header, the script list and script table
	# take 8 and 4 bytes. In LangSys, set required index 0 and count 0.
	FontBuild.patch(layout, 28, FontBuild.pack([U16(0), U16(0)]))
}

fixture : {} -> Font
fixture = |_| {
	gsub = required_layout("calt", 8192, [3, 4].map(|glyph| { kind: 1, subtables: [FontBuild.single2([1], [glyph])] }))
	pair = |x, advance| {
		sets = [3, 4].map(|glyph| { glyph, pairs: [{ second: 2, values: [x, advance, 0] }] })
		{ kind: 2, subtables: [FontBuild.pair1(5, 4, sets)] }
	}
	gpos = required_layout("kern", 12288, [pair(13, -20), pair(29, -70)])
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'B', glyph: 1 }]) }])
	fvar = FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 800 }])
	bytes = FontBuild.glyphs_font([500, 600, 700, 800, 900], cmap, [{ tag: "fvar", data: fvar }, { tag: "GSUB", data: gsub }, { tag: "GPOS", data: gpos }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "required feature variation fixture rejected"
}
