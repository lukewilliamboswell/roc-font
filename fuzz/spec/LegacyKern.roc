import build.FontBuild
import font.Font

# HarfBuzz 14.6.0's legacy kern machine applies IgnoreMarks to the search
# for the second endpoint. When a mark is reached as the first endpoint,
# it can still start a pair. X is an ASCII letter mapped to a GDEF mark,
# so the fixture exercises the font's glyph class without Unicode composition.
# https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/hb-kern.hh
LegacyKern := {}.{
	check : {} -> Bool
	check = |_| {
		font = fixture({})
		for case in cases {
			features = if (case.masked) [Font.Feature.{ tag: "kern", value: 0, start: 1, end: 2 }] else []
			run = Font.shape(font, case.text, Font.ShapeOptions.{ features })
			want = { glyphs: case.glyphs, clusters: FontBuild.counting(case.glyphs.len()), advances: case.advances.map(|x| { x, y: 0 }), offsets: case.offsets.map(|x| { x, y: 0 }), flags: case.flags }
			if run != want {
				crash "legacy kern for ${case.text} with masked byte 1 = ${Str.inspect(case.masked)}: expected ${Str.inspect(want)}, got ${Str.inspect(run)}"
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
			encoding: 1,
			subtable: FontBuild.cmap4([
				{ first: 'A', last: 'C', delta: 65536 - 64, glyphs: [] },
				{ first: 'X', last: 'X', delta: 65536 - 84, glyphs: [] },
			]),
		},
	])
	gdef = FontBuild.pack([
		U32(0x00010000),
		Ref(
			FontBuild.classes2([
				{ first: 1, last: 3, class: 1 },
				{ first: 4, last: 4, class: 3 },
			]),
		),
		U16(0),
		U16(0),
		U16(0),
	])
	kern = FontBuild.kern([
		{
			coverage: 1,
			pairs: [
				{ left: 1, right: 2, value: -21 },
				{ left: 2, right: 1, value: 11 },
				{ left: 4, right: 2, value: 59 },
			],
		},
	])
	Font.from_bytes(
		FontBuild.glyphs_font(
			[500, 500, 500, 500, 0],
			cmap,
			[
				{ tag: "GDEF", data: gdef },
				{ tag: "kern", data: kern },
			],
		),
		Font.ReadOptions.{ strict: True },
	) ?? crash "legacy kern fixture did not read strictly"
}

cases : List({ text : Str, masked : Bool, glyphs : List(U32), advances : List(I32), offsets : List(I32), flags : List(U8) })
cases = [
	# Masking a skipped mark leaves the pair and the unsafe span intact.
	{ text: "AXXB", masked: False, glyphs: [1, 4, 4, 2], advances: [489, 0, 0, 490], offsets: [0, 0, 0, -10], flags: [0, 1, 1, 1] },
	{ text: "AXXB", masked: True, glyphs: [1, 4, 4, 2], advances: [489, 0, 0, 490], offsets: [0, 0, 0, -10], flags: [0, 1, 1, 1] },
	# Masking the second endpoint prevents the pair.
	{ text: "AB", masked: True, glyphs: [1, 2], advances: [500, 500], offsets: [0, 0], flags: [0, 0] },
	# The second endpoint can start a new pair across a different mark.
	{ text: "AXBXA", masked: False, glyphs: [1, 4, 2, 4, 1], advances: [489, 0, 495, 0, 506], offsets: [0, 0, -10, 0, 6], flags: [0, 1, 1, 1, 1] },
	# A base with no matching pair still ends the search for the second endpoint.
	{ text: "ACXB", masked: False, glyphs: [1, 3, 4, 2], advances: [500, 500, 0, 500], offsets: [0, 0, 0, 0], flags: [0, 0, 0, 0] },
	# Masking A after C resumes the scan at X. A first-endpoint mark keeps its
	# zero advance and receives the compensating offset from mark zeroing.
	{ text: "CAXB", masked: False, glyphs: [3, 1, 4, 2], advances: [500, 489, 0, 490], offsets: [0, 0, 0, -10], flags: [0, 0, 1, 1] },
	{ text: "CAXB", masked: True, glyphs: [3, 1, 4, 2], advances: [500, 500, 0, 530], offsets: [0, 0, -29, 30], flags: [0, 0, 0, 1] },
]
