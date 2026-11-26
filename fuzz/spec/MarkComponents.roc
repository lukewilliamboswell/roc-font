import build.FontBuild
import build.MarkBuild
import font.Font
import fuzz.Model

# Marks that a ligature lookup skips retain their original component. A
# mark-to-mark lookup uses that provenance even when all the marks share
# one glyph ID and one output cluster. HarfBuzz 14.6.0 agrees on an
# independent FontTools face for every finished text in this model.
# https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/OT/Layout/GPOS/MarkMarkPosFormat1.hh#L105-L126
MarkComponents := {}.{
	check : {} -> Bool
	check = |_| {
		report = Model.explore(machine(fixture({})), Model.Options.{ depth: 10, key: |state| state })
		if (report.verdict, report.states, report.steps, report.depth, report.reached.len()) == (Holds(Exhausted), 66, 65, 9, 2) {
			True
		} else {
			crash "${Model.explain(report)} ${Str.inspect(report)}"
		}
	}
}

State : { closed : List(U64), accents : U64 }

Action : [Accent, Close]

machine : Font -> Model.Machine(State, Action)
machine = |font| {
	init: { closed: [], accents: 0 },
	actions: |state|
		if (state.closed.len() == 3) [] else if (state.accents == 2) [Close] else [Accent, Close],
	step: |state, action| match action {
		Accent => { ..state, accents: state.accents + 1 }
		Close => { closed: state.closed.append(state.accents), accents: 0 }
	},
	rules: [
		Model.always(
			"each mark stack starts at its own component anchor",
			|state| match state.closed {
				[first, second, trailing] => agrees(font, first, second, trailing)
				_ => True
			},
		),
		# These two histories have identical glyph IDs, advances, clusters
		# and flags. Only placement identifies the component boundary.
		Model.sometimes("both marks belong to the first component", |state| state.closed == [2, 0, 0]),
		Model.sometimes("the same two mark glyphs belong to separate components", |state| state.closed == [1, 1, 0]),
	],
}

agrees : Font, U64, U64, U64 -> Bool
agrees = |font, first, second, trailing| {
	marks = |n| Str.repeat("\u(301)", n)
	text = "A".concat(marks(first)).concat("B").concat(marks(second)).concat("C").concat(marks(trailing))
	run = Font.shape(font, text, Font.ShapeOptions.{ script: "Latn", clusters: Characters })
	inside = first + second
	amount = inside + trailing
	# Each group begins with the mark-to-ligature displacement (150, 180)
	# relative to a 700-unit pen. Successive marks add the two mark anchors'
	# difference (30, 50). Trailing marks form a separate group.
	offsets = [first, second, trailing].join_map(
		|n| FontBuild.counting(n).map(|j| { x: -550 + 30 * j.to_i32_wrap(), y: 180 + 50 * j.to_i32_wrap() }),
	)
	run == {
		glyphs: [5].concat(List.repeat(4, amount)),
		clusters: List.repeat(0, 1 + inside).concat(FontBuild.counting(trailing).map(|j| 3 + 2 * (inside + j))),
		advances: [{ x: 700, y: 0 }].concat(List.repeat({ x: 0, y: 0 }, amount)),
		offsets: [{ x: 0, y: 0 }].concat(offsets),
		flags: List.repeat(0, 1 + inside).concat(List.repeat(1, trailing)),
	}
}

fixture : {} -> Font
fixture = |_| {
	cmap = FontBuild.cmap([
		{
			system: 3,
			encoding: 10,
			subtable: FontBuild.cmap12([
				{ first: 'A', last: 'C', glyph: 1 },
				{ first: 0x0301, last: 0x0301, glyph: 4 },
			]),
		},
	])
	gdef = MarkBuild.gdef([{ first: 1, last: 3, class: 1 }, { first: 4, last: 4, class: 3 }, { first: 5, last: 5, class: 2 }], [])
	ligature = FontBuild.ligature([1], [[{ glyph: 5, rest: [2, 3] }]])
	gsub = MarkBuild.layout(
		"latn",
		[{ tag: "liga", lookups: [0] }],
		[
			MarkBuild.Lookup.{ kind: 4, flag: 8, subtables: [ligature] },
		],
	)
	mark = [{ glyph: 4, class: 0, anchor: MarkBuild.anchor(10, 20) }]
	lig = MarkBuild.ligatures(mark, 1, [{ glyph: 5, components: List.repeat([MarkBuild.anchor(160, 200)], 3) }])
	stack = MarkBuild.position(mark, 1, [{ glyph: 4, anchors: [MarkBuild.anchor(40, 70)] }])
	gpos = MarkBuild.layout(
		"latn",
		[{ tag: "mark", lookups: [0] }, { tag: "mkmk", lookups: [1] }],
		[
			MarkBuild.Lookup.{ kind: 5, subtables: [lig] },
			MarkBuild.Lookup.{ kind: 6, subtables: [stack] },
		],
	)
	bytes = FontBuild.glyphs_font(
		[500, 460, 490, 540, 90, 700],
		cmap,
		[
			{ tag: "GDEF", data: gdef },
			{ tag: "GSUB", data: gsub },
			{ tag: "GPOS", data: gpos },
		],
	)
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "mark component fixture did not read strictly"
}
