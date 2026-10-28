app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import fuzz.Fuzz
import font.Font
import build.FontBuild

## Substitution lookups, one kind at a time. The first input byte picks the
## kind (single, multiple, ligature, contextual, chained contextual, or an
## extension holding a single, multiple or ligature substitution, by its
## value modulo 6 and, for extensions, bits 3 and 4); every further byte
## chooses one lookup: which glyphs it covers, its subtable format, what it
## substitutes, and for contextual lookups the context and which nested
## substitution it calls. Lookup `i` reads only glyphs of its own band of
## eight (from glyph 16 + 8 i) and writes only glyphs 1 to 15, which no
## lookup reads, so lookups never feed each other. The same choices build
## a font at two sizes, 8 and 64 lookups (all of feature `liga`); the text
## uses glyphs of the first four bands and outputs.
##
## Contract: both fonts read; with ligatures off the glyphs are the text's;
## shaping the text gives the same run with both fonts (the extra lookups
## never match it) and the same run twice; runs are index-aligned with
## clusters in range and in order, within HarfBuzz's growth bound; tracing
## gives the same run with one origin per glyph, `Mapped` for every band
## glyph (lookups write only glyphs 1 to 15) and `liga` for every
## substituted one, a ligature joining at least two glyphs; checking the
## budgets finds the run complete. Reading
## and planning take at most `10 × small + 256` allocations for 8 times the
## lookups (linear in lookups), shaping the same text with a plan costs no
## more allocations with 8 times the lookups (constant per call), and
## nothing leaks.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = bytes.first() ?? 0
	picks = bytes.drop_first(1).take_first(64)
	small = recipe(choice, picks, 8)
	large = recipe(choice, picks, 64)
	text = text_of(picks)
	small_font = check!(small, text, text_glyphs(picks))
	large_font = check!(large, text, text_glyphs(picks))
	small_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(small, Font.ReadOptions.{}))
	large_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(large, Font.ReadOptions.{}))
	Fuzz.expect_no_leaks!(|{}| Font.from_bytes(large, Font.ReadOptions.{}))
	if large_read.allocations > 10 * small_read.allocations + 256 {
		crash "reading 8 times the lookups took ${large_read.allocations.to_str()} allocations, against ${small_read.allocations.to_str()}"
	}
	small_plan = Fuzz.measure_allocs!(|{}| Font.plan(small_font, Font.ShapeOptions.{}))
	large_plan = Fuzz.measure_allocs!(|{}| Font.plan(large_font, Font.ShapeOptions.{}))
	Fuzz.expect_no_leaks!(|{}| Font.plan(large_font, Font.ShapeOptions.{}))
	if large_plan.allocations > 10 * small_plan.allocations + 256 {
		crash "planning 8 times the lookups took ${large_plan.allocations.to_str()} allocations, against ${small_plan.allocations.to_str()}"
	}
	small_shape = Fuzz.measure_allocs!(|{}| Font.shape_planned(small_font, small_plan.value, text))
	large_shape = Fuzz.measure_allocs!(|{}| Font.shape_planned(large_font, large_plan.value, text))
	Fuzz.expect_no_leaks!(|{}| Font.shape_planned(large_font, large_plan.value, text))
	if large_shape.allocations > small_shape.allocations + 8 {
		crash "shaping one text with 8 times the lookups took ${large_shape.allocations.to_str()} allocations, against ${small_shape.allocations.to_str()}"
	}
	if Str.inspect(small_shape.value) != Str.inspect(large_shape.value) {
		crash "lookups that never match the text changed its run: ${Str.inspect(small_shape.value.glyphs)} against ${Str.inspect(large_shape.value.glyphs)}"
	}
	Fuzz.keep
}

pick : List(U8), U64 -> U64
pick = |bytes, i| if (bytes.is_empty()) 0 else (bytes.get(i % bytes.len()) ?? 0).to_u64()

## The first glyph of lookup `i`'s band.
band : U64 -> U64
band = |i| 16 + 8 * i

## The glyphs of a band a mask byte selects (never none).
selected : U64, U64 -> List(U64)
selected = |base, mask| FontBuild.counting(8).keep_if(|t| t == 0 or (mask.bitwise_or(1).shr_zf_wrap(t.to_u8_wrap()).bitwise_and(1)) != 0).map(|t| base + t)

## An output glyph, 1 to 15.
output : U64 -> U64
output = |k| 1 + k % 15

single : U64, U64, U64 -> List(U8)
single = |base, b, c| {
	covered = selected(base, b)
	if c.bitwise_and(1) == 0 {
		FontBuild.single1_over(FontBuild.coverage1(covered), 1 + (c.shr_zf_wrap(1) % 8).to_i64_wrap() - base.to_i64_wrap())
	} else {
		FontBuild.single2_over(FontBuild.coverage1(covered), covered.map_with_index(|_, t| output(c + 3 * t)))
	}
}

multiple : U64, U64, U64 -> List(U8)
multiple = |base, b, c| {
	covered = selected(base, b)
	FontBuild.multiple(covered, covered.map_with_index(|_, t| FontBuild.counting((c + t) % 4).map(|u| output(c + t + 5 * u))))
}

ligature : U64, U64, U64 -> List(U8)
ligature = |base, b, c| {
	covered = selected(base, b)
	FontBuild.ligature(covered, covered.map_with_index(|_, t| [{ glyph: output(c + t), rest: [base + (c + t) % 8] }, { glyph: output(c + 2 * t + 1), rest: [base + c.shr_zf_wrap(3) % 8, base + t % 8] }]))
}

## The classes of a band: odd and even glyphs.
band_classes : U64 -> List(U8)
band_classes = |base| FontBuild.classes1(base, [1, 2, 1, 2, 1, 2, 1, 2])

class_in_band : U64, U64 -> U64
class_in_band = |base, g| 1 + (g - base) % 2

## A context rule set list for format 2: the rule at the first glyph's
## class.
class_sets : U64, List(U8) -> List(List(List(U8)))
class_sets = |class, rule| FontBuild.counting(3).map(|k| if (k == class) [rule] else [])

## A contextual subtable over band `base`, calling lookup `nested` at one
## position of its input. Format by `c % 3`.
context : U64, U64, U64, U64 -> List(U8)
context = |base, nested, b, c| {
	first = base + b % 8
	rest = if (c.bitwise_and(4) == 0) [base + b.shr_zf_wrap(3) % 8] else [base + b.shr_zf_wrap(3) % 8, base + (b + c) % 8]
	calls = [{ at: c.shr_zf_wrap(3) % (rest.len() + 1), lookup: nested }]
	match c % 3 {
		0 => FontBuild.context1([first], [[FontBuild.rule(rest, calls)]])
		1 => FontBuild.context2([first], band_classes(base), class_sets(class_in_band(base, first), FontBuild.rule(rest.map(|g| class_in_band(base, g)), calls)))
		_ => FontBuild.context3([[first]].concat(rest.map(|g| [g])), calls)
	}
}

## A chained contextual subtable over band `base`: `context` with a glyph
## before and after it (either may be absent).
chained : U64, U64, U64, U64 -> List(U8)
chained = |base, nested, b, c| {
	first = base + b % 8
	rest = if (c.bitwise_and(4) == 0) [] else [base + b.shr_zf_wrap(3) % 8]
	back = if (c.bitwise_and(8) == 0) [] else [base + c.shr_zf_wrap(4) % 8]
	ahead = if (c.bitwise_and(0x80) == 0) [base + (b + c) % 8] else []
	calls = [{ at: c.shr_zf_wrap(5) % (rest.len() + 1), lookup: nested }]
	classes = |list| list.map(|g| class_in_band(base, g))
	match c % 3 {
		0 => FontBuild.chain1([first], [[FontBuild.chain_rule(back, rest, ahead, calls)]])
		1 => FontBuild.chain2([first], band_classes(base), band_classes(base), band_classes(base), class_sets(class_in_band(base, first), FontBuild.chain_rule(classes(back), classes(rest), classes(ahead), calls)))
		_ => FontBuild.chain3(back.map(|g| [g]), [[first]].concat(rest.map(|g| [g])), ahead.map(|g| [g]), calls)
	}
}

## A font of `count` lookups of the kind the choice byte picks, with the
## nested single substitutions contextual lookups call after them.
recipe : U8, List(U8), U64 -> List(U8)
recipe = |choice, picks, count| {
	kind = choice.to_u64() % 6
	inner = choice.shr_zf_wrap(3).to_u64() % 3
	lookups = FontBuild.counting(count).map(
		|i| {
			base = band(i)
			b = pick(picks, 2 * i)
			c = pick(picks, 2 * i + 1)
			match kind {
				0 => { kind: 1, subtables: [single(base, b, c)] }
				1 => { kind: 2, subtables: [multiple(base, b, c)] }
				2 => { kind: 4, subtables: [ligature(base, b, c)] }
				3 => { kind: 5, subtables: [context(base, count + i, b, c)] }
				4 => { kind: 6, subtables: [chained(base, count + i, b, c)] }
				_ =>
					match inner {
						0 => { kind: 7, subtables: [FontBuild.extension(1, single(base, b, c))] }
						1 => { kind: 7, subtables: [FontBuild.extension(2, multiple(base, b, c))] }
						_ => { kind: 7, subtables: [FontBuild.extension(4, ligature(base, b, c))] }
					}
			}
		},
	)
	nested = if (kind == 3 or kind == 4) FontBuild.counting(count).map(|i| { kind: 1, subtables: [single(band(i), 0xFF, 2 * pick(picks, 2 * i + 1))] }) else []
	glyphs = band(count) + 16
	gsub = FontBuild.layout("latn", [{ tag: "liga", lookups: FontBuild.counting(count) }], lookups.concat(nested))
	characters = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 0xE000, last: 0xE000 + glyphs - 1, delta: 65536 - 0xE000, glyphs: [] }]) }])
	FontBuild.glyphs_font(FontBuild.counting(glyphs).map(|g| 100 + g % 400), characters, [{ tag: "GSUB", data: gsub }])
}

## The text's glyphs: up to 24, from the first four bands or outputs.
text_glyphs : List(U8) -> List(U64)
text_glyphs = |picks|
	FontBuild.counting(picks.len().min(24)).map(
		|k| {
			b = pick(picks, 3 * k + 1)
			if (b % 5 == 0) output(b) else band(b % 4) + b.shr_zf_wrap(2) % 8
		},
	)

text_of : List(U8) -> Str
text_of = |picks| Str.from_utf8_lossy(text_glyphs(picks).join_map(utf8))

## A private-use character's UTF-8 bytes: glyph `g` is U+E000 + `g`.
utf8 : U64 -> List(U8)
utf8 = |g| {
	cp = 0xE000 + g
	[(0xE0 + cp.shr_zf_wrap(12)).to_u8_wrap(), (0x80 + cp.shr_zf_wrap(6).bitwise_and(0x3F)).to_u8_wrap(), (0x80 + cp.bitwise_and(0x3F)).to_u8_wrap()]
}

check! : List(U8), Str, List(U64) => Font
check! = |file, text, source| {
	font = match Font.from_bytes(file, Font.ReadOptions.{ strict: True }) {
		Ok(f) => f
		Err(problems) => crash "a valid substitution font was rejected: ${Str.inspect(problems)}"
	}
	n = text.to_utf8().len()
	plain = Font.shape(font, text, Font.ShapeOptions.{ features: [Font.Feature.{ tag: "liga", value: 0 }] })
	check_run!(n, plain, False)
	glyphs = plain.glyphs.map(|g| g.to_u64())
	if glyphs != source {
		crash "turning ligatures off still changed the glyphs: ${Str.inspect(glyphs)}"
	}
	run = Font.shape(font, text, Font.ShapeOptions.{})
	check_run!(n, run, False)
	if Str.inspect(run) != Str.inspect(Font.shape(font, text, Font.ShapeOptions.{})) {
		crash "shaping the same text twice gave different runs"
	}
	check_run!(n, Font.shape(font, text, Font.ShapeOptions.{ direction: RightToLeft }), True)
	plan = Font.plan(font, Font.ShapeOptions.{})
	traced = match Font.shape_traced(font, plan, text) {
		Ok(t) => t
		Err(OverBudget({ run: over_run, origins, budgets: _ })) => { run: over_run, origins }
	}
	if Str.inspect(traced.run) != Str.inspect(run) or traced.origins.len() != run.glyphs.len() {
		crash "a traced run differs from the run, or its origins are not index-aligned"
	}
	traced.origins.map2(run.glyphs, |o, g| (o, g)).for_each!(
		|(origin, glyph)| {
			fits = match origin {
				# Output glyphs in the text are mapped too; band glyphs only.
				Mapped => True
				Substituted({ feature }) => glyph < 16 and feature == "liga"
				Multiple({ feature }) => glyph < 16 and feature == "liga"
				Inserted({ feature }) => glyph < 16 and feature == "liga"
				Ligature({ feature, components }) => glyph < 16 and feature == "liga" and components >= 2
			}
			if !fits {
				crash "glyph ${glyph.to_str()} has origin ${Str.inspect(origin)}"
			}
		},
	)
	if Font.shape_checked(font, plan, text).is_err() {
		crash "a small text went over budget"
	}
	font
}

## A run's lists are index-aligned, its clusters lie inside the text and
## run in order (backwards for right-to-left), and it grew within bounds.
check_run! : U64, Font.Run, Bool => {}
check_run! = |bytes, run, rtl| {
	n = run.glyphs.len()
	if run.advances.len() != n or run.offsets.len() != n or run.clusters.len() != n or run.flags.len() != n {
		crash "a run's lists are not index-aligned"
	}
	if n > (256 * bytes).max(65536) {
		crash "shaping grew ${bytes.to_str()} bytes of text to ${n.to_str()} glyphs"
	}
	if !run.clusters.all(|c| c.to_u64() < bytes) {
		crash "a cluster lies outside the text"
	}
	var $k = 1
	while $k < n {
		a = run.clusters.get($k - 1) ?? 0
		b = run.clusters.get($k) ?? 0
		if if (rtl) a < b else a > b {
			crash "clusters are out of order"
		}
		$k = $k + 1
	}
}

target = Fuzz.target_with!({
	name: "font-gsub",
	generator: Fuzz.raw_bytes,
	test!,
	show: |bytes| Str.inspect(bytes.take_first(65)),
})
