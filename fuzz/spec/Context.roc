import fuzz.Model
import fuzz.Target
import font.Font
import build.FontBuild

Context := [].{
	target : Target
	target = {
		machine = model(32)
		Model.walk_target({
			name: "gsub-context-positions",
			machine,
			examples: [
				Model.walk_example(machine, { name: "growth first, two adjacent matches", revision: "1", trace: [Choose(GrowFirst), Append('A'), Append('B'), Append('C'), Append('A'), Append('B'), Append('C')] }),
				Model.walk_example(machine, { name: "shrinkage first, with surrounding text", revision: "1", trace: [Choose(ShrinkFirst), Append('B'), Append('A'), Append('B'), Append('C'), Append('A'), Append('B')] }),
				Model.walk_example(machine, { name: "shrinkage first, two adjacent matches", revision: "1", trace: [Choose(ShrinkFirst), Append('A'), Append('B'), Append('C'), Append('A'), Append('B'), Append('C')] }),
			],
		})
	}
}

# OpenType 1.9.1 GSUB, "Lookup type 5 subtable: contextual
# substitution", and Layout Common Table Formats, "Sequence lookup record".
# https://learn.microsoft.com/en-us/typography/opentype/spec/gsub
# https://learn.microsoft.com/en-us/typography/opentype/spec/chapter2
# A rule matches its input window before running its records. Each record
# addresses the input sequence as modified by preceding records. These fixtures
# start two child contexts from an outer context on ABC, then address
# inserted and surviving glyphs after returning to the outer context.
Order : [GrowFirst, ShrinkFirst]

State : [Unchosen, Text({ order : Order, bytes : List(U8) })]

Action : [Choose(Order), Append(U8)]

Item : { glyph : U32, cluster : U64 }

context_font : Order -> Font
context_font = |order| {
	calls = match order {
		# Address position 3 while the rule has four glyphs.
		# [1, 2, 3] -> [4, 6, 2, 3] -> [4, 6, 2, 12] -> [4, 6, 8] -> [4, 9, 8].
		GrowFirst => [{ at: 0, lookup: 1 }, { at: 3, lookup: 8 }, { at: 2, lookup: 2 }, { at: 1, lookup: 7 }]
		# [1, 2, 3] -> [1, 8] -> [1, 10] -> [4, 6, 10] -> [4, 6, 11].
		ShrinkFirst => [{ at: 1, lookup: 2 }, { at: 1, lookup: 7 }, { at: 0, lookup: 1 }, { at: 2, lookup: 7 }]
	}
	third = if (order == GrowFirst) 12 else 3
	lookups = [
		{ kind: 6, subtables: [FontBuild.chain3([], [[1], [2], [3]], [], calls)] },
		{ kind: 5, subtables: [FontBuild.context3([[1]], [{ at: 0, lookup: 3 }, { at: 1, lookup: 4 }])] },
		{ kind: 5, subtables: [FontBuild.context3([[2], [third]], [{ at: 0, lookup: 5 }, { at: 0, lookup: 6 }])] },
		{ kind: 2, subtables: [FontBuild.multiple([1], [[4, 5]])] },
		{ kind: 1, subtables: [FontBuild.single2([5], [6])] },
		{ kind: 4, subtables: [FontBuild.ligature([2], [[{ glyph: 7, rest: [third] }]])] },
		{ kind: 1, subtables: [FontBuild.single2([7], [8])] },
		{ kind: 1, subtables: [FontBuild.single2([6, 8, 10], [9, 10, 11])] },
		{ kind: 1, subtables: [FontBuild.single2([3], [12])] },
	]
	gsub = FontBuild.layout("DFLT", [{ tag: "calt", lookups: [0] }], lookups)
	cmap = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 'A', last: 'C', delta: 65536 - 64, glyphs: [] }]) }])
	file = FontBuild.glyphs_font(List.repeat(500, 13), cmap, [{ tag: "GSUB", data: gsub }])
	Font.from_bytes(file, Font.ReadOptions.{ strict: True }) ?? crash "the contextual GSUB model font did not read strictly"
}

# Treat each complete ABC as a literal replacement. The two glyphs from
# A share its byte index, the BC ligature takes B's, and unmatched text
# retains its original indices. Neither output contains A, B or C.
expected : Order, List(U8) -> List(Item)
expected = |order, bytes| {
	(glyph2, glyph3) = match order {
		GrowFirst => (9, 8)
		ShrinkFirst => (6, 11)
	}
	var $pos = 0
	var $items = []
	while $pos < bytes.len() {
		match bytes.drop_first($pos) {
			['A', 'B', 'C', ..] => {
				$items = $items.concat([{ glyph: 4, cluster: $pos }, { glyph: glyph2, cluster: $pos }, { glyph: glyph3, cluster: $pos + 1 }])
				$pos = $pos + 3
			}
			[byte, ..] => {
				$items = $items.append({ glyph: byte.to_u32() - 64, cluster: $pos })
				$pos = $pos + 1
			}
			[] => {
				$pos = bytes.len()
			}
		}
	}
	$items
}

model : U64 -> Model.Machine(State, Action)
model = |max_letters| {
	grow = context_font(GrowFirst)
	shrink = context_font(ShrinkFirst)
	{
		init: Unchosen,
		actions: |state| match state {
			Unchosen => [Choose(GrowFirst), Choose(ShrinkFirst)]
			Text({ order: _, bytes }) => if (bytes.len() < max_letters) [Append('A'), Append('B'), Append('C')] else []
		},
		step: |state, action| match (state, action) {
			(Unchosen, Choose(order)) => Text({ order, bytes: [] })
			(Text({ order, bytes }), Append(byte)) => Text({ order, bytes: bytes.append(byte) })
			_ => state
		},
		rules: [
			Model.always(
				"parent contextual records see the sequence after child lookups",
				|state| match state {
					Unchosen => True
					Text({ order, bytes }) => {
						font = if (order == GrowFirst) grow else shrink
						text = Str.from_utf8(bytes) ?? crash "the contextual GSUB model alphabet must be ASCII"
						run = Font.shape(font, text, Font.ShapeOptions.{})
						want = expected(order, bytes)
						run.glyphs == want.map(|item| item.glyph) and run.clusters == want.map(|item| item.cluster)
					}
				},
			),
			Model.sometimes("the parent addresses a position beyond the original three", |state| state == Text({ order: GrowFirst, bytes: ['A', 'B', 'C'] })),
			Model.sometimes("shrinkage first and unmatched context on both sides", |state| state == Text({ order: ShrinkFirst, bytes: ['B', 'A', 'B', 'C', 'A', 'B'] })),
			Model.sometimes("adjacent outer context matches resume after growth first", |state| state == Text({ order: GrowFirst, bytes: ['A', 'B', 'C', 'A', 'B', 'C'] })),
			Model.sometimes("adjacent outer context matches resume after shrinkage first", |state| state == Text({ order: ShrinkFirst, bytes: ['A', 'B', 'C', 'A', 'B', 'C'] })),
		],
	}
}

# All 0–6 letter strings of the three letters, with each edit order.
expect {
	report = Model.explore(model(6), Model.Options.{ depth: 8, key: |state| state })
	if (report.verdict, report.states, report.steps, report.depth, report.reached.len()) != (Holds(Exhausted), 2187, 2186, 7, 4) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	True
}
