import build.FontBuild
import font.Font
import fuzz.Fuzz
import fuzz.Model
import "../../tests/fonts/thai/NotoSansThai-Regular.ttf" as thai_bytes : List(U8)

# HarfBuzz 14.6.0's Thai preprocessing supplies a movable NIKHAHIT only
# for SARA AM. Compare a public run in which cmap gives each form its own
# glyph and no positioning or substitution can hide the order.
# https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/hb-ot-shaper-thai.cc#L247
Thai := {}.{
	check : {} -> Bool
	check = |_| {
		report = Model.explore(machine(4), Model.Options.{ depth: 6, key: |state| state })
		if (report.verdict, report.states, report.steps, report.depth, report.reached.len()) != (Holds(Exhausted), 3111, 3110, 5, 4) {
			crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
		}
		True
	}

	target = {
		walk = machine(48)
		Model.walk_target({
			name: "thai-sara-am",
			machine: walk,
			examples: [
				Model.walk_example(walk, { name: "split over tone", revision: "1", trace: [Choose(False), Append(Base), Append(Tone), Append(Am)] }),
				Model.walk_example(walk, { name: "authored mark keeps its order", revision: "1", trace: [Choose(True), Append(Base), Append(Tone), Append(Nikhahit), Append(Aa)] }),
				Model.walk_example(walk, { name: "isolated tone and repeated sara am", revision: "1", trace: [Choose(False), Append(Tone), Append(Am), Append(Am)] }),
				Model.walk_example(walk, { name: "spacing vowel stops the move", revision: "1", trace: [Choose(True), Append(Tone), Append(Aa), Append(Am)] }),
			],
		})
	}
	growth_target = Fuzz.target_with!({
		name: "thai-sara-am-growth",
		generator: Fuzz.raw_bytes,
		test!: growth!,
		show: Str.inspect,
		examples: [
			Fuzz.saved({ name: "isolated sara am with repeated source offsets", revision: "1", bytes: [0] }),
			Fuzz.saved({ name: "above-base prefix before sara am", revision: "1", bytes: [1] }),
			Fuzz.saved({ name: "real Thai name and address fragments", revision: "1", bytes: [2] }),
		],
	})
}

Token : [Base, Vowel, Tone, Am, Nikhahit, Aa]

State : [Unchosen, Text({ characters : Bool, tokens : List(Token) })]

Action : [Choose(Bool), Append(Token)]

Row : { glyph : U32, cluster : U64 }

options : Bool -> Font.ShapeOptions
options = |characters| Font.ShapeOptions.{ script: "Thai", language: "th", clusters: if (characters) Characters else Graphemes }

cp_glyph : Token -> (U32, U32)
cp_glyph = |token| match token {
	Base => (0x0E14, 1)
	Vowel => (0x0E34, 2)
	Tone => (0x0E4B, 3)
	Am => (0x0E33, 4)
	Nikhahit => (0x0E4D, 5)
	Aa => (0x0E32, 6)
}

tokens : List(Token)
tokens = [Base, Vowel, Tone, Am, Nikhahit, Aa]

fixture : {} -> Font
fixture = |_| {
	# This font has a SARA AM glyph too, so its presence cannot be used
	# as a reason to skip the split.
	cmap = FontBuild.cmap([
		{
			system: 3,
			encoding: 10,
			subtable: FontBuild.cmap12([
				{ first: 0x0E14, last: 0x0E14, glyph: 1 },
				{ first: 0x0E32, last: 0x0E32, glyph: 6 },
				{ first: 0x0E33, last: 0x0E33, glyph: 4 },
				{ first: 0x0E34, last: 0x0E34, glyph: 2 },
				{ first: 0x0E4B, last: 0x0E4B, glyph: 3 },
				{ first: 0x0E4D, last: 0x0E4D, glyph: 5 },
			]),
		},
	])
	data = FontBuild.glyphs_font([500, 500, 0, 0, 500, 0, 500], cmap, [])
	Font.from_bytes(data, Font.ReadOptions.{ strict: True }) ?? crash "Thai fixture did not read strictly"
}

# Use the preceding output's attachment and the authored mark suffix to
# predict cluster ownership. Source offsets increase by three bytes.
expected : List(Token), Bool -> List(Row)
expected = |source, characters| {
	var $rows = []
	var $offset = 0
	for token in source {
		last = $rows.last()
		above = |glyph| [2, 3, 5].contains(glyph)
		owner = |fallback| (last ?? { cluster: fallback, glyph: 0 }).cluster
		if token == Am {
			var $cut = $rows.len()
			while $cut > 0 and above(($rows.get($cut - 1) ?? { cluster: 0, glyph: 0 }).glyph) {
				$cut = $cut - 1
			}
			tail = $rows.drop_first($cut)
			cluster = if (characters) (tail.first() ?? { cluster: $offset, glyph: 0 }).cluster else owner($offset)
			$rows = $rows.take_first($cut)
				.append({ glyph: 5, cluster })
				.concat(tail.map(|row| { ..row, cluster }))
				.append({ glyph: 6, cluster })
		} else {
			(_, glyph) = cp_glyph(token)
			cluster = if (!characters and above(glyph)) owner($offset) else $offset
			$rows = $rows.append({ glyph, cluster })
		}
		$offset = $offset + 3
	}
	$rows
}

machine : U64 -> Model.Machine(State, Action)
machine = |max_tokens| {
	font = fixture({})
	graphemes = Font.plan(font, options(False))
	characters_plan = Font.plan(font, options(True))
	at = |source, characters| {
		scalars = source.map_with_index(
			|token, i| {
				(scalar, _) = cp_glyph(token)
				{ scalar, offset: 3 * i }
			},
		)
		plan = if (characters) characters_plan else graphemes
		run = Font.shape_scalars(font, plan, scalars)
		want = expected(source, characters)
		run.glyphs == want.map(|row| row.glyph)
			and run.clusters == want.map(|row| row.cluster)
			and run.advances == want.map(|row| { x: if ([1, 6].contains(row.glyph)) 500 else 0, y: 0 })
			and run.offsets == List.repeat({ x: 0, y: 0 }, want.len())
			and run.flags.len() == want.len()
			and run == Font.shape_scalars(font, plan, scalars)
	}
	{
		init: Unchosen,
		actions: |state| match state {
			Unchosen => [Choose(False), Choose(True)]
			Text(t) => if (t.tokens.len() < max_tokens) tokens.map(|token| Append(token)) else []
		},
		step: |state, action| match (state, action) {
			(Unchosen, Choose(characters)) => Text({ characters, tokens: [] })
			(Text(t), Append(token)) => Text({ ..t, tokens: t.tokens.append(token) })
			_ => state
		},
		rules: [
			Model.always(
				"Thai preprocessing preserves the modeled glyphs, source owners and widths",
				|state| match state {
					Unchosen => True
					Text(t) => at(t.tokens, t.characters)
				},
			),
			Model.sometimes("only the derived nikhahit crosses the tone", |s| s == Text({ characters: False, tokens: [Base, Tone, Am] })),
			Model.sometimes("authored nikhahit stays after its tone", |s| s == Text({ characters: True, tokens: [Base, Tone, Nikhahit, Aa] })),
			Model.sometimes("standalone tone receives no dotted circle", |s| s == Text({ characters: False, tokens: [Tone, Am, Am] })),
			Model.sometimes("SARA AA stops the move", |s| s == Text({ characters: True, tokens: [Tone, Aa, Am] })),
		],
	}
}

growth! : List(U8) => Fuzz.Outcome
growth! = |bytes| {
	pattern = (bytes.first() ?? 0) % 3
	face = if pattern == 2 {
		Font.from_bytes(thai_bytes, Font.ReadOptions.{ strict: True }) ?? crash "the Thai font should read strictly"
	} else {
		fixture({})
	}
	plan = Font.plan(face, options(False))
	var $previous = None
	for size in [16, 128, 1024] {
		measured = match pattern {
			0 => {
				scalars = List.repeat({ scalar: 0x0E33, offset: 0 }, size)
				Fuzz.measure!("repeated-cluster", || Font.shape_scalars(face, plan, scalars))
			}
			1 => {
				text = "ด".concat(Str.repeat("๋", size)).concat("ำ")
				Fuzz.measure!("above-base-span", || Font.shape_planned(face, plan, text))
			}
			_ => {
				text = Str.repeat("น้ำฝน อำเภอเมืองเชียงใหม่ ", size)
				Fuzz.measure!("thai-text", || Font.shape_planned(face, plan, text))
			}
		}
		stats = measured.stats
		run = measured.value
		used = {
			allocs: stats.allocs + stats.reallocs,
			bytes: stats.requested_bytes,
			peak: stats.peak_live_bytes - stats.entry_live_bytes,
		}
		if run.glyphs.len() != run.clusters.len() or run.glyphs.len() != run.advances.len() or run.glyphs.len() != run.offsets.len() or run.glyphs.len() != run.flags.len() {
			crash "Thai run lists lost index alignment"
		}
		if (pattern == 0 and (run.glyphs.len() != 2 * size or run.clusters.any(|c| c != 0))) or (pattern == 1 and run.glyphs.len() != size + 3) {
			crash "Thai preprocessing did not add exactly one glyph per split"
		}
		match $previous {
			Some(small) => {
				if used.allocs > 10 * small.allocs + 64 or used.bytes > 10 * small.bytes + 4096 or used.peak > 10 * small.peak + 4096 {
					crash "Thai allocations did not scale linearly: ${Str.inspect((small, used))}"
				}
			}
			None => {}
		}
		$previous = Some(used)
	}
	Fuzz.keep
}
