import build.FontBuild
import font.Font
import fuzz.Fuzz
import fuzz.Model

# Unicode joining determines the forms before GSUB. The fixture makes
# each requested form independently visible by a different glyph.
# https://www.unicode.org/versions/Unicode18.0.0/
# https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/hb-ot-shaper-arabic.cc
Arabic := {}.{
	check : {} -> Bool
	check = |_| {
		report = Model.explore(machine(3), Model.Options.{ depth: 5, key: |state| state })
		if (report.verdict, report.states, report.steps, report.depth, report.reached.len()) != (Holds(Exhausted), 4145, 4144, 4, 5) {
			crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
		}
		True
	}

	target = {
		walk = machine(64)
		Model.walk_target({
			name: "arabic-joining",
			machine: walk,
			examples: [
				Model.walk_example(walk, { name: "transparent mark keeps the join", revision: "1", trace: [Choose(edge), Append(Lam), Append(Mark), Append(Alef)] }),
				Model.walk_example(walk, { name: "zwnj breaks the join", revision: "1", trace: [Choose(edge), Append(Lam), Append(Zwnj), Append(Alef)] }),
				Model.walk_example(walk, { name: "zwj keeps the join", revision: "1", trace: [Choose(edge), Append(Lam), Append(Zwj), Append(Alef)] }),
				Model.walk_example(walk, { name: "context can produce a medial glyph", revision: "1", trace: [Choose({ before: TransparentLink, after: Connected }), Append(Lam)] }),
				Model.walk_example(walk, { name: "non-joining context hides preceding dual joiner", revision: "1", trace: [Choose({ before: Blocked, after: Connected }), Append(Lam)] }),
			],
		})
	}
	growth_target = Fuzz.target_with!({
		name: "arabic-joining-growth",
		generator: Fuzz.raw_bytes,
		test!: growth!,
		show: Str.inspect,
		examples: [
			Fuzz.saved({ name: "long transparent span", revision: "1", bytes: [0] }),
			Fuzz.saved({ name: "joined and blocked clusters", revision: "1", bytes: [1] }),
		],
	})
}

Token : [Lam, Alef, Mark, Zwj, Zwnj, Hamza]

Edge : [Line, Connected, Blocked, TransparentLink]

Context : { before : Edge, after : Edge }

State : [Unchosen, Text({ context : Context, tokens : List(Token) })]

Action : [Choose(Context), Append(Token)]

Row : { glyph : U32, cluster : U64, flag : U8 }

edge : Context
edge = { before: Line, after: Line }

tokens : List(Token)
tokens = [Lam, Alef, Mark, Zwj, Zwnj, Hamza]

edges : List(Edge)
edges = [Line, Connected, Blocked, TransparentLink]

scalar : Token -> U32
scalar = |token| match token {
	Lam => 0x0644
	Alef => 0x0627
	Mark => 0x064E
	Zwj => 0x200D
	Zwnj => 0x200C
	Hamza => 0x0621
}

before_text : Edge -> Str
before_text = |context| match context {
	Line => ""
	Connected => "ل"
	Blocked => "لء"
	TransparentLink => "لَ"
}

after_text : Edge -> Str
after_text = |context| match context {
	Line => ""
	Connected => "ا"
	Blocked => "ءا"
	TransparentLink => "َا"
}

fixture : {} -> Font
fixture = |_| {
	lookups = [[6, 7], [8, 9], [10, 11], [12, 13]].map(
		|glyphs| { kind: 1, subtables: [FontBuild.single2([1, 2], glyphs)] },
	)
	gsub = FontBuild.layout("arab", [{ tag: "fina", lookups: [1] }, { tag: "init", lookups: [3] }, { tag: "isol", lookups: [0] }, { tag: "medi", lookups: [2] }], lookups)
	cmap = FontBuild.cmap([
		{
			system: 3,
			encoding: 10,
			subtable: FontBuild.cmap12([
				{ first: ' ', last: ' ', glyph: 5 },
				{ first: 0x0621, last: 0x0621, glyph: 4 },
				{ first: 0x0627, last: 0x0627, glyph: 2 },
				{ first: 0x0644, last: 0x0644, glyph: 1 },
				{ first: 0x064E, last: 0x064E, glyph: 3 },
			]),
		},
	])
	# A pair outside the input repertoire keeps the positioning fallback
	# out of the joining model.
	gpos = FontBuild.layout("arab", [{ tag: "kern", lookups: [0] }], [{ kind: 2, subtables: [FontBuild.pair1(4, 0, [{ glyph: 14, pairs: [{ second: 14, values: [0] }] }])] }])
	data = FontBuild.glyphs_font(List.repeat(500, 15), cmap, [{ tag: "GSUB", data: gsub }, { tag: "GPOS", data: gpos }])
	Font.from_bytes(data, Font.ReadOptions.{ strict: True }) ?? crash "Arabic fixture did not read strictly"
}

connects : Token, Token -> Bool
connects = |earlier, later| [Lam, Zwj].contains(earlier) and [Lam, Alef, Zwj].contains(later)

available : Edge -> Bool
available = |boundary| [Connected, TransparentLink].contains(boundary)

expected : List(Token), Context -> List(Row)
expected = |source, context| {
	significant = source.map_with_index(|token, i| { token, i }).drop_if(|r| r.token == Mark)
	edges_in_run = significant.keep_if(
		|earlier| {
			next = significant.find_first(|later| later.i > earlier.i)
			connects(earlier.token, (next ?? { token: if (available(context.after)) Alef else Hamza, i: source.len() }).token)
		},
	).map(
		|earlier| {
			next = significant.find_first(|later| later.i > earlier.i) ?? { token: Hamza, i: source.len() }
			{ start: earlier.i, end: next.i }
		},
	)
	logical = source.map_with_index(
		|token, i| {
			before = significant.keep_if(|r| r.i < i).last() ?? { token: if (available(context.before)) Lam else Hamza, i: 0 }
			after = significant.find_first(|r| r.i > i) ?? { token: if (available(context.after)) Alef else Hamza, i: source.len() }
			left = connects(before.token, token)
			right = connects(token, after.token)
			glyph = match token {
				Mark => 3
				Hamza => 4
				Zwj | Zwnj => 5
				Lam | Alef => {
					form = match (left, right) {
						(True, True) => 10
						(True, False) => 8
						(False, True) => 12
						_ => 6
					}
					form + (if (token == Alef) 1 else 0)
				}
			}
			grapheme = i != 0 and (token == Mark or token == Zwj)
			joining = edges_in_run.any(|e| e.start < i and i <= e.end)
			{ glyph, cluster: i * 3, flag: if (grapheme or joining) 1 else 0 }
		},
	)
	logical.fold([], |visual, row| visual.prepend(row))
}

machine : U64 -> Model.Machine(State, Action)
machine = |bound| {
	face = fixture({})
	check = |context, source| {
		opts = Font.ShapeOptions.{
			script: "Arab",
			language: "ar",
			clusters: Characters,
			arabic_context: Font.ArabicContext.{ before: before_text(context.before), after: after_text(context.after) },
		}
		plan = Font.plan(face, opts)
		scalars = source.map_with_index(|token, i| { scalar: scalar(token), offset: 3 * i })
		run = Font.shape_scalars(face, plan, scalars)
		want = expected(source, context)
		run.glyphs == want.map(|r| r.glyph) and run.clusters == want.map(|r| r.cluster)
			and run.flags == want.map(|r| r.flag)
			and run == Font.shape_scalars(face, plan, scalars)
	}
	{
		init: Unchosen,
		actions: |state| match state {
			Unchosen => edges.join_map(|before| edges.map(|after| Choose({ before, after })))
			Text(t) => if (t.tokens.len() < bound) tokens.map(|token| Append(token)) else []
		},
		step: |state, action| match (state, action) {
			(Unchosen, Choose(context)) => Text({ context, tokens: [] })
			(Text(t), Append(token)) => Text({ ..t, tokens: t.tokens.append(token) })
			_ => state
		},
		rules: [
			Model.always(
				"Arabic joining selects the expected form, cluster and break flag",
				|state| match state {
					Unchosen => True
					Text(t) => check(t.context, t.tokens)
				},
			),
			Model.sometimes("transparent mark keeps the join", |s| s == Text({ context: edge, tokens: [Lam, Mark, Alef] })),
			Model.sometimes("zwnj breaks the join", |s| s == Text({ context: edge, tokens: [Lam, Zwnj, Alef] })),
			Model.sometimes("zwj keeps the join", |s| s == Text({ context: edge, tokens: [Lam, Zwj, Alef] })),
			Model.sometimes("context can produce a medial glyph", |s| s == Text({ context: { before: TransparentLink, after: Connected }, tokens: [Lam] })),
			Model.sometimes("non-joining context hides preceding dual joiner", |s| s == Text({ context: { before: Blocked, after: Connected }, tokens: [Lam] })),
		],
	}
}

growth! : List(U8) => Fuzz.Outcome
growth! = |bytes| {
	face = fixture({})
	plan = Font.plan(face, Font.ShapeOptions.{ script: "Arab", language: "ar" })
	blocked = (bytes.first() ?? 0) % 2 == 1
	var $previous = None
	for size in [16, 128, 1024] {
		text = if (blocked) Str.repeat("لَالا\u(200C)ل", size) else "ل".concat(Str.repeat("َ", size)).concat("ا")
		measured = Fuzz.measure!("arabic-joining", || Font.shape_planned(face, plan, text))
		stats = measured.stats
		run = measured.value
		used = { allocs: stats.allocs + stats.reallocs, bytes: stats.requested_bytes, peak: stats.peak_live_bytes - stats.entry_live_bytes }
		want = if (blocked) size * 7 else size + 2
		if run.glyphs.len() != want or run.clusters.len() != want or run.flags.len() != want or run.advances.len() != want or run.offsets.len() != want {
			crash "Arabic joining changed run length or index alignment"
		}
		match $previous {
			Some(small) => {
				if used.allocs > 10 * small.allocs + 64 or used.bytes > 10 * small.bytes + 4096 or used.peak > 10 * small.peak + 4096 {
					crash "Arabic allocations did not scale linearly: ${Str.inspect((small, used))}"
				}
			}
			None => {}
		}
		$previous = Some(used)
	}
	Fuzz.keep
}
