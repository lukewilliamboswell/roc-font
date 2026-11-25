import build.FontBuild
import font.Font
import fuzz.Model

# OpenType 1.9.1 Layout Common Table Formats, "LangSys table", "Feature
# table" and "Lookup List table": the language's required feature is used,
# and lookups selected by features are applied in LookupList order.
# https://learn.microsoft.com/en-us/typography/opentype/spec/chapter2
#
# Font.Feature adds half-open ranges at UTF-8 cluster offsets. This model
# checks HarfBuzz's later-overlapping-range precedence for one feature and
# union of the active ranges when two features share a lookup in the
# same HarfBuzz shaping stage.
# https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/hb-ot-map.cc#L327
# https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/hb-ot-shape.cc#L700
Features := {}.{
	check : {} -> Bool
	check = |_| {
		result = report({})
		(result.verdict, result.states, result.steps, result.depth, result.reached.len()) == (Holds(Exhausted), 315, 314, 3, 5)
	}
}

Feature : [Contextual, Ligatures]

Request : { feature : Feature, on : Bool, start : U64, end : U64 }

Action : [Read(Bool), Add(Request)]

Ready : { font : Font, required_first : Bool, requests : List(Request) }

World : [Start, Rejected, Ready(Ready)]

text : Str
text = "A\u(10001)A"

clusters : List(U64)
clusters = [0, 1, 5]

requests : List(Request)
requests = [Contextual, Ligatures].join_map(
	|feature| [
		{ feature, on: False, start: 0, end: 6 },
		{ feature, on: False, start: 1, end: 5 },
		{ feature, on: True, start: 1, end: 5 },
		{ feature, on: True, start: 0, end: 2 },
		{ feature, on: False, start: 2, end: 5 },
		{ feature, on: False, start: 1, end: 1 },
	],
)

request_feature : Request -> Font.Feature
request_feature = |r| {
	tag = match r.feature {
		Contextual => "calt"
		Ligatures => "liga"
	}
	Font.Feature.{ tag, value: if (r.on) 1 else 0, start: r.start, end: r.end }
}

fixture : Bool -> List(U8)
fixture = |required_first| {
	chars = FontBuild.cmap([
		{
			system: 3,
			encoding: 10,
			subtable: FontBuild.cmap12([
				{ first: 'A', last: 'A', glyph: 1 },
				{ first: 0x10001, last: 0x10001, glyph: 1 },
			]),
		},
	])
	features = [
		{ tag: "calt", lookups: [0, 2] },
		{ tag: "clig", lookups: [0] },
		{ tag: "liga", lookups: [1, 2] },
	]
	lookups = [
		{ kind: 1, subtables: [FontBuild.single1([1, 2, 3, 4, 5, 6], 1)] },
		{ kind: 1, subtables: [FontBuild.single2([1, 2], [4, 6])] },
		# Its outputs also match. An accidental second application is visible.
		{ kind: 1, subtables: [FontBuild.single1(FontBuild.counting(24), 10)] },
	]
	selection = if (required_first) 1 else 0xFFFF
	gsub = FontBuild.layout_listing("latn", [0, 2], selection, features, lookups)
	FontBuild.glyphs_font(FontBuild.counting(40).map(|g| 100 + g), chars, [{ tag: "GSUB", data: gsub }])
}

active : List(Request), Feature, U64 -> Bool
active = |history, feature, cluster|
	history.fold(True, |previous, r|
		if (r.feature == feature and cluster >= r.start and cluster < r.end) r.on else previous)

expected : Ready, U64 -> U32
expected = |ready, cluster| {
	contextual = active(ready.requests, Contextual, cluster)
	ligatures = active(ready.requests, Ligatures, cluster)
	first = ready.required_first or contextual
	# Both input letters start at glyph 1. Lookup 0 makes 2. Lookup 1
	# maps 1 to 4 or 2 to 6, so swapping lookup order changes the answer.
	case_glyph = if (ligatures) (if (first) 6 else 4) else if (first) 2 else 1
	if (contextual or ligatures) case_glyph + 10 else case_glyph
}

agrees : Ready -> Bool
agrees = |ready| {
	run = Font.shape(ready.font, text, Font.ShapeOptions.{ features: ready.requests.map(request_feature) })
	glyphs = clusters.map(|cluster| expected(ready, cluster))
	run.glyphs == glyphs and run.clusters == clusters
		and run.advances == glyphs.map(|glyph| { x: (100 + glyph).to_i32_wrap(), y: 0 })
}

machine : Model.Machine(World, Action)
machine = {
	init: Start,
	actions: |world| match world {
		Start => [Read(False), Read(True)]
		Ready(ready) if ready.requests.len() < 2 => requests.map(|r| Add(r))
		_ => []
	},
	step: |world, action| match (world, action) {
		(Start, Read(required_first)) => match Font.from_bytes(fixture(required_first), Font.ReadOptions.{ strict: True }) {
			Ok(font) => Ready({ font, required_first, requests: [] })
			Err(_) => Rejected
		}
		(Ready(ready), Add(r)) => Ready({ ..ready, requests: ready.requests.append(r) })
		_ => world
	},
	rules: [
		Model.always(
			"the layout fixture reads strictly",
			|world| match world {
				Rejected => False
				_ => True
			},
		),
		Model.always(
			"the shape uses active lookups in font order, once each",
			|world| match world {
				Ready(ready) => agrees(ready)
				_ => True
			},
		),
		goal("only calt requests the shared lookup", |ready| active(ready.requests, Contextual, 1) and !active(ready.requests, Ligatures, 1)),
		goal("only liga requests the shared lookup", |ready| !active(ready.requests, Contextual, 1) and active(ready.requests, Ligatures, 1)),
		goal("neither optional feature applies but the required lookup still runs", |ready| ready.required_first and !active(ready.requests, Contextual, 1) and !active(ready.requests, Ligatures, 1)),
		goal(
			"a later request re-enables calt over the second letter",
			|ready| match ready.requests {
				[off, on] => off.feature == Contextual and !active([off], Contextual, 1) and on.feature == Contextual and active(ready.requests, Contextual, 1)
				_ => False
			},
		),
		goal(
			"a range beginning inside a UTF-8 character covers no cluster",
			|ready| match ready.requests {
				[{ feature: Contextual, on: False, start: 2, end: 5 }] => True
				_ => False
			},
		),
	],
}

goal : Str, (Ready -> Bool) -> Model.Rule(World, Action)
goal = |name, reached| Model.sometimes(
	name,
	|world| match world {
		Ready(ready) => reached(ready)
		_ => False
	},
)

report = |_| Model.explore(
	machine,
	{
		depth: 4,
		# The font is fixed by the read choice. Keep the whole request history
		# because callers pass it in order and overlapping requests differ.
		key: |world| match world {
			Start => Starting
			Rejected => Refused
			Ready(ready) => Shaping(ready.required_first, ready.requests)
		},
		verify: EveryStep,
	},
)
