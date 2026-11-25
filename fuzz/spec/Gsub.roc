import fuzz.Model
import fuzz.Target
import font.Font
import build.FontBuild

Gsub := [].{
	target : Target
	target = {
		machine = model(32)
		Model.walk_target({
			name: "gsub-order",
			machine,
			examples: [
				Model.walk_example(machine, { name: "short preference and two matches", revision: "1", trace: [Choose(FeedFirstShort), Append('A'), Append('B'), Append('A'), Append('B')] }),
				Model.walk_example(machine, { name: "an earlier lookup feeds the ligature", revision: "1", trace: [Choose(FeedFirstShort), Append('C'), Append('B')] }),
				Model.walk_example(machine, { name: "long preference", revision: "1", trace: [Choose(FeedFirstLong), Append('A'), Append('B'), Append('A')] }),
				Model.walk_example(machine, { name: "a late lookup cannot feed an earlier one", revision: "1", trace: [Choose(FeedLastShort), Append('C'), Append('B')] }),
			],
		})
	}
}

# OpenType 1.9.1 GSUB, "GSUB table organization" and "Lookup type 4
# subtable: ligature substitution".
# https://learn.microsoft.com/en-us/typography/opentype/spec/gsub
# Lookups run in LookupList order, each on the complete result of the
# preceding lookup. A ligature set prefers its first matching entry.
# The font has C -> A, AB -> short / ABA -> long, and a lookup that
# substitutes both ligature outputs. Vary the placement of C -> A and
# which ligature is preferred. The feature references always run in
# reverse LookupList order so they cannot accidentally agree with it.

Recipe : [FeedFirstShort, FeedFirstLong, FeedLastShort, FeedLastLong]

State : [Unchosen, Text({ recipe : Recipe, bytes : List(U8) })]

Action : [Choose(Recipe), Append(U8)]

Item : { glyph : U32, cluster : U64 }

feed_first : Recipe -> Bool
feed_first = |recipe| recipe == FeedFirstShort or recipe == FeedFirstLong

long_first : Recipe -> Bool
long_first = |recipe| recipe == FeedFirstLong or recipe == FeedLastLong

recipe_font : Recipe -> Font
recipe_font = |recipe| {
	feed = { kind: 1, subtables: [FontBuild.single2([3], [1])] }
	short = { glyph: 4, rest: [2] }
	long = { glyph: 5, rest: [2, 1] }
	set = if (long_first(recipe)) [long, short] else [short, long]
	ligature = { kind: 4, subtables: [FontBuild.ligature([1], [set])] }
	finish = { kind: 1, subtables: [FontBuild.single2([4, 5], [6, 7])] }
	lookups = if (feed_first(recipe)) [feed, ligature, finish] else [ligature, feed, finish]
	gsub = FontBuild.layout("latn", [{ tag: "liga", lookups: [2, 1, 0] }], lookups)
	cmap = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 'A', last: 'C', delta: 65536 + 1 - 'A', glyphs: [] }]) }])
	file = FontBuild.glyphs_font(List.repeat(500, 8), cmap, [{ tag: "GSUB", data: gsub }])
	Font.from_bytes(file, Font.ReadOptions.{ strict: True }) ?? crash "the GSUB model font did not read strictly"
}

# Reference transducer on the literal input. Fuse the final single
# substitution into the chosen output. The C -> A lookup can affect
# matching only when it precedes the ligature lookup.
expected : Recipe, List(U8) -> List(Item)
expected = |recipe, bytes| {
	input = if (feed_first(recipe)) bytes.map(|byte| if (byte == 'C') 'A' else byte) else bytes
	var $pos = 0
	var $items = []
	while $pos < input.len() {
		(glyph, count) = match input.drop_first($pos) {
			['A', 'B', 'A', ..] if long_first(recipe) => (7, 3)
			['A', 'B', ..] => (6, 2)
			['B', ..] => (2, 1)
			# Both A and C end as glyph A even when C was too late to match.
			_ => (1, 1)
		}
		$items = $items.append({ glyph, cluster: $pos })
		$pos = $pos + count
	}
	$items
}

model : U64 -> Model.Machine(State, Action)
model = |max_letters| {
	early_short = recipe_font(FeedFirstShort)
	early_long = recipe_font(FeedFirstLong)
	late_short = recipe_font(FeedLastShort)
	late_long = recipe_font(FeedLastLong)
	{
		init: Unchosen,
		actions: |state| match state {
			Unchosen => [Choose(FeedFirstShort), Choose(FeedFirstLong), Choose(FeedLastShort), Choose(FeedLastLong)]
			Text({ recipe: _, bytes }) => if (bytes.len() < max_letters) [Append('A'), Append('B'), Append('C')] else []
		},
		step: |state, action| match (state, action) {
			(Unchosen, Choose(recipe)) => Text({ recipe, bytes: [] })
			(Text({ recipe, bytes }), Append(byte)) => Text({ recipe, bytes: bytes.append(byte) })
			_ => state
		},
		rules: [
			Model.always(
				"GSUB yields the ordered glyphs and source byte clusters",
				|state| match state {
					Unchosen => True
					Text({ recipe, bytes }) => {
						font = match recipe {
							FeedFirstShort => early_short
							FeedFirstLong => early_long
							FeedLastShort => late_short
							FeedLastLong => late_long
						}
						text = Str.from_utf8(bytes) ?? crash "the GSUB model alphabet must be ASCII"
						run = Font.shape(font, text, Font.ShapeOptions.{})
						want = expected(recipe, bytes)
						run.glyphs == want.map(|item| item.glyph) and run.clusters == want.map(|item| item.cluster)
					}
				},
			),
			Model.sometimes("two matching ligatures with the shorter first", |state| state == Text({ recipe: FeedFirstShort, bytes: ['A', 'B', 'A'] })),
			Model.sometimes("two matching ligatures with the longer first", |state| state == Text({ recipe: FeedFirstLong, bytes: ['A', 'B', 'A'] })),
			Model.sometimes("an earlier lookup creates a match", |state| state == Text({ recipe: FeedFirstShort, bytes: ['C', 'B'] })),
			Model.sometimes("a later lookup is too late to create a match", |state| state == Text({ recipe: FeedLastShort, bytes: ['C', 'B'] })),
			Model.sometimes("two matches in one scan", |state| state == Text({ recipe: FeedFirstShort, bytes: ['A', 'B', 'A', 'B'] })),
		],
	}
}

# Every string of 0 to 5 letters of this alphabet, with each of the four
# recipes. Choose contributes one action to the maximum depth.
expect {
	report = Model.explore(model(5), Model.Options.{ depth: 7, key: |state| state })
	if (report.verdict, report.states, report.steps, report.depth, report.reached.len()) != (Holds(Exhausted), 1457, 1456, 6, 5) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	True
}
