import build.FontBuild
import font.Font
import fuzz.Fuzz
import fuzz.Model

# OpenType 1.9.1 GPOS type 3 format 1. The run direction selects the
# horizontal pen equations. The lookup flag selects the cross-axis root.
Cursive := {}.{
	check : {} -> Bool
	check = |_| {
		settings.all(
			|config| {
				result = Model.explore(machine(config), { depth: 4, key: |letters| letters, verify: EveryStep })
				if result.verdict == Holds(Exhausted) and result.states == 85 and result.reached.len() == 2 {
					True
				} else {
					crash "cursive shape model ${Str.inspect(config)} ${Str.inspect(result)}"
				}
			},
		) and validation({}) and checkpoints({}) and harfbuzz_checkpoints({}) and mark_timing({})
	}

	target = Fuzz.target_with!({
		name: "cursive-positioning",
		examples: [],
		generator: Fuzz.raw_bytes,
		show: Str.inspect,
		test!: |bytes| {
			mode = bytes.first() ?? 0
			config = { backward: mode.bitwise_and(1) != 0, last_root: mode.bitwise_and(2) != 0, skip_mark: mode.bitwise_and(4) != 0 }
			encoding = if (mode.bitwise_and(8) != 0) Extension else Direct
			letters = bytes.drop_first(1).take_first(32).map(|b| 'A' + b % 6)
			if mode.bitwise_and(16) != 0 {
				damage = if (mode.bitwise_and(32) != 0) BadCoverage else BadAnchor
				if !validates(config, encoding, damage) {
					crash "invalid cursive coverage or anchor accepted"
				}
			} else if mode.bitwise_and(64) != 0 {
				font = prepared(config, encoding)
				count = 65 + (bytes.get(1) ?? 0).to_u64()
				if !long_chain(font, config, count) {
					crash "long cursive chain disagreed for ${Str.inspect((config, count))}"
				}
			} else {
				font = prepared(config, encoding)
				if !agrees(font, config, letters) {
					crash "cursive shape disagreed for ${Str.inspect((config, letters))}"
				}
			}
			Fuzz.keep
		},
	})
}

Config : { backward : Bool, last_root : Bool, skip_mark : Bool }

LookupEncoding : [Direct, Extension]

Damage : [None, BadCoverage, BadAnchor, BadCount]

settings : List(Config)
settings = [False, True].join_map(|backward| [False, True].join_map(|last_root| [False, True].map(|skip_mark| { backward, last_root, skip_mark })))

Point : { x : I32, y : I32 }

Glyph : { id : U32, base : I32, entry : [Present(Point), Absent], exit : [Present(Point), Absent] }

facts : U8 -> Glyph
facts = |ch| match ch {
	'A' => { id: 1, base: 100, entry: Present({ x: -7, y: 2 }), exit: Present({ x: 54, y: 11 }) }
	'B' => { id: 2, base: 130, entry: Present({ x: 13, y: -6 }), exit: Present({ x: 82, y: 24 }) }
	'C' => { id: 3, base: 160, entry: Present({ x: -9, y: 10 }), exit: Present({ x: 65, y: -11 }) }
	'D' => { id: 4, base: 190, entry: Absent, exit: Present({ x: 77, y: 5 }) }
	'E' => { id: 5, base: 0, entry: Absent, exit: Absent }
	_ => { id: 6, base: 220, entry: Present({ x: 19, y: -5 }), exit: Absent }
}

cursive_table : Damage -> List(U8)
cursive_table = |damage| {
	records = ['A', 'B', 'C', 'D', 'F'].map(facts)
	coverage = if (damage == BadCoverage) FontBuild.coverage1([1, 2, 3, 6, 4]) else FontBuild.coverage1([1, 2, 3, 4, 6])
	anchor = |value, format| match value {
		Absent => U16(0)
		Present({ x, y }) => Ref(FontBuild.pack([U16(format), I16(x.to_i64()), I16(y.to_i64())].concat(if (format == 2) [U16(0)] else [])))
	}
	fields = records.join_map(
		|glyph| [
			anchor(glyph.entry, if (glyph.id == 1 and damage == BadAnchor) 4 else 1),
			anchor(glyph.exit, if (glyph.id == 2) 2 else 1),
		],
	)
	FontBuild.pack([U16(1), Ref(coverage), U16(if (damage == BadCount) 4 else 5)].concat(fields))
}

fixture : Config, LookupEncoding, Damage -> List(U8)
fixture = |config, encoding, damage| {
	cursive = cursive_table(damage)
	flag = (if (config.last_root) 1 else 0) + (if (config.skip_mark) 8 else 0)
	lookup = if (encoding == Extension) { kind: 9, flag, set: 0, subtables: [FontBuild.extension(3, cursive)] } else { kind: 3, flag, set: 0, subtables: [cursive] }
	gpos = FontBuild.patch(FontBuild.flagged_layout("curs", [lookup]), 12, (if (config.backward) "hebr" else "latn").to_utf8())
	font_file(gpos)
}

font_file : List(U8) -> List(U8)
font_file = |gpos| {
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'F', glyph: 1 }]) }])
	gdef = FontBuild.pack([U32(0x00010000), Ref(FontBuild.classes1(1, [1, 1, 1, 1, 3, 1])), U16(0), U16(0), U16(0)])
	FontBuild.glyphs_font([500, 100, 130, 160, 190, 0, 220], cmap, [{ tag: "GDEF", data: gdef }, { tag: "GPOS", data: gpos }])
}

prepared : Config, LookupEncoding -> Font
prepared = |config, encoding| Font.from_bytes(fixture(config, encoding, None), Font.ReadOptions.{ strict: True }) ?? crash "valid cursive fixture did not read"

validates : Config, LookupEncoding, Damage -> Bool
validates = |config, encoding, damage| match Font.from_bytes(fixture(config, encoding, damage), Font.ReadOptions.{}) {
	Err(problems) => problems.any(
		|p| match p {
			BadTable({ table, offset: _ }) => table == "GPOS"
			_ => False
		},
	)
	Ok(_) => False
}

validation : {} -> Bool
validation = |_| [Direct, Extension].all(|encoding| [BadAnchor, BadCoverage, BadCount].all(|damage| validates({ backward: False, last_root: False, skip_mark: False }, encoding, damage)))

options : Config -> Font.ShapeOptions
options = |config| Font.ShapeOptions.{ script: if (config.backward) "Hebr" else "Latn", direction: if (config.backward) RightToLeft else LeftToRight, features: [Font.Feature.{ tag: "curs" }] }

Row : { glyph : U32, advance : I32, offset : Point, cluster : U64 }

# Derive links from the filtered source. Then compute each glyph's pen
# displacement from its own entry/exit and sum the connected anchor
# height differences from the required baseline endpoint.
expected : Config, List(U8) -> List(Row)
expected = |config, letters| {
	visible = letters.map_with_index(|ch, i| { ch, i }).keep_if(|item| !config.skip_mark or item.ch != 'E')
	var $edges = []
	for from in 0..<visible.len() {
		match (visible.get(from), visible.get(from + 1)) {
			(Ok(left), Ok(right)) => match ((facts(left.ch)).exit, (facts(right.ch)).entry) {
				(Present(exit), Present(entry)) => {
					$edges = $edges.append({ from: left.i, to: right.i, exit, entry })
				}
				_ => {}
			}
			_ => {}
		}
	}
	edges = $edges
	rows = letters.map_with_index(
		|ch, i| {
			glyph = facts(ch)
			incoming = edges.keep_if(|edge| edge.to == i).first()
			outgoing = edges.keep_if(|edge| edge.from == i).first()
			(entry_x, has_incoming) = match incoming {
				Ok(edge) => (edge.entry.x, True)
				Err(_) => (0, False)
			}
			(exit_x, has_outgoing) = match outgoing {
				Ok(edge) => (edge.exit.x, True)
				Err(_) => (0, False)
			}
			x = if (config.backward) -exit_x else -entry_x
			advance = x + (if (config.backward and has_incoming) entry_x else if (!config.backward and has_outgoing) exit_x else glyph.base)
			var $y = 0
			var $at = i
			for _ in edges {
				step = edges.keep_if(|edge| if (config.last_root) edge.from == $at else edge.to == $at).first()
				match step {
					Ok(edge) => {
						$y = $y + (if (config.last_root) edge.entry.y - edge.exit.y else edge.exit.y - edge.entry.y)
						$at = if (config.last_root) edge.to else edge.from
					}
					Err(_) => {}
				}
			}
			{ glyph: glyph.id, advance, offset: { x, y: $y }, cluster: i }
		},
	)
	if (config.backward) rows.fold([], |visual, row| visual.prepend(row)) else rows
}

agrees : Font, Config, List(U8) -> Bool
agrees = |font, config, letters| {
	text = Str.from_utf8(letters) ?? ""
	run = Font.shape(font, text, options(config))
	want = expected(config, letters)
	good = run.glyphs == want.map(|row| row.glyph)
		and run.clusters == want.map(|row| row.cluster)
		and run.advances == want.map(|row| { x: row.advance, y: 0 })
		and run.offsets == want.map(|row| row.offset)
	if (good) True else crash "cursive ${text} with ${Str.inspect(config)} gave ${Str.inspect(run)}. Expected ${Str.inspect(want)}"
}

machine : Config -> Model.Machine(List(U8), U8)
machine = |config| {
	font = prepared(config, Direct)
	{
		init: [],
		actions: |letters| if (letters.len() < 3) ['A', 'B', 'D', 'E'] else [],
		step: |letters, ch| letters.append(ch),
		rules: [
			Model.always("anchors agree with independent pen geometry", |letters| agrees(font, config, letters)),
			Model.sometimes("a mark lies between covered bases", |letters| letters == ['A', 'E', 'B']),
			Model.sometimes("an absent entry ends a chain", |letters| letters == ['A', 'D', 'B']),
		],
	}
}

checkpoints : {} -> Bool
checkpoints = |_| settings.all(
	|config| {
		font = prepared(config, Extension)
		["ABC", "AEBC", "AFBC", "ABDC"].all(|s| agrees(font, config, Str.to_utf8(s)))
	},
)

# HarfBuzz 14.6.0 on independently built FontTools equivalents. Changing
# the lookup root moves the baseline to the other end of the chain.
harfbuzz_checkpoints : {} -> Bool
harfbuzz_checkpoints = |_| {
	for { backward, last_root, advances, xs, ys } in [
		{ backward: False, last_root: False, advances: [54, 0, 69, 169], xs: [0, 0, -13, 9], ys: [0, 0, 17, 31] },
		{ backward: False, last_root: True, advances: [54, 0, 69, 169], xs: [0, 0, -13, 9], ys: [-31, 0, -14, 0] },
		{ backward: True, last_root: False, advances: [-9, -69, 0, 46], xs: [0, -82, 0, -54], ys: [31, 17, 0, 0] },
		{ backward: True, last_root: True, advances: [-9, -69, 0, 46], xs: [0, -82, 0, -54], ys: [0, -14, 0, -31] },
	] {
		config = { backward, last_root, skip_mark: True }
		font = prepared(config, Direct)
		run = Font.shape(font, "AEBC", options(config))
		glyphs = if (backward) [3, 2, 5, 1] else [1, 5, 2, 3]
		clusters = if (backward) [3, 2, 1, 0] else [0, 1, 2, 3]
		flags = if (backward) [True, True, True, False] else [False, True, True, True]
		if (run.glyphs, run.clusters, run.advances.map(|v| v.x), run.offsets.map(|v| v.x), run.offsets.map(|v| v.y), run.flags.map(Font.is_unsafe_to_break)) != (glyphs, clusters, advances, xs, ys, flags) {
			return False
		}
	}
	# HarfBuzz stops propagating at 64 links before resuming its scan.
	long = { backward: False, last_root: True, skip_mark: False }
	font = prepared(long, Direct)
	run = Font.shape(font, "A".repeat(130), options(long))
	indices = [0, 1, 64, 65, 129]
	indices.map(|i| (run.offsets.get(i) ?? { x: 0, y: 0 }).y) == [-585, -576, -9, -576, 0]
}

long_chain : Font, Config, U64 -> Bool
long_chain = |font, config, count| {
	run = Font.shape(font, "A".repeat(count), options(config))
	# If the root is at the far end of the visual scan, HarfBuzz clears
	# one edge after each 64 propagated links and starts a fresh segment.
	far = config.backward != config.last_root
	y_sign = if (config.last_root) -9 else 9
	indices = FontBuild.counting(count)
	heights = indices.map(
		|i| {
			steps = if (far) (65 - i % 65).min(count - 1 - i) else i
			y_sign * steps.to_i32_wrap()
		},
	)
	advance = |i| if config.backward {
		if (i == 0) -7 else if (i == count - 1) 46 else -61
	} else if (i == 0) 54 else if (i == count - 1) 107 else 61
	run.glyphs == List.repeat(1, count)
		and run.clusters == indices.map(|i| if (config.backward) count - 1 - i else i)
		and run.offsets.map(|v| v.y) == heights
		and run.advances.map(|v| v.x) == indices.map(advance)
}

# A mark follows the cross-axis offset of its base as of mark lookup
# time. Its x position still uses the final base advance in both orders.
mark_timing : {} -> Bool
mark_timing = |_| {
	anchor = |x, y| FontBuild.pack([U16(1), I16(x), I16(y)])
	marks = FontBuild.pack([U16(1), U16(0), Ref(anchor(-3, 6))])
	bases = FontBuild.pack([U16(1), Ref(anchor(35, 50))])
	mark = FontBuild.pack([U16(1), Ref(FontBuild.coverage1([5])), Ref(FontBuild.coverage1([2])), U16(1), Ref(marks), Ref(bases)])
	cursive_lookup = FontBuild.pack([U16(3), U16(8), U16(1), Ref(cursive_table(None))])
	mark_lookup = FontBuild.pack([U16(4), U16(0), U16(1), Ref(mark)])
	language = FontBuild.pack([U16(0), U16(0xFFFF), U16(2), U16(0), U16(1)])
	script = FontBuild.pack([U16(1), Tag("latn"), Ref(FontBuild.pack([Ref(language), U16(0)]))])
	both_orders = [True, False].all(
		|curs_first| {
			feature = |index| FontBuild.pack([U16(0), U16(1), U16(index)])
			features = FontBuild.pack([U16(2), Tag("curs"), Ref(feature(if (curs_first) 0 else 1)), Tag("mark"), Ref(feature(if (curs_first) 1 else 0))])
			lookups = if (curs_first) [Ref(cursive_lookup), Ref(mark_lookup)] else [Ref(mark_lookup), Ref(cursive_lookup)]
			gpos = FontBuild.pack([U32(0x00010000), Ref(script), Ref(features), Ref(FontBuild.pack([U16(2)].concat(lookups)))])
			font = Font.from_bytes(font_file(gpos), Font.ReadOptions.{ strict: True }) ?? crash "cursive and mark fixture did not read"
			run = Font.shape(font, "ABEC", Font.ShapeOptions.{})
			mark_y = if (curs_first) 61 else 44
			run.glyphs == [1, 2, 5, 3]
				and run.clusters == [0, 1, 2, 3]
				and run.advances.map(|v| v.x) == [54, 69, 0, 169]
				and run.offsets == [{ x: 0, y: 0 }, { x: -13, y: 17 }, { x: -44, y: mark_y }, { x: 9, y: 31 }]
		},
	)
	# A second lookup roots the same chain in the opposite direction.
	# The two old links must be reversed or detached as each pair joins.
	reversed_lookups = [1, 0].map(|flag| { kind: 3, flag, set: 0, subtables: [cursive_table(None)] })
	reversed = Font.from_bytes(font_file(FontBuild.flagged_layout("curs", reversed_lookups)), Font.ReadOptions.{ strict: True }) ?? crash "two cursive lookups did not read"
	run = Font.shape(reversed, "ABA", Font.ShapeOptions.{})
	both_orders
		and run.advances.map(|v| v.x) == [54, 69, 107]
		and run.offsets == [{ x: 0, y: 0 }, { x: -13, y: 17 }, { x: 7, y: 39 }]
}
