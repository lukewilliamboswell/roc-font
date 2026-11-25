import build.FontBuild
import font.Font
import fuzz.Model

Direction := [].{
	check : {} -> Bool
	check = |{}| {
		report = Model.explore(machine({}), Model.Options.{ depth: 5, key: |state| state })
		if (report.verdict, report.states, report.steps, report.depth, report.reached.len()) != (Holds(Exhausted), 241, 240, 4, 6) {
			crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
		}
		True
	}
}

Scenario : [LatinDefault, LatinRtl, ThaanaDefault, ThaanaLtr, LatinRtlOffInitial, LatinLtrRtlmExplicit]

Atom : [Open, Angle, Integral]

State : [Unchosen, Text({ scenario : Scenario, atoms : List(Atom) })]

Action : [Choose(Scenario), Append(Atom)]

Item : { glyph : U32, cluster : U64 }

# The mirror of '(' and the original '<' share glyph 2. Only '(' has
# a mapped Unicode mirror. U+2232 exercises a glyph-only mirrored form.
# https://learn.microsoft.com/en-us/typography/opentype/spec/features_pt#tag-rtlm
font_with_mirrors : {} -> Font
font_with_mirrors = |{}| {
	cmap = FontBuild.cmap([
		{
			system: 3,
			encoding: 10,
			subtable: FontBuild.cmap12([
				{ first: '(', last: '(', glyph: 1 },
				{ first: ')', last: ')', glyph: 2 },
				{ first: '<', last: '<', glyph: 2 },
				{ first: 0x2232, last: 0x2232, glyph: 4 },
			]),
		},
	])
	lookups = [
		{ kind: 1, subtables: [FontBuild.single2([2, 4], [3, 5])] },
		{
			kind: 6,
			subtables: [
				FontBuild.chain3([], [[2]], [[3]], [{ at: 0, lookup: 2 }]),
				FontBuild.chain3([], [[1]], [[2]], [{ at: 0, lookup: 2 }]),
			],
		},
		{ kind: 1, subtables: [FontBuild.single2([1, 2], [7, 6])] },
	]
	gsub = FontBuild.layout("DFLT", [{ tag: "calt", lookups: [1] }, { tag: "rtlm", lookups: [0] }], lookups)
	bytes = FontBuild.glyphs_font(List.repeat(500, 8), cmap, [{ tag: "GSUB", data: gsub }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "direction model fixture did not read strictly"
}

options_for : Scenario -> Font.ShapeOptions
options_for = |scenario| match scenario {
	LatinDefault => Font.ShapeOptions.{ script: "Latn" }
	LatinRtl => Font.ShapeOptions.{ script: "Latn", direction: RightToLeft }
	ThaanaDefault => Font.ShapeOptions.{ script: "Thaa" }
	ThaanaLtr => Font.ShapeOptions.{ script: "Thaa", direction: LeftToRight }
	LatinRtlOffInitial => Font.ShapeOptions.{ script: "Latn", direction: RightToLeft, features: [Font.Feature.{ tag: "rtlm", value: 0, end: 1 }] }
	LatinLtrRtlmExplicit => Font.ShapeOptions.{ script: "Latn", direction: LeftToRight, features: [Font.Feature.{ tag: "rtlm" }] }
}

atom_text : Atom -> Str
atom_text = |atom| match atom {
	Open => "("
	Angle => "<"
	Integral => "∲"
}

expected : List(Atom), Scenario -> List(Item)
expected = |atoms, scenario| {
	rtl = [LatinRtl, ThaanaDefault, LatinRtlOffInitial].contains(scenario)
	native_rtl = [ThaanaDefault, ThaanaLtr].contains(scenario)
	var $offset = 0
	var $mapped = []
	for atom in atoms {
		automatic = rtl and (scenario != LatinRtlOffInitial or $offset != 0)
		alternate = automatic or scenario == LatinLtrRtlmExplicit
		glyph : U32
		glyph = match atom {
			Open => if (rtl) 2 else 1
			Angle => if (alternate) 3 else 2
			Integral => if (alternate) 5 else 4
		}
		$mapped = $mapped.append({ glyph, cluster: $offset })
		$offset = $offset + atom_text(atom).to_utf8().len()
	}
	# Context is evaluated in the script's shaping order. Each rule reads
	# just the next item, whose glyph has yet to receive contextual forms.
	ordered = if (rtl != native_rtl) $mapped.fold([], |reversed, item| reversed.prepend(item)) else $mapped
	var $contextual = []
	for i in 0..<ordered.len() {
		item = ordered.get(i) ?? crash "index is inside the direction model input"
		next = (ordered.get(i + 1) ?? { glyph: 0, cluster: 0 }).glyph
		glyph = match (item.glyph, next) {
			(2, 3) => 6
			(1, 2) => 7
			_ => item.glyph
		}
		$contextual = $contextual.append({ ..item, glyph })
	}
	if (native_rtl) $contextual.fold([], |reversed, item| reversed.prepend(item)) else $contextual
}

machine : {} -> Model.Machine(State, Action)
machine = |{}| {
	face = font_with_mirrors({})
	{
		init: Unchosen,
		actions: |state| match state {
			Unchosen => [Choose(LatinDefault), Choose(LatinRtl), Choose(ThaanaDefault), Choose(ThaanaLtr), Choose(LatinRtlOffInitial), Choose(LatinLtrRtlmExplicit)]
			Text({ scenario: _, atoms }) => if (atoms.len() < 3) [Append(Open), Append(Angle), Append(Integral)] else []
		},
		step: |state, action| match (state, action) {
			(Unchosen, Choose(scenario)) => Text({ scenario, atoms: [] })
			(Text({ scenario, atoms }), Append(atom)) => Text({ scenario, atoms: atoms.append(atom) })
			_ => state
		},
		rules: [
			Model.always(
				"mirroring, script order and source byte ranges select the glyphs and clusters",
				|state| match state {
					Unchosen => True
					Text({ scenario, atoms }) => {
						text = atoms.fold("", |s, atom| s.concat(atom_text(atom)))
						run = Font.shape(face, text, options_for(scenario))
						want = expected(atoms, scenario)
						run.glyphs == want.map(|item| item.glyph) and run.clusters == want.map(|item| item.cluster)
					}
				},
			),
			Model.sometimes("the mapped Unicode mirror precedes the glyph alternate", |s| s == Text({ scenario: LatinRtl, atoms: [Open, Angle] })),
			Model.sometimes("script direction changes the contextual match in a right-to-left run", |s| s == Text({ scenario: ThaanaDefault, atoms: [Open, Angle] })),
			Model.sometimes("an explicit direction shapes Thaana left-to-right", |s| s == Text({ scenario: ThaanaLtr, atoms: [Open, Angle] })),
			Model.sometimes("rtlm exclusions use the original byte position", |s| s == Text({ scenario: LatinRtlOffInitial, atoms: [Angle, Integral] })),
			Model.sometimes("excluding rtlm preserves Unicode mirroring", |s| s == Text({ scenario: LatinRtlOffInitial, atoms: [Open, Angle] })),
			Model.sometimes("explicit rtlm applies in a left-to-right run", |s| s == Text({ scenario: LatinLtrRtlmExplicit, atoms: [Integral, Open] })),
		],
	}
}
