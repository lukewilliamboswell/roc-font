import build.FontBuild
import build.MarkBuild
import font.Font
import fuzz.Model

# A mark lookup tries its subtables in order. Its input coverage, and the
# feature mask at that input, govern attachment independently of GDEF.
# https://learn.microsoft.com/en-us/typography/opentype/spec/gpos
MarkCertification := {}.{
	check : {} -> Bool
	check = |_| {
		report = Model.explore(machine({}), Model.Options.{ depth: 8, key: key, verify: EveryStep })
		report.verdict == Holds(Exhausted) and report.states == 373 and report.reached.len() == 5
	}
}

CoverageForm : [Glyphs, Ranges]

Location : [Default, MixedFirst, OnlyMarks]

Sample : [Mark, Shared, Nonmark, UncoveredMark, UncoveredLetter]

Config : { encoding : CoverageForm, location : Location, cut : Bool, text : List(Sample) }

State : [Unchosen, Shaping({ config : Config, face : Font })]

Action : [Read(CoverageForm), Move(Location), Mask(Bool), Append(Sample)]

samples : List(Sample)
samples = [Mark, Shared, Nonmark, UncoveredMark, UncoveredLetter]

key : State -> [Unchosen, Shaping(Config)]
key = |state| match state {
	Unchosen => Unchosen
	Shaping(s) => Shaping(s.config)
}

# The input class is deliberately a mix. In particular, the last glyph
# in the two-glyph format 2 range is the nonmark.
mark_subtable : CoverageForm, U64, I64, I64 -> List(U8)
mark_subtable = |encoding, first, x, y| {
	coverage = match encoding {
		Glyphs => FontBuild.coverage1([first, first + 1])
		Ranges => FontBuild.coverage2([{ first, last: first + 1, index: 0 }])
	}
	marks = MarkBuild.mark_array([
		{ glyph: first, class: 0, anchor: MarkBuild.anchor(11, 7) },
		{ glyph: first + 1, class: 0, anchor: MarkBuild.anchor(13, 17) },
	])
	base = FontBuild.pack([U16(1), Ref(MarkBuild.anchor(x, y))])
	FontBuild.pack([U16(1), Ref(coverage), Ref(FontBuild.coverage1([1])), U16(1), Ref(marks), Ref(base)])
}

fixture : CoverageForm -> Font
fixture = |encoding| {
	certified = mark_subtable(encoding, 3, 125, 210)
	mixed = mark_subtable(encoding, 4, 260, 450)
	variation = |min, max, lookup| { conditions: [{ axis: 0, min, max }], substitutions: [{ feature: 0, lookups: [lookup] }] }
	layout = FontBuild.layout_varied(
		"latn",
		[{ tag: "mark", lookups: [0] }],
		[
			{ kind: 4, subtables: [certified, mixed] },
			{ kind: 4, subtables: [mixed, certified] },
			{ kind: 4, subtables: [certified] },
		],
		FontBuild.feature_variations([variation(4096, 8192, 1), variation(12288, 16384, 2)]),
	)
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'G', glyph: 1 }]) }])
	gdef = MarkBuild.gdef([{ first: 1, last: 2, class: 1 }, { first: 3, last: 4, class: 3 }, { first: 6, last: 6, class: 3 }], [])
	fvar = FontBuild.fvar([{ tag: "TEST", min: 0, default: 0, max: 1000 }])
	bytes = FontBuild.glyphs_font([500, 612, 390, 0, 0, 330, 0, 410], cmap, [{ tag: "GDEF", data: gdef }, { tag: "GPOS", data: layout }, { tag: "fvar", data: fvar }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "Mark certification fixture was rejected"
}

source : Sample -> Str
source = |sample| match sample {
	Mark => "AC"
	Shared => "AD"
	Nonmark => "AE"
	UncoveredMark => "AF"
	UncoveredLetter => "AG"
}

Row : { glyph : U32, cluster : U64, advance : I32, x : I32, y : I32, flag : U8 }

expected : Config -> List(Row)
expected = |config| config.text.map_with_index(
	|sample, i| {
		pen = 612.I32
		(glyph, advance) = match sample {
			Mark => (3, 0)
			Shared => (4, 0)
			Nonmark => (5, 330)
			UncoveredMark => (6, 0)
			UncoveredLetter => (7, 410)
		}
		attachment = if (config.cut and i == 0) None else match sample {
			Mark => At(114, 203)
			Shared => if (config.location == MixedFirst) At(249, 443) else At(112, 193)
			Nonmark => if (config.location == OnlyMarks) None else At(247, 433)
			UncoveredMark | UncoveredLetter => None
		}
		(x, y, flag) = match attachment {
			None => (0, 0, 0)
			At(ax, ay) => (ax - pen, ay, 1)
		}
		[
			{ glyph: 1, cluster: 2 * i, advance: pen, x: 0, y: 0, flag: 0 },
			{ glyph, cluster: 2 * i + 1, advance, x, y, flag },
		]
	},
).join_map(|rows| rows)

agrees : Font, Config -> Bool
agrees = |face, config| {
	features = if (config.cut) [Font.Feature.{ tag: "mark", value: 0, start: 1, end: 2 }] else []
	text = Str.join_with(config.text.map(source), "")
	plan = Font.plan(face, Font.ShapeOptions.{ script: "Latn", clusters: Characters, features })
	run = Font.shape_planned(face, plan, text)
	rows = expected(config)
	coordinate = match config.location {
		Default => 0
		MixedFirst => 6554
		OnlyMarks => 14746
	}
	Font.coordinates(face) == [{ tag: "TEST", value: coordinate }] and run.glyphs == rows.map(|r| r.glyph) and run.clusters == rows.map(|r| r.cluster) and run.flags == rows.map(|r| r.flag)
		and run.advances == rows.map(|r| { x: r.advance, y: 0 }) and run.offsets == rows.map(|r| { x: r.x, y: r.y })
}

machine : {} -> Model.Machine(State, Action)
machine = |_| {
	glyphs = fixture(Glyphs)
	ranges = fixture(Ranges)
	{
		init: Unchosen,
		actions: |state| match state {
			Unchosen => [Read(Glyphs), Read(Ranges)]
			Shaping(s) => {
				edits = [Move(Default), Move(MixedFirst), Move(OnlyMarks), Mask(True), Mask(False)]
				if (s.config.text.len() < 2) edits.concat(samples.map(|sample| Append(sample))) else edits
			}
		},
		step: |state, action| match (state, action) {
			(Unchosen, Read(encoding)) => Shaping({ config: { encoding, location: Default, cut: False, text: [] }, face: if (encoding == Glyphs) glyphs else ranges })
			(Shaping(s), Move(location)) => {
				axes = match location {
					Default => []
					MixedFirst => [{ tag: "TEST", value: 400 }]
					OnlyMarks => [{ tag: "TEST", value: 900 }]
				}
				config = s.config
				Shaping({ config: { ..config, location }, face: Font.at(s.face, Font.Variation.{ axes }) })
			}
			(Shaping(s), Mask(cut)) => {
				config = s.config
				Shaping({ ..s, config: { ..config, cut } })
			}
			(Shaping(s), Append(sample)) => {
				config = s.config
				Shaping({ ..s, config: { ..config, text: config.text.append(sample) } })
			}
			_ => state
		},
		rules: [
			Model.always(
				"mark attachment follows all input coverages of the selected lookup",
				|state| match state {
					Unchosen => True
					Shaping(s) => agrees(s.face, s.config)
				},
			),
			Model.sometimes("a nonmark matches the last glyph of the second coverage range", |s| key(s) == Shaping({ encoding: Ranges, location: Default, cut: False, text: [Nonmark] })),
			Model.sometimes("the first subtable wins for shared input at an alternate location", |s| key(s) == Shaping({ encoding: Glyphs, location: MixedFirst, cut: False, text: [Shared] })),
			Model.sometimes("a real mark and nonmark both reach a mixed lookup", |s| key(s) == Shaping({ encoding: Ranges, location: Default, cut: False, text: [Mark, Nonmark] })),
			Model.sometimes("mask disables only the first attachment", |s| key(s) == Shaping({ encoding: Ranges, location: Default, cut: True, text: [Nonmark, Nonmark] })),
			Model.sometimes_step("returning from a marks-only location restores mixed coverage", |{ before, after, action: _ }| key(before) == Shaping({ encoding: Ranges, location: OnlyMarks, cut: False, text: [Nonmark] }) and key(after) == Shaping({ encoding: Ranges, location: Default, cut: False, text: [Nonmark] })),
		],
	}
}
