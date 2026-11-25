import fuzz.Model
import fuzz.Target
import font.Font
import build.FontBuild

Gpos := [].{
	target : Target
	target = {
		machine = model(32)
		Model.walk_target({
			name: "gpos-pair-cursors",
			machine,
			examples: [
				Model.walk_example(machine, { name: "absent second record and pair fallthrough", revision: "1", trace: [Choose(Absent), Append('A'), Append('B'), Append('A'), Append('A')] }),
				Model.walk_example(machine, { name: "present zero second record", revision: "1", trace: [Choose(Zero), Append('A'), Append('B'), Append('A')] }),
				Model.walk_example(machine, { name: "all-zero pair shadows a nonzero alternative", revision: "1", trace: [Choose(Zero), Append('A'), Append('C'), Append('A')] }),
				Model.walk_example(machine, { name: "two nonzero records and a fresh lookup", revision: "1", trace: [Choose(Nonzero), Append('A'), Append('B'), Append('A')] }),
			],
		})
	}
}

# OpenType 1.9.1 GPOS, "Lookup type 2 subtable: pair adjustment
# positioning" and "ValueRecord", and Layout Common Table Formats,
# "Lookup table".
# https://learn.microsoft.com/en-us/typography/opentype/spec/gpos
# https://learn.microsoft.com/en-us/typography/opentype/spec/chapter2
# A matched pair ends the subtable search at that position, even if neither
# record changes a value. The next position in that lookup is the second
# glyph if ValueFormat2 is zero and the following glyph otherwise.
# Each lookup starts afresh and adds its adjustments to the run.
Second : [Absent, Zero, Nonzero]

State : [Unchosen, Text({ second : Second, bytes : List(U8) })]

Action : [Choose(Second), Append(U8)]

Point : { x : I32, y : I32 }

Adjustment : { advance : I32, offset : Point }

positioning_font : Second -> Font
positioning_font = |second| {
	# The primary subtable matches AB and AC. AC has no adjustment in
	# either record, but still shadows the AC entry of the next subtable.
	format2 = if (second == Absent) 0 else 7
	b = match second {
		Absent => []
		Zero => [0, 0, 0]
		Nonzero => [7, 4, -9]
	}
	c = if (second == Absent) [] else [0, 0, 0]
	primary = FontBuild.pair1(7, format2, [{ glyph: 1, pairs: [{ second: 2, values: [3, -4, -23].concat(b) }, { second: 3, values: [0, 0, 0].concat(c) }] }])
	fallback = FontBuild.pair1(
		7,
		0,
		[
			{ glyph: 1, pairs: [{ second: 1, values: [-5, 6, -31] }, { second: 2, values: [1, 2, -40] }, { second: 3, values: [2, 3, -50] }] },
			{ glyph: 2, pairs: [{ second: 1, values: [-2, 8, -11] }] },
			{ glyph: 3, pairs: [{ second: 1, values: [4, 2, -13] }] },
		],
	)
	# This lookup can apply both to the original AB and to the following BA,
	# even if the first lookup consumed B. It has no entry for AC or CA.
	additive = FontBuild.pair1(7, 0, [{ glyph: 1, pairs: [{ second: 2, values: [-1, 9, 17] }] }, { glyph: 2, pairs: [{ second: 1, values: [6, -3, -19] }] }])
	gpos = FontBuild.layout("DFLT", [{ tag: "kern", lookups: [0, 1] }], [{ kind: 2, subtables: [primary, fallback] }, { kind: 2, subtables: [additive] }])
	file = FontBuild.file(FontBuild.replace(FontBuild.basic, "GPOS", gpos))
	Font.from_bytes(file, Font.ReadOptions.{ strict: True }) ?? crash "the GPOS model font did not read strictly"
}

# In these tables only AB and AC can consume a position. At B or C the
# previous character determines whether that glyph can start a pair in
# lookup 0. The adjustments in lookup 1 depend only on the following
# character. Compute each glyph directly from its neighbourhood.
no_adjustment : Adjustment
no_adjustment = { advance: 0, offset: { x: 0, y: 0 } }

expected : Second, U8, U8, U8 -> Adjustment
expected = |second, prev, glyph, next| {
	consumed = second != Absent and prev == 'A' and (glyph == 'B' or glyph == 'C')
	first = match (glyph, next) {
		('A', 'A') => { advance: -31, offset: { x: -5, y: 6 } }
		('A', 'B') => { advance: -23, offset: { x: 3, y: -4 } }
		('B', 'A') if !consumed => { advance: -11, offset: { x: -2, y: 8 } }
		('C', 'A') if !consumed => { advance: -13, offset: { x: 4, y: 2 } }
		_ => no_adjustment
	}
	incoming = if (second == Nonzero and prev == 'A' and glyph == 'B') { advance: -9, offset: { x: 7, y: 4 } } else no_adjustment
	added = match (glyph, next) {
		('A', 'B') => { advance: 17, offset: { x: -1, y: 9 } }
		('B', 'A') => { advance: -19, offset: { x: 6, y: -3 } }
		_ => no_adjustment
	}
	{
		advance: first.advance + incoming.advance + added.advance,
		offset: {
			x: first.offset.x + incoming.offset.x + added.offset.x,
			y: first.offset.y + incoming.offset.y + added.offset.y,
		},
	}
}

model : U64 -> Model.Machine(State, Action)
model = |max_letters| {
	absent = positioning_font(Absent)
	zero = positioning_font(Zero)
	nonzero = positioning_font(Nonzero)
	{
		init: Unchosen,
		actions: |state| match state {
			Unchosen => [Choose(Absent), Choose(Zero), Choose(Nonzero)]
			Text({ second: _, bytes }) => if (bytes.len() < max_letters) [Append('A'), Append('B'), Append('C')] else []
		},
		step: |state, action| match (state, action) {
			(Unchosen, Choose(second)) => Text({ second, bytes: [] })
			(Text({ second, bytes }), Append(byte)) => Text({ second, bytes: bytes.append(byte) })
			_ => state
		},
		rules: [
			Model.always(
				"GPOS matches exact advances and placements across subtables and lookups",
				|state| match state {
					Unchosen => True
					Text({ second, bytes }) => {
						font = match second {
							Absent => absent
							Zero => zero
							Nonzero => nonzero
						}
						text = Str.from_utf8(bytes) ?? crash "the GPOS model alphabet must be ASCII"
						run = Font.shape(font, text, Font.ShapeOptions.{})
						want = bytes.map_with_index(|glyph, i| expected(second, if (i == 0) 0 else bytes.get(i - 1) ?? 0, glyph, bytes.get(i + 1) ?? 0))
						glyphs = bytes.map(|glyph| glyph.to_u32() - 64)
						advances = want.map2(glyphs, |adj, glyph| { x: 500 + 100 * glyph.to_i32_wrap() + adj.advance, y: 0 })
						run.glyphs == glyphs and run.clusters == FontBuild.counting(bytes.len()) and run.advances == advances and run.offsets == want.map(|adj| adj.offset)
					}
				},
			),
			Model.sometimes("a missing pair falls through despite first-glyph coverage", |state| state == Text({ second: Absent, bytes: ['A', 'B', 'A', 'A'] })),
			Model.sometimes("an absent second record leaves B available", |state| state == Text({ second: Absent, bytes: ['A', 'B', 'A'] })),
			Model.sometimes("a zero second record consumes B in only the first lookup", |state| state == Text({ second: Zero, bytes: ['A', 'B', 'A'] })),
			Model.sometimes("an all-zero match shadows and consumes", |state| state == Text({ second: Zero, bytes: ['A', 'C', 'A'] })),
			Model.sometimes("nonzero adjustments combine on both glyphs", |state| state == Text({ second: Nonzero, bytes: ['A', 'B', 'A'] })),
		],
	}
}

# All 0–5 letter strings over A, B and C, for the three second-record
# choices. The recipe choice itself is one action.
expect {
	report = Model.explore(model(5), Model.Options.{ depth: 7, key: |state| state })
	if (report.verdict, report.states, report.steps, report.depth, report.reached.len()) != (Holds(Exhausted), 1093, 1092, 6, 5) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	True
}
