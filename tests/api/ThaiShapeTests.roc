import build.FontBuild
import font.Font

ThaiShapeTests := {}.{}

# In font units, the base's anchors are (340,350) for tone and
# (210,250) for nikhahit. Its advance is 500.
face : Font
face = {
	mark_base = attachment(
		[3, 5],
		1,
		[U16(0), Ref(anchor(20, 30)), U16(1), Ref(anchor(5, 10))],
		2,
		[Ref(anchor(340, 350)), Ref(anchor(210, 250))],
	)
	mark_mark = attachment([3], 5, [U16(0), Ref(anchor(10, 20))], 1, [Ref(anchor(50, 70))])
	gpos = FontBuild.layout(
		"thai",
		[{ tag: "mark", lookups: [0] }, { tag: "mkmk", lookups: [1] }],
		[
			{ kind: 4, subtables: [mark_base] },
			{ kind: 6, subtables: [mark_mark] },
		],
	)
	# The font has a Thai GSUB script. The optional stylistic lookup is
	# unrelated to preprocessing and never applies in these tests.
	gsub = FontBuild.layout("thai", [{ tag: "ss01", lookups: [0] }], [{ kind: 1, subtables: [FontBuild.single2([7], [7])] }])
	cmap = FontBuild.cmap([
		{
			system: 3,
			encoding: 10,
			subtable: FontBuild.cmap12([
				{ first: 0x0E14, last: 0x0E14, glyph: 1 },
				{ first: 0x0E32, last: 0x0E32, glyph: 6 },
				{ first: 0x0E33, last: 0x0E33, glyph: 4 },
				{ first: 0x0E4B, last: 0x0E4B, glyph: 3 },
				{ first: 0x0E4D, last: 0x0E4D, glyph: 5 },
				{ first: 0x25CC, last: 0x25CC, glyph: 7 },
			]),
		},
	])
	gdef = FontBuild.pack([U32(0x00010000), Ref(FontBuild.classes1(1, [1, 0, 3, 1, 3, 1, 1])), U16(0), U16(0), U16(0)])
	bytes = FontBuild.glyphs_font(
		[500, 500, 0, 100, 500, 100, 500, 500],
		cmap,
		[
			{ tag: "GDEF", data: gdef },
			{ tag: "GPOS", data: gpos },
			{ tag: "GSUB", data: gsub },
		],
	)
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "Thai anchor fixture did not read strictly"
}

anchor : I64, I64 -> List(U8)
anchor = |x, y| FontBuild.pack([U16(1), I16(x), I16(y)])

attachment : List(U64), U64, List(FontBuild.Field), U64, List(FontBuild.Field) -> List(U8)
attachment = |marks, target, mark_fields, classes, target_fields| FontBuild.pack([
	U16(1),
	Ref(FontBuild.coverage1(marks)),
	Ref(FontBuild.coverage1([target])),
	U16(classes),
	Ref(FontBuild.pack([U16(marks.len())].concat(mark_fields))),
	Ref(FontBuild.pack([U16(1)].concat(target_fields))),
])

opts : Font.ShapeOptions
opts = Font.ShapeOptions.{ script: "Thai", language: "th" }

expect {
	run = Font.shape(face, "ด๋ำ", opts)
	# Nikhahit attaches to the base and the following tone attaches to
	# nikhahit. The tone's offset includes nikhahit's movement.
	run.glyphs == [1, 5, 3, 6] and run.clusters == [0, 0, 0, 0]
		and run.advances.map(|a| a.x) == [500, 0, 0, 500]
		and run.offsets == xy([(0, 0), (-295, 240), (-255, 290), (0, 0)])
		and run.flags == [0, 0, 0, 0]
}

expect {
	run = Font.shape(face, "ด๋ํา", opts)
	# Authored nikhahit follows the tone, so both marks attach to the base.
	run.glyphs == [1, 3, 5, 6] and run.clusters == [0, 0, 0, 9]
		and run.advances.map(|a| a.x) == [500, 0, 0, 500]
		and run.offsets == xy([(0, 0), (-180, 320), (-295, 240), (0, 0)])
		and run.flags == [0, 0, 0, 0]
}

expect {
	run = Font.shape(face, "ด๋ำ", Font.ShapeOptions.{ script: "Thai", language: "th", clusters: Characters, features: [Font.Feature.{ tag: "mkmk", value: 0 }] })
	run.glyphs == [1, 5, 3, 6] and run.clusters == [0, 3, 3, 3]
		and run.offsets == xy([(0, 0), (-295, 240), (-180, 320), (0, 0)])
		and run.flags == [0, 1, 1, 1]
}

expect {
	run = Font.shape(face, "๋", opts)
	run.glyphs == [3] and run.clusters == [0] and run.flags == [0]
		and run.advances == xy([(0, 0)]) and run.offsets == xy([(0, 0)])
}

expect {
	limited = Font.plan(face, Font.ShapeOptions.{ script: "Thai", language: "th", limits: Font.ShapeLimits.{ growth: 1 } })
	fits = Font.shape_checked(face, limited, Str.repeat("ำ", 8192))
	stops = Font.shape_checked(face, limited, Str.repeat("ำ", 8193))
	match (fits, stops) {
		(Ok(complete), Err(OverBudget({ run, budgets: [Growth] }))) =>
			complete.glyphs.len() == 16384 and run.glyphs.len() == 16384
				and complete.glyphs.last() == Ok(6)
				and run.glyphs.drop_first(16382) == [4, 4]
		_ => False
	}
}

xy : List((I32, I32)) -> List({ x : I32, y : I32 })
xy = |points| points.map(|(x, y)| { x, y })
