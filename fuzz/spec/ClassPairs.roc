import build.FontBuild
import font.Font

# OpenType 1.9.1 GPOS, PairPos formats 1 and 2, and Layout Common Table
# Formats, Lookup and Class Definition tables.
# https://learn.microsoft.com/en-us/typography/opentype/spec/gpos
# https://learn.microsoft.com/en-us/typography/opentype/spec/chapter2
# Coverage gates the first glyph, including class 0. A covered class
# cell with zero values still matches and can consume the second glyph.
ClassPairs := {}.{
	check : {} -> Bool
	check = |_| {
		for order in [PrimaryFirst, ExceptionsFirst] {
			class_font = fixture(class_pairs, order)
			explicit_font = fixture(explicit_pairs, order)
			for case in cases(order) {
				want = (case.glyphs, case.advances.map(|x| { x, y: 0 }), case.offsets.map(|x| { x, y: 0 }))
				class_run = positioned(class_font, case.text)
				explicit_run = positioned(explicit_font, case.text)
				if class_run != want or explicit_run != want {
					crash "pair positioning for ${case.text}, ${Str.inspect(order)}: expected ${Str.inspect(want)}, class ${Str.inspect(class_run)}, explicit ${Str.inspect(explicit_run)}"
				}
			}
		}
		True
	}
}

Order : [PrimaryFirst, ExceptionsFirst]

class_pairs : List(U8)
class_pairs = FontBuild.pair2(
	5,
	1,
	FontBuild.coverage1([1]),
	FontBuild.classes2([]),
	FontBuild.classes2([{ first: 3, last: 3, class: 1 }, { first: 5, last: 6, class: 1 }]),
	1,
	2,
	[0, 0, 0, 3, -30, 7],
)

explicit_pairs : List(U8)
explicit_pairs = FontBuild.pair1(
	5,
	1,
	[
		{
			glyph: 1,
			pairs: [
				{ second: 0, values: [0, 0, 0] },
				{ second: 1, values: [0, 0, 0] },
				{ second: 2, values: [0, 0, 0] },
				{ second: 3, values: [3, -30, 7] },
				{ second: 4, values: [0, 0, 0] },
				{ second: 5, values: [3, -30, 7] },
				{ second: 6, values: [3, -30, 7] },
				{ second: 7, values: [0, 0, 0] },
			],
		},
	],
)

fixture : List(U8), Order -> Font
fixture = |primary, order| {
	exceptions = FontBuild.pair1(
		5,
		0,
		[
			{ glyph: 1, pairs: [{ second: 2, values: [12, -40] }] },
			{ glyph: 2, pairs: [{ second: 3, values: [-9, 25] }] },
			{ glyph: 3, pairs: [{ second: 2, values: [6, 20] }] },
		],
	)
	subtables = if (order == PrimaryFirst) [primary, exceptions] else [exceptions, primary]
	# Set 0 admits E (glyph 5) and skips F (glyph 6).
	gpos = FontBuild.flagged_layout("kern", [{ kind: 2, flag: 0x10, set: 0, subtables }])
	cmap = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 'A', last: 'G', delta: 65536 - 64, glyphs: [] }]) }])
	bytes = FontBuild.glyphs_font([500, 500, 500, 500, 500, 0, 0, 500], cmap, [{ tag: "GDEF", data: FontBuild.marks_gdef }, { tag: "GPOS", data: gpos }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "valid pair positioning fixture did not read strictly"
}

cases : Order -> List({ text : Str, glyphs : List(U32), advances : List(I32), offsets : List(I32) })
cases = |order| {
	# Across F, AB's class (0, 0) shadows the exception and consumes B.
	# The exception has no second value record, so when it wins, BC applies.
	(advances, offsets) = if (order == PrimaryFirst) ([500, 0, 500, 500], [0, 0, 0, 0]) else ([460, 0, 525, 500], [12, 0, -9, 0])
	[
		{ text: "AFBC", glyphs: [1, 6, 2, 3], advances, offsets },
		# E is visible, so AE uses (0, 1), then BC can apply.
		{ text: "AEBC", glyphs: [1, 5, 2, 3], advances: [470, 0, 525, 500], offsets: [3, 7, -9, 0] },
		# C is class 0 on the left but is outside first-glyph coverage.
		{ text: "CBA", glyphs: [3, 2, 1], advances: [520, 500, 500], offsets: [6, 0, 0] },
	]
}

positioned : Font, Str -> (List(U32), List({ x : I32, y : I32 }), List({ x : I32, y : I32 }))
positioned = |font, content| {
	run = Font.shape(font, content, Font.ShapeOptions.{ script: "Latn" })
	(run.glyphs, run.advances, run.offsets)
}
