import build.FontBuild
import font.Font
import fuzz.Fuzz
import fuzz.Model

## Modern Devanagari syllables compose without presentation lookups crossing
## their boundaries. The synthetic face makes substitutions in both reorder
## stages visible. The recipe rows agree with HarfBuzz 14.6.0 on a separate
## FontTools face carrying the same OpenType rules.
Indic := {}.{
	check : {} -> Bool
	check = |_| {
		report = Model.explore(machine(3), Model.Options.{ depth: 5, key: |state| state })
		if (report.verdict, report.states, report.steps, report.depth, report.reached.len()) != (Holds(Exhausted), 3645, 3644, 4, 6) {
			crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
		}
		True
	}

	target = {
		walk = machine(48)
		Model.walk_target({
			name: "indic-syllables",
			machine: walk,
			examples: [
				Model.walk_example(walk, { name: "initial matra reaches basic nukt", revision: "1", trace: [Choose(defaults), Append(Matra)] }),
				Model.walk_example(walk, { name: "formed reph reaches final pres", revision: "1", trace: [Choose(defaults), Append(RephMatra)] }),
				Model.walk_example(walk, { name: "explicit halant restores prebase matra", revision: "1", trace: [Choose({ ..defaults, characters: True }), Append(ExplicitHalant)] }),
				Model.walk_example(walk, { name: "joiner and nonjoiner keep distinct break flags", revision: "1", trace: [Choose(defaults), Append(Joiner), Append(NonJoiner)] }),
				Model.walk_example(walk, { name: "broken syllable inserts a dotted circle", revision: "1", trace: [Choose(defaults), Append(Broken), Append(Ta)] }),
				Model.walk_example(walk, { name: "presentation ligature stops at syllable boundary", revision: "1", trace: [Choose(defaults), Append(Ta), Append(Ka)] }),
			],
		})
	}

	growth_target = Fuzz.target_with!({
		name: "indic-syllable-growth",
		generator: Fuzz.raw_bytes,
		test!: growth!,
		show: Str.inspect,
		examples: [
			Fuzz.saved({ name: "adjacent matra and reph syllables", revision: "1", bytes: [0] }),
			Fuzz.saved({ name: "independent broken syllables", revision: "1", bytes: [1] }),
		],
	})
}

Recipe : [Ka, Ta, Matra, Reph, RephMatra, HalfMatra, ExplicitHalant, Joiner, NonJoiner, Broken]

Config : { circle : Bool, characters : Bool }

State : [Unconfigured, Text({ config : Config, recipes : List(Recipe) })]

Action : [Choose(Config), Append(Recipe)]

Row : (U32, U64, U8)

defaults : Config
defaults = { circle: True, characters: False }

fragments : List(Recipe)
fragments = [Ka, Ta, Matra, Reph, RephMatra, HalfMatra, ExplicitHalant, Joiner, NonJoiner]

source : Recipe -> Str
source = |recipe| match recipe {
	Ka => "क"
	Ta => "त"
	Matra => "कि"
	Reph => "र्क"
	RephMatra => "र्कि"
	HalfMatra => "क्ति"
	ExplicitHalant => "त्कि"
	Joiner => "र्\u(200D)क"
	NonJoiner => "र्\u(200C)क"
	Broken => "ि"
}

# Glyph IDs exercise the two pauses independently. The basic nukt lookup
# marks a prebase matra before kaa or the consonant later made half. The
# presentation lookup consumes kaa followed by already-formed reph.
# The second presentation ligature would combine adjacent त and क if
# the syllable boundary were lost.
fixture : Bool -> Font
fixture = |circle| {
	characters = [
		{ first: ' ', last: ' ', glyph: 7 },
		{ first: 0x0915, last: 0x0915, glyph: 1 },
		{ first: 0x0924, last: 0x0924, glyph: 2 },
		{ first: 0x0930, last: 0x0930, glyph: 3 },
		{ first: 0x093F, last: 0x093F, glyph: 5 },
		{ first: 0x094D, last: 0x094D, glyph: 4 },
	]
	mapped = if (circle) characters.append({ first: 0x25CC, last: 0x25CC, glyph: 6 }) else characters
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12(mapped) }])
	features = [{ tag: "half", lookups: [1] }, { tag: "nukt", lookups: [3] }, { tag: "pres", lookups: [0] }, { tag: "rphf", lookups: [2] }]
	gsub = FontBuild.layout(
		"dev2",
		features,
		[
			{ kind: 4, subtables: [FontBuild.ligature([1, 2], [[{ glyph: 11, rest: [8] }], [{ glyph: 12, rest: [1] }]])] },
			{ kind: 4, subtables: [FontBuild.ligature([1], [[{ glyph: 9, rest: [4] }]])] },
			{ kind: 4, subtables: [FontBuild.ligature([3], [[{ glyph: 8, rest: [4] }]])] },
			{ kind: 6, subtables: [FontBuild.chain3([], [[5]], [[1]], [{ at: 0, lookup: 4 }])] },
			{ kind: 1, subtables: [FontBuild.single2([5], [10])] },
		],
	)
	# The unused pair opts out of mark positioning fallback in the fixture.
	gpos = FontBuild.layout("dev2", [{ tag: "kern", lookups: [0] }], [{ kind: 2, subtables: [FontBuild.pair1(4, 0, [{ glyph: 13, pairs: [{ second: 13, values: [0] }] }])] }])
	bytes = FontBuild.glyphs_font(List.repeat(500, 14), cmap, [{ tag: "GSUB", data: gsub }, { tag: "GPOS", data: gpos }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "Indic syllable fixture did not read strictly"
}

options : Config -> Font.ShapeOptions
options = |config| Font.ShapeOptions.{ script: "Deva", language: "hi", clusters: if (config.characters) Characters else Graphemes }

# Each fragment starts a syllable. The orphan matra can occur only at the
# start of a run, where it has no preceding base and stays broken. The
# remaining fragments begin with a consonant and keep their own clusters.
# An already-reordered initial matra after a letter or mark also marks its
# first cluster unsafe. A dotted circle has the category Other Symbol.
expected : Config, List(Recipe) -> List(Row)
expected = |config, recipes| {
	var $rows = []
	var $offset = 0
	var $follows_letter_or_mark = False
	for recipe in recipes {
		matra_break : U8
		matra_break = if ($follows_letter_or_mark) 1 else 0
		halant : Row
		halant = if (config.characters) (4, 3, 1) else (4, 0, 0)
		rows : List(Row)
		rows = match recipe {
			Ka => [(1, 0, 0)]
			Ta => [(2, 0, 0)]
			Matra => [(10, 0, matra_break), (1, 0, matra_break)]
			Reph => [(11, 0, 0)]
			RephMatra => [(10, 0, matra_break), (11, 0, matra_break)]
			HalfMatra => [(10, 0, matra_break), (9, 0, matra_break), (2, 0, matra_break)]
			ExplicitHalant => [(2, 0, 0), halant, (5, 6, 1), (1, 6, 1)]
			Joiner => [(3, 0, 0), halant, if (config.characters) (7, 6, 1) else (7, 0, 0), (1, 9, 1)]
			NonJoiner => [(3, 0, 0), halant, (7, 6, 1), (1, 9, 0)]
			Broken => if (config.circle) [(5, 0, 0), (6, 0, 0)] else [(5, 0, 0)]
		}
		$rows = $rows.concat(rows.map(|(glyph, cluster, flag)| (glyph, $offset + cluster, flag)))
		$offset = $offset + source(recipe).to_utf8().len()
		$follows_letter_or_mark = !(config.circle and recipe == Broken)
	}
	$rows
}

machine : U64 -> Model.Machine(State, Action)
machine = |bound| {
	with_circle = fixture(True)
	without_circle = fixture(False)
	{
		init: Unconfigured,
		actions: |state| match state {
			Unconfigured => [True, False].join_map(|circle| [False, True].map(|characters| Choose({ circle, characters })))
			Text(t) => {
				if t.recipes.is_empty() {
					fragments.append(Broken).map(|recipe| Append(recipe))
				} else if t.recipes.len() < bound {
					fragments.map(|recipe| Append(recipe))
				} else {
					[]
				}
			}
		},
		step: |state, action| match (state, action) {
			(Unconfigured, Choose(config)) => Text({ config, recipes: [] })
			(Text(t), Append(recipe)) => Text({ ..t, recipes: t.recipes.append(recipe) })
			_ => state
		},
		rules: [
			Model.always(
				"Indic syllables respect the two reorder stages and output clusters",
				|state| match state {
					Unconfigured => True
					Text(t) => {
						face = if (t.config.circle) with_circle else without_circle
						text = Str.join_with(t.recipes.map(source), "")
						run = Font.shape(face, text, options(t.config))
						rows = expected(t.config, t.recipes)
						(run.glyphs, run.clusters, run.flags) == (rows.map(|(g, _, _)| g), rows.map(|(_, c, _)| c), rows.map(|(_, _, f)| f))
					}
				},
			),
			Model.sometimes("initial matra reaches basic nukt", |s| s == Text({ config: defaults, recipes: [Matra] })),
			Model.sometimes("formed reph reaches final pres", |s| s == Text({ config: defaults, recipes: [RephMatra] })),
			Model.sometimes("explicit halant restores prebase matra", |s| s == Text({ config: { ..defaults, characters: True }, recipes: [ExplicitHalant] })),
			Model.sometimes("joiner and nonjoiner keep distinct break flags", |s| s == Text({ config: defaults, recipes: [Joiner, NonJoiner] })),
			Model.sometimes("broken syllable inserts a dotted circle", |s| s == Text({ config: defaults, recipes: [Broken, Ta] })),
			Model.sometimes("presentation ligature stops at syllable boundary", |s| s == Text({ config: defaults, recipes: [Ta, Ka] })),
		],
	}
}

growth! : List(U8) => Fuzz.Outcome
growth! = |bytes| {
	face = fixture(True)
	plan = Font.plan(face, options(defaults))
	broken = (bytes.first() ?? 0) % 2 == 1
	var $previous = None
	for size in [16, 128, 1024] {
		text = if (broken) Str.repeat("ि।", size) else Str.repeat("किर्कक्ति", size)
		measured = Fuzz.measure!("indic-syllables", || Font.shape_planned(face, plan, text))
		stats = measured.stats
		run = measured.value
		used = { allocs: stats.allocs + stats.reallocs, bytes: stats.requested_bytes, peak: stats.peak_live_bytes - stats.entry_live_bytes }
		want = if (broken) 3 * size else 6 * size
		if run.glyphs.len() != want or run.clusters.len() != want or run.flags.len() != want or run.advances.len() != want or run.offsets.len() != want {
			crash "Indic syllables changed expected glyph count or index alignment: ${Str.inspect((size, broken, want, run.glyphs.len()))}"
		}
		match $previous {
			Some(small) => {
				if used.allocs > 10 * small.allocs + 64 or used.bytes > 10 * small.bytes + 4096 or used.peak > 10 * small.peak + 4096 {
					crash "Indic syllable allocations did not scale linearly: ${Str.inspect((small, used))}"
				}
			}
			None => {}
		}
		$previous = Some(used)
	}
	Fuzz.keep
}
