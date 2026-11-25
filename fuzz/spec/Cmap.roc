import build.FontBuild
import font.Font
import fuzz.Fuzz
import fuzz.Model

# OpenType 1.9.1, cmap, "Encoding records and encodings" and "Format 14:
# Unicode variation sequences." Use one nominal map, preferring full
# Unicode to BMP. A default sequence gets its glyph from that map. A
# non-default sequence has its own glyph and can exist without a nominal
# base mapping. Unknown sequences use HarfBuzz's nominal fallback.
# https://learn.microsoft.com/en-us/typography/opentype/spec/cmap
Cmap := {}.{
	target = Model.path_target({
		name: "cmap-sequences",
		machine,
		decode: |bytes| match bytes {
			[] => []
			[choice, .. as rest] => {
				repertoire = repertoires.get(choice.to_u64() % repertoires.len()) ?? Bmp
				[Read(repertoire)].concat(rest.take_first(32).map(|byte| Append(pick_token(byte.to_u64()))))
			}
		},
		examples: [
			Fuzz.saved({ name: "bmp: default, alternate-only, and unknown", revision: "1", bytes: [0, 1, 5, 9, 2, 3] }),
			Fuzz.saved({ name: "full: sequence followed by a supplementary base", revision: "2", bytes: [1, 2, 12, 1] }),
			Fuzz.saved({ name: "full without variation records", revision: "1", bytes: [2, 2, 9] }),
		],
	})
}

Repertoire : [Bmp, Full, FullWithoutVariants]

Base : [GreaterNotEqual, MuchLess, Reed, Supplementary]

Selector : [None, Vs1, Vs17, Unknown]

Token : { base : Base, selector : Selector }

Action : [Read(Repertoire), Append(Token)]

Ready : { repertoire : Repertoire, font : Font, tokens : List(Token) }

World := [Start, Rejected, Ready(Ready)].{
	# Only the repertoire can construct the immutable prepared font.
	is_eq : World, World -> Bool
	is_eq = |a, b| world_key(a) == world_key(b)
}

repertoires : List(Repertoire)
repertoires = [Bmp, Full, FullWithoutVariants]

bases : List(Base)
bases = [GreaterNotEqual, MuchLess, Reed, Supplementary]

pick_token : U64 -> Token
pick_token = |n| {
	selectors = [None, Vs1, Vs17, Unknown]
	{ base: bases.get((n // 4) % bases.len()) ?? GreaterNotEqual, selector: selectors.get(n % selectors.len()) ?? None }
}

scalar : Base -> U32
scalar = |base| match base {
	GreaterNotEqual => 0x2269
	MuchLess => 0x226A
	Reed => 0x82A6
	Supplementary => 0x20000
}

text_of : Token -> Str
text_of = |token| {
	base = match token.base {
		GreaterNotEqual => "\u(2269)"
		MuchLess => "\u(226A)"
		Reed => "\u(82A6)"
		Supplementary => "\u(20000)"
	}
	selector = match token.selector {
		None => ""
		Vs1 => "\u(FE00)"
		Vs17 => "\u(E0100)"
		Unknown => "\u(FE01)"
	}
	base.concat(selector)
}

# A compact map of the fixture's nominal repertoire. The two ranges
# disagree visibly where both cover a base, so choosing the wrong one
# changes the observed glyph, including the glyph of a default sequence.
nominal : Repertoire, Base -> Try(U32, [Missing])
nominal = |repertoire, base| match base {
	GreaterNotEqual => Ok(if (repertoire == Bmp) 1 else 3)
	MuchLess => Ok(if (repertoire == Bmp) 2 else 4)
	Reed => Err(Missing)
	Supplementary => if (repertoire == Bmp) Err(Missing) else Ok(1)
}

variant : Repertoire, Token -> [Default, Override(U32), Unsupported]
variant = |repertoire, token|
	if repertoire == FullWithoutVariants {
		Unsupported
	} else {
		match (token.selector, token.base) {
			(Vs1, GreaterNotEqual) | (Vs1, MuchLess) => Default
			(Vs1, Reed) => Override(5)
			(Vs17, GreaterNotEqual) => Override(6)
			(Vs17, Reed) => Override(7)
			_ => Unsupported
		}
	}

fixture : Repertoire -> List(U8)
fixture = |repertoire| {
	bmp = {
		system: 3,
		encoding: 1,
		subtable: FontBuild.cmap4([
			{ first: 0x20, last: 0x20, delta: 0, glyphs: [8] },
			{ first: 0x2269, last: 0x226A, delta: 0, glyphs: [1, 2] },
		]),
	}
	full = {
		system: 3,
		encoding: 10,
		subtable: FontBuild.cmap12([{ first: 0x20, last: 0x20, glyph: 8 }, { first: 0x2269, last: 0x226A, glyph: 3 }, { first: 0x20000, last: 0x20000, glyph: 1 }]),
	}
	variations = { system: 0, encoding: 5, subtable: format14 }
	records = match repertoire {
		Bmp => [variations, bmp]
		Full => [variations, bmp, full]
		FullWithoutVariants => [bmp, full]
	}
	# The space glyph distinguishes an unsupported selector (which leaves
	# a zero-width placeholder) from a consumed default sequence.
	FontBuild.glyphs_font([100, 200, 300, 400, 500, 600, 700, 800, 900], FontBuild.cmap(records), [])
}

format14 : List(U8)
format14 = FontBuild.pack([
	U16(14),
	U32(63),
	U32(2),
	# Selector records: FE00 has both tables, E0100 has only overrides.
	Raw([0, 0xFE, 0]),
	U32(32),
	U32(40),
	Raw([0x0E, 0x01, 0]),
	U32(0),
	U32(49),
	# FE00 default range 2269..226A and one non-default mapping.
	U32(1),
	Raw([0, 0x22, 0x69, 1]),
	U32(1),
	Raw([0, 0x82, 0xA6]),
	U16(5),
	# E0100 non-default mappings in ascending base order.
	U32(2),
	Raw([0, 0x22, 0x69]),
	U16(6),
	Raw([0, 0x82, 0xA6]),
	U16(7),
])

nominal_agrees : Ready -> Bool
nominal_agrees = |ready| {
	bases.all(|base| Font.glyph(ready.font, scalar(base)) == nominal(ready.repertoire, base))
		and Font.glyph(ready.font, 0x20) == Ok(8)
		and Font.code_points(ready.font) == [0x20].concat(bases.keep_if(|base| nominal(ready.repertoire, base).is_ok()).map(scalar))
}

shaping_agrees : Ready -> Bool
shaping_agrees = |ready| {
	want = ready.tokens.fold(
		{ text: "", items: [], offset: 0 },
		|out, token| {
			part = text_of(token)
			choice = variant(ready.repertoire, token)
			glyph = match choice {
				Override(g) => g
				_ => nominal(ready.repertoire, token.base) ?? 0
			}
			items = out.items.append({ glyph, cluster: out.offset, advance: (100 + 100 * glyph).to_i32_wrap() })
			{
				text: out.text.concat(part),
				offset: out.offset + part.to_utf8().len(),
				items: if (choice == Unsupported and token.selector != None) items.append({ glyph: 8, cluster: out.offset, advance: 0 }) else items,
			}
		},
	)
	run = Font.shape(ready.font, want.text, Font.ShapeOptions.{ direction: LeftToRight })
	run.glyphs == want.items.map(|item| item.glyph)
		and run.clusters == want.items.map(|item| item.cluster)
		and run.advances == want.items.map(|item| { x: item.advance, y: 0 })
		and run.flags.map(Font.is_missing) == want.items.map(|item| item.glyph == 0)
}

machine : Model.Machine(World, Action)
machine = {
	init: Start,
	actions: |world| match world {
		Start => repertoires.map(|repertoire| Read(repertoire))
		Ready(ready) if ready.tokens.len() < 2 => FontBuild.counting(16).map(|n| Append(pick_token(n)))
		_ => []
	},
	step: |world, action| match (world, action) {
		(Start, Read(repertoire)) =>
			match Font.from_bytes(fixture(repertoire), Font.ReadOptions.{ strict: True }) {
				Ok(font) => Ready({ repertoire, font, tokens: [] })
				Err(_) => Rejected
			}
		(Ready(ready), Append(token)) => Ready({ ..ready, tokens: ready.tokens.append(token) })
		_ => world
	},
	rules: [
		Model.always(
			"the constructed map is accepted in strict mode",
			|world| match world {
				Rejected => False
				_ => True
			},
		),
		Model.always_step(
			"glyph queries and coverage use the preferred nominal map",
			|{ before, action: _, after }| match (before, after) {
				(Start, Ready(ready)) => nominal_agrees(ready)
				_ => True
			},
		),
		Model.always(
			"the shaped glyphs, byte clusters, advances and missing flags agree",
			|world| match world {
				Ready(ready) => shaping_agrees(ready)
				_ => True
			},
		),
		sequence_goal("the full Unicode map supplies the glyph of a default sequence", Full, { base: GreaterNotEqual, selector: Vs1 }),
		sequence_goal("the inclusive end of the default range is used", Bmp, { base: MuchLess, selector: Vs1 }),
		sequence_goal("a non-default sequence maps an otherwise missing base", Bmp, { base: Reed, selector: Vs1 }),
		sequence_goal("an unknown selector falls back to the nominal glyph", Bmp, { base: GreaterNotEqual, selector: Unknown }),
		sequence_goal("an absent variation table leaves the nominal map in use", FullWithoutVariants, { base: GreaterNotEqual, selector: Vs17 }),
		Model.sometimes(
			"a supplementary base follows a supplementary selector",
			|world| match world {
				Ready({ repertoire: Full, tokens: [{ base: GreaterNotEqual, selector: Vs17 }, { base: Supplementary, selector: None }, ..], font: _ }) => True
				_ => False
			},
		),
	],
}

sequence_goal : Str, Repertoire, Token -> Model.Rule(World, Action)
sequence_goal = |name, repertoire, token|
	Model.sometimes_step(
		name,
		|{ before, action, after: _ }| match before {
			Ready(ready) => ready.repertoire == repertoire and action == Append(token)
			_ => False
		},
	)

# A strict read is deterministic for the fixture, and the ordered
# tokens determine both the text and all possible next actions.
world_key : World -> [Starting, Refused, Shaping(Repertoire, List(Token))]
world_key = |world| match world {
	Start => Starting
	Rejected => Refused
	Ready(ready) => Shaping(ready.repertoire, ready.tokens)
}

expect {
	result = Model.explore(machine, { depth: 4, key: world_key, verify: EveryStep })
	if (result.verdict, result.states, result.steps, result.depth, result.reached.len()) != (Holds(Exhausted), 820, 819, 3, 6) {
		crash "${Model.explain(result)} ${Str.inspect(result.verdict)}"
	}
	True
}
