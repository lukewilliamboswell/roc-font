import build.FontBuild
import build.MarkBuild
import font.Font
import fuzz.Model

# OpenType 1.9.1 GPOS types 4 and 6. The mark chooses a class. With
# the selected anchor, its position in absolute pen coordinates is the
# target's position plus the target anchor minus the mark anchor.
# https://learn.microsoft.com/en-us/typography/opentype/spec/gpos
MarkAttachment := {}.{
	check : {} -> Bool
	check = |_| {
		report = Model.explore(machine({}), Model.Options.{ depth: 6, key: |state| state })
		if (report.verdict, report.states, report.steps, report.depth, report.reached.len()) == (Holds(Exhausted), 485, 484, 5, 3) {
			True
		} else {
			crash "${Model.explain(report)} ${Str.inspect(report)}"
		}
	}
}

Base : [A, B]

Mark : [Top, Stack, Skipped]

Text : { rtl : Bool, base : Base, marks : List(Mark) }

State : [Start, Text(Text)]

Action : [Begin({ rtl : Bool, base : Base }), Add(Mark)]

fixture : Bool -> Font
fixture = |rtl| {
	a = MarkBuild.anchor
	source = [{ glyph: 3, class: 0, anchor: a(17, 23) }, { glyph: 4, class: 1, anchor: a(-10, 14) }]
	base = MarkBuild.position(
		source,
		2,
		[
			{ glyph: 1, anchors: [a(200, 300), []] },
			{ glyph: 2, anchors: [a(110, 180), a(-60, 120)] },
		],
	)
	stack = MarkBuild.position(
		[{ glyph: 4, class: 0, anchor: a(-10, 14) }],
		1,
		[
			{ glyph: 3, anchors: [a(25, 64)] },
			{ glyph: 4, anchors: [a(5, 44)] },
		],
	)
	gdef = MarkBuild.gdef([{ first: 1, last: 2, class: 1 }, { first: 3, last: 5, class: 3 }], [[3, 4]])
	gpos = MarkBuild.layout(
		if (rtl) "hebr" else "latn",
		[{ tag: "mark", lookups: [0] }, { tag: "mkmk", lookups: [1] }],
		[MarkBuild.Lookup.{ kind: 4, subtables: [base] }, MarkBuild.Lookup.{ kind: 6, flag: 0x10, subtables: [stack] }],
	)
	cmap = FontBuild.cmap([
		{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'B', glyph: 1 }, { first: 0x0300, last: 0x0302, glyph: 3 }]) },
	])
	bytes = FontBuild.glyphs_font([500, 610, 370, 90, 80, 70], cmap, [{ tag: "GDEF", data: gdef }, { tag: "GPOS", data: gpos }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "GPOS mark model fixture was rejected"
}

Row : { glyph : U32, cluster : U64, advance : I32, x : I32, y : I32 }

expected : Text -> List(Row)
expected = |t| {
	# The other base comes first, so crossing the real base is observable.
	(base1, base2) = match t.base {
		A => ({ glyph: 2, advance: 370, cluster: 0, x: 0, y: 0 }, { glyph: 1, advance: 610, cluster: 1, x: 0, y: 0 })
		B => ({ glyph: 1, advance: 610, cluster: 0, x: 0, y: 0 }, { glyph: 2, advance: 370, cluster: 1, x: 0, y: 0 })
	}
	mark_pen = if (t.rtl) 0 else base2.advance
	var $rows = [base1, base2]
	var $last = Absent
	for m in t.marks {
		cluster = 2 + 2 * ($rows.len() - 2)
		row = match m {
			Top => {
				(x, y) = if (t.base == A) (183, 277) else (93, 157)
				{ glyph: 3, cluster, advance: 0, x: x - mark_pen, y }
			}
			Stack => {
				(x, y) = match $last {
					Present(previous) => if (previous.glyph == 3) (previous.x + 35, previous.y + 50) else (previous.x + 15, previous.y + 30)
					Absent => if (t.base == A) (0, 0) else (-50 - mark_pen, 106)
				}
				{ glyph: 4, cluster, advance: 0, x, y }
			}
			Skipped => { glyph: 5, cluster, advance: 0, x: 0, y: 0 }
		}
		if m != Skipped {
			$last = Present(row)
		}
		$rows = $rows.append(row)
	}
	if (t.rtl) $rows.fold([], |rows, row| rows.prepend(row)) else $rows
}

agrees : Font, Text -> Bool
agrees = |font, t| {
	prefix = if (t.base == A) "BA" else "AB"
	text = t.marks.fold(
		prefix,
		|prefix_text, mark| prefix_text.concat(
			match mark {
				Top => "\u(300)"
				Stack => "\u(301)"
				Skipped => "\u(302)"
			},
		),
	)
	options = Font.ShapeOptions.{ script: if (t.rtl) "Hebr" else "Latn", direction: if (t.rtl) RightToLeft else LeftToRight, clusters: Characters }
	run = Font.shape(font, text, options)
	rows = expected(t)
	run.glyphs == rows.map(|row| row.glyph)
		and run.clusters == rows.map(|row| row.cluster)
		and run.advances == rows.map(|row| { x: row.advance, y: 0 })
		and run.offsets == rows.map(|row| { x: row.x, y: row.y })
}

machine : {} -> Model.Machine(State, Action)
machine = |_| {
	left = fixture(False)
	right = fixture(True)
	{
		init: Start,
		actions: |state| match state {
			Start => [False, True].join_map(|rtl| [A, B].map(|base| Begin({ rtl, base })))
			Text(t) => if (t.marks.len() < 4) [Top, Stack, Skipped].map(|m| Add(m)) else []
		},
		step: |state, action| match (state, action) {
			(Start, Begin({ rtl, base })) => Text({ rtl, base, marks: [] })
			(Text(t), Add(mark)) => Text({ ..t, marks: t.marks.append(mark) })
			_ => state
		},
		rules: [
			Model.always(
				"attached anchors agree with the final pen coordinates",
				|state| match state {
					Start => True
					Text(t) => agrees(if (t.rtl) right else left, t)
				},
			),
			Model.sometimes("an RTL stack reaches its predecessor across a filtered mark", |state| state == Text({ rtl: True, base: A, marks: [Top, Skipped, Stack] })),
			Model.sometimes("a null base anchor leaves the mark unplaced", |state| state == Text({ rtl: False, base: A, marks: [Stack] })),
			Model.sometimes("a stack has two attachment edges", |state| state == Text({ rtl: False, base: B, marks: [Top, Stack, Stack] })),
		],
	}
}
