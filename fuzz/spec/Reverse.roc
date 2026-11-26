import build.FontBuild
import font.Font
import fuzz.Model

Reverse := [].{
	check : {} -> Bool
	check = |{}| {
		# All strings of length zero through six, for each feature scope.
		report = Model.explore(machine(6), Model.Options.{ depth: 8, key: |state| state })
		if (report.verdict, report.states, report.steps, report.depth, report.reached.len()) != (Holds(Exhausted), 3280, 3279, 7, 5) {
			crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
		}
		True
	}
}

Scope : [Full, TwoCandidates, FirstCandidate]

State : [Unchosen, Text({ scope : Scope, bytes : List(U8) })]

Action : [Choose(Scope), Append(U8)]

# OpenType 1.9.1 GSUB lookup type 8 specifies scanning from the logical
# end, while context offsets are nearest first on either side. Type 7
# uses the same lookup semantics when it wraps type 8.
# https://learn.microsoft.com/en-us/typography/opentype/spec/gsub
font_with_reverse : Bool -> Font
font_with_reverse = |extended| {
	subtable = FontBuild.pack([
		U16(1),
		Ref(FontBuild.coverage1([1])),
		U16(2),
		Ref(FontBuild.coverage1([1])),
		Ref(FontBuild.coverage1([1, 2])),
		U16(2),
		Ref(FontBuild.coverage1([2, 3])),
		Ref(FontBuild.coverage1([2, 3, 4])),
		U16(1),
		U16(3),
	])
	lookup = if (extended) { kind: 7, subtables: [FontBuild.extension(8, subtable)] } else { kind: 8, subtables: [subtable] }
	gsub = FontBuild.layout("DFLT", [{ tag: "liga", lookups: [0] }], [lookup])
	cmap = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 'A', last: 'D', delta: 65536 - 64, glyphs: [] }]) }])
	bytes = FontBuild.glyphs_font(List.repeat(500, 5), cmap, [{ tag: "GSUB", data: gsub }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "reverse chaining model fixture did not read strictly"
}

options_for : Scope -> Font.ShapeOptions
options_for = |scope| {
	features = match scope {
		Full => []
		TwoCandidates => [Font.Feature.{ tag: "liga", value: 0 }, Font.Feature.{ tag: "liga", start: 2, end: 4 }]
		FirstCandidate => [Font.Feature.{ tag: "liga", value: 0 }, Font.Feature.{ tag: "liga", start: 2, end: 3 }]
	}
	Font.ShapeOptions.{ features }
}

# Build the output suffix from the right. The left context remains
# original input. The right context comes from the suffix already
# produced, including any substitutions within it.
expected : List(U8), Scope -> List(U32)
expected = |bytes, scope| {
	var $suffix = []
	for offset in 0..<bytes.len() {
		i = bytes.len() - 1 - offset
		glyph = (bytes.get(i) ?? crash "index is inside the model input").to_u32() - 64
		enabled = scope == Full or i == 2 or (scope == TwoCandidates and i == 3)
		left = i >= 2 and bytes.get(i - 1) == Ok('A') and [Ok('A'), Ok('B')].contains(bytes.get(i - 2))
		right = [Ok(2), Ok(3)].contains($suffix.get(0)) and [Ok(2), Ok(3), Ok(4)].contains($suffix.get(1))
		$suffix = $suffix.prepend(if (glyph == 1 and enabled and left and right) 3 else glyph)
	}
	$suffix
}

machine : U64 -> Model.Machine(State, Action)
machine = |max_letters| {
	font = font_with_reverse(False)
	extended = font_with_reverse(True)
	{
		init: Unchosen,
		actions: |state| match state {
			Unchosen => [Choose(Full), Choose(TwoCandidates), Choose(FirstCandidate)]
			Text({ scope: _, bytes }) => if (bytes.len() < max_letters) [Append('A'), Append('B'), Append('D')] else []
		},
		step: |state, action| match (state, action) {
			(Unchosen, Choose(scope)) => Text({ scope, bytes: [] })
			(Text({ scope, bytes }), Append(byte)) => Text({ scope, bytes: bytes.append(byte) })
			_ => state
		},
		rules: [
			Model.always(
				"reverse chaining uses ordered context and the substituted suffix",
				|state| match state {
					Unchosen => True
					Text({ scope, bytes }) => {
						text = Str.from_utf8(bytes) ?? crash "the reverse chaining alphabet is ASCII"
						options = options_for(scope)
						want = expected(bytes, scope)
						clusters = FontBuild.counting(bytes.len())
						[font, extended].all(
							|face| {
								run = Font.shape(face, text, options)
								run.glyphs == want and run.clusters == clusters
							},
						)
					}
				},
			),
			Model.sometimes("one substitution enables the earlier candidate", |s| s == Text({ scope: Full, bytes: ['B', 'A', 'A', 'A', 'B', 'D'] })),
			Model.sometimes("context can extend past both ends of the enabled range", |s| s == Text({ scope: TwoCandidates, bytes: ['B', 'A', 'A', 'A', 'B', 'D'] })),
			Model.sometimes("disabling the next candidate prevents the earlier match", |s| s == Text({ scope: FirstCandidate, bytes: ['B', 'A', 'A', 'A', 'B', 'D'] })),
			Model.sometimes("the nearer backtrack position has its own coverage", |s| s == Text({ scope: Full, bytes: ['A', 'B', 'A', 'B', 'D'] })),
			Model.sometimes("the nearer lookahead position has its own coverage", |s| s == Text({ scope: Full, bytes: ['B', 'A', 'A', 'D', 'B'] })),
		],
	}
}
