import build.FontBuild
import font.Font

ArabicShapeTests :: {}.{}

# Lookup index order differs from Arabic feature order. locl makes the
# input that init consumes. rlig then consumes init and fina's outputs
# before calt substitutes the ligature.
face : Font
face = fixture(False)

fixture : Bool -> Font
fixture = |grow| {
	required = if (grow) { kind: 2, subtables: [FontBuild.multiple([12], [List.repeat(16, 32)])] } else { kind: 4, subtables: [FontBuild.ligature([12], [[{ glyph: 15, rest: [9] }]])] }
	gsub = FontBuild.layout(
		"arab",
		[
			{ tag: "calt", lookups: [1] },
			{ tag: "fina", lookups: [2] },
			{ tag: "init", lookups: [3] },
			{ tag: "isol", lookups: [5] },
			{ tag: "locl", lookups: [4] },
			{ tag: "rlig", lookups: [0] },
		],
		[
			required,
			{ kind: 1, subtables: [FontBuild.single2([15], [16])] },
			{ kind: 1, subtables: [FontBuild.single2([2, 14], [9, 8])] },
			{ kind: 1, subtables: [FontBuild.single2([14], [12])] },
			{ kind: 1, subtables: [FontBuild.single2([1], [14])] },
			{ kind: 1, subtables: [FontBuild.single2([2, 14], [7, 6])] },
		],
	)
	cmap = FontBuild.cmap([
		{
			system: 3,
			encoding: 10,
			subtable: FontBuild.cmap12([
				{ first: ' ', last: ' ', glyph: 5 },
				{ first: 0x0627, last: 0x0627, glyph: 2 },
				{ first: 0x0644, last: 0x0644, glyph: 1 },
				{ first: 0x064E, last: 0x064E, glyph: 3 },
			]),
		},
	])
	gpos = FontBuild.layout("arab", [{ tag: "kern", lookups: [0] }], [{ kind: 2, subtables: [FontBuild.pair1(4, 0, [{ glyph: 17, pairs: [{ second: 17, values: [0] }] }])] }])
	bytes = FontBuild.glyphs_font(List.repeat(500, 18), cmap, [{ tag: "GSUB", data: gsub }, { tag: "GPOS", data: gpos }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "Arabic stage fixture did not read strictly"
}

opts : Font.ShapeOptions
opts = Font.ShapeOptions.{ script: "Arab", language: "ar" }

expect {
	plan = Font.plan(face, opts)
	match Font.shape_traced(face, plan, "لا") {
		Ok({ run, origins }) =>
			run.glyphs == [16] and run.clusters == [0] and run.flags == [0]
				and origins == [Ligature({ feature: "calt", components: 2 })]
				and Font.cluster_ranges(run, 4) == [{ start: 0, end: 4 }]
		Err(_) => False
	}
}

expect {
	run = Font.shape(face, "لا", Font.ShapeOptions.{ script: "Arab", language: "ar", features: [Font.Feature.{ tag: "rlig", value: 0 }] })
	run.glyphs == [9, 12] and run.clusters == [2, 0] and run.flags == [1, 0]
}

# ZWJ participates in joining but the required ligature does not skip it.
expect {
	run = Font.shape(face, "ل\u(200D)ا", opts)
	run.glyphs == [9, 5, 12] and run.clusters == [5, 0, 0] and run.flags == [1, 0, 0]
}

expect {
	run = Font.shape(face, "ل\u(200C)ا", opts)
	run.glyphs == [7, 5, 6] and run.clusters == [5, 2, 0] and run.flags == [0, 0, 0]
}

expect {
	left = Font.shape(face, "ل", Font.ShapeOptions.{ script: "Arab", arabic_context: Font.ArabicContext.{ after: "َا" } })
	right = Font.shape(face, "ل", Font.ShapeOptions.{ script: "Arab", arabic_context: Font.ArabicContext.{ before: "لَ" } })
	edge = Font.shape(face, "ل", opts)
	outside = Font.shape(face, "ل", Font.ShapeOptions.{ script: "Arab", arabic_context: Font.ArabicContext.{ after: "َََََا" } })
	left.glyphs == [12] and right.glyphs == [8] and edge.glyphs == [6] and outside.glyphs == [6]
		and left.clusters == [0] and right.clusters == [0] and left.flags == [0] and right.flags == [0]
}

# A deliberately expansive, valid rlig runs after joining and obeys the
# common shaping budget. It leaves every source cluster represented.
expect {
	growing = fixture(True)
	text = Str.repeat("لا", 600)
	options = Font.ShapeOptions.{ script: "Arab", limits: Font.ShapeLimits.{ growth: 1 } }
	normal = Font.shape(growing, text, opts)
	match Font.shape_checked(growing, Font.plan(growing, options), text) {
		Err(OverBudget({ run, budgets })) =>
			budgets == [Growth] and normal.glyphs.len() == 19_800
				and run.glyphs.len() <= 16_384 and run.glyphs.len() > 1200
				and run.clusters.first() == Ok(2398) and run.clusters.last() == Ok(0)
				and run == Font.shape(growing, text, options)
		Ok(_) => False
	}
}
