app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import fuzz.Fuzz
import font.Font
import build.FontBuild

## Coverage tables and class definitions, through the two lookups that
## lean on them hardest: a single substitution (`liga`) over a coverage
## table, and pair kerning by class (`GPOS` pair adjustment format 2,
## `kern`) over the same coverage and two class definitions. The first
## input byte picks the formats: bit 0 the coverage format (1 or 2), bit 1
## the substitution format (a delta or a list), bits 2 and 3 the formats of
## the first and second class definitions, and bits 4 and 5 how many
## classes they use. Every further byte chooses a run of covered glyphs
## (its distance from the last run and its length), the kerning values and
## the text. The same choices build a font at two sizes, 2 and 16 copies of
## the runs; the text uses glyphs both fonts have.
##
## Contract: both fonts read; with kerning off, the glyphs are the text's
## glyphs with exactly the covered ones substituted as the recipe says;
## with ligatures off, the glyphs are the text's and the width is the sum
## of the advances plus the class kerning of every adjacent pair whose
## first glyph is covered; runs are index-aligned with clusters in range
## and in order, and deterministic. Reading the larger font takes at most
## `10 × small + 256` allocations (linear), shaping the same text with a
## plan costs no more allocations in the larger font (constant per call),
## and nothing leaks.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = bytes.first() ?? 0
	picks = bytes.drop_first(1).take_first(32)
	small = recipe(choice, picks, 2)
	large = recipe(choice, picks, 16)
	text = text_of(small, picks)
	small_font = check!(small, text)
	large_font = check!(large, text)
	small_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(small.file, Font.ReadOptions.{}))
	large_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(large.file, Font.ReadOptions.{}))
	Fuzz.expect_no_leaks!(|{}| Font.from_bytes(large.file, Font.ReadOptions.{}))
	if large_read.allocations > 10 * small_read.allocations + 256 {
		crash "reading coverage 8 times larger took ${large_read.allocations.to_str()} allocations, against ${small_read.allocations.to_str()}"
	}
	small_plan = Font.plan(small_font, Font.ShapeOptions.{})
	large_plan = Font.plan(large_font, Font.ShapeOptions.{})
	small_shape = Fuzz.measure_allocs!(|{}| Font.shape_planned(small_font, small_plan, text))
	large_shape = Fuzz.measure_allocs!(|{}| Font.shape_planned(large_font, large_plan, text))
	Fuzz.expect_no_leaks!(|{}| Font.shape_planned(large_font, large_plan, text))
	if large_shape.allocations > small_shape.allocations + 8 {
		crash "shaping one text with coverage 8 times larger took ${large_shape.allocations.to_str()} allocations, against ${small_shape.allocations.to_str()}"
	}
	Fuzz.keep
}

## The font a recipe builds and what it means: the covered glyphs (in
## coverage order) with their substitutes, the class of each covered glyph
## (first) and of each glyph that may follow (second), and the kerning
## value of every pair of classes, row by row.
Built : { file : List(U8), glyphs : U64, covered : List(U64), substitutes : List(U64), first : List({ glyph : U64, class : U64 }), second : List({ glyph : U64, class : U64 }), height : U64, width : U64, values : List(I64) }

pick : List(U8), U64 -> U64
pick = |bytes, i| if (bytes.is_empty()) 0 else (bytes.get(i % bytes.len()) ?? 0).to_u64()

## Runs of glyphs from 1: distance from the last run, length.
runs_of : List(U8), U64, U64 -> List({ first : U64, last : U64 })
runs_of = |picks, copies, salt| {
	var $out = []
	var $next = 1
	for j in 0..<(picks.len().max(1) * copies) {
		b = pick(picks, j + salt)
		first = $next + b % 3
		last = first + b.shr_zf_wrap(2) % 6
		$out = $out.append({ first, last })
		$next = last + 1
	}
	$out
}

recipe : U8, List(U8), U64 -> Built
recipe = |choice, picks, copies| {
	runs = runs_of(picks, copies, 0)
	seconds = runs_of(picks, copies, 5)
	covered = runs.join_map(|r| FontBuild.counting(r.last - r.first + 1).map(|t| r.first + t))
	top = (covered.last() ?? 0).max((seconds.last() ?? { first: 0, last: 0 }).last)
	glyphs = top + 32
	delta = 1 + pick(picks, 1) % 7
	substitutes = if (choice.bitwise_and(2) == 0) covered.map(|g| g + delta) else covered.map_with_index(|_, i| 1 + (37 * i + pick(picks, i)) % (glyphs - 1))
	coverage = if (choice.bitwise_and(1) == 0) FontBuild.coverage1(covered) else FontBuild.coverage2(coverage_ranges(runs))
	single = if (choice.bitwise_and(2) == 0) FontBuild.single1_over(coverage, delta.to_i64_wrap()) else FontBuild.single2_over(coverage, substitutes)
	height = 2 + choice.shr_zf_wrap(4).bitwise_and(1).to_u64()
	width = 2 + choice.shr_zf_wrap(5).bitwise_and(1).to_u64()
	first = expand(runs, |i| i % height)
	second = expand(seconds, |i| (i + 1) % width)
	values = FontBuild.counting(height * width).map(|k| pick(picks, 3 + k).to_i64_wrap() - 128)
	class1 = classes(choice.bitwise_and(4) != 0, first)
	class2 = classes(choice.bitwise_and(8) != 0, second)
	pairs = FontBuild.pair2(4, 0, coverage, class1, class2, height, width, values)
	gsub = FontBuild.layout("latn", [{ tag: "liga", lookups: [0] }], [{ kind: 1, subtables: [single] }])
	gpos = FontBuild.layout("latn", [{ tag: "kern", lookups: [0] }], [{ kind: 2, subtables: [pairs] }])
	characters = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 0xE000, last: 0xE000 + glyphs - 1, glyph: 0 }]) }])
	file = FontBuild.glyphs_font(advances(glyphs), characters, [{ tag: "GSUB", data: gsub }, { tag: "GPOS", data: gpos }])
	{ file, glyphs, covered, substitutes, first, second, height, width, values }
}

advances : U64 -> List(U64)
advances = |glyphs| FontBuild.counting(glyphs).map(|g| 100 + g % 400)

## Every glyph of the runs, each run with the class `class_at` gives its
## index.
expand : List({ first : U64, last : U64 }), (U64 -> U64) -> List({ glyph : U64, class : U64 })
expand = |runs, class_at| {
	var $out = []
	for i in 0..<runs.len() {
		r = runs.get(i) ?? { first: 0, last: 0 }
		for g in r.first..=r.last {
			$out = $out.append({ glyph: g, class: class_at(i) })
		}
	}
	$out
}

coverage_ranges : List({ first : U64, last : U64 }) -> List({ first : U64, last : U64, index : U64 })
coverage_ranges = |runs| {
	var $out = []
	var $index = 0
	for r in runs {
		$out = $out.append({ first: r.first, last: r.last, index: $index })
		$index = $index + r.last - r.first + 1
	}
	$out
}

## A class definition of format 1 (an array from the first glyph, class 0
## between) or format 2 (one range per glyph run of a class).
classes : Bool, List({ glyph : U64, class : U64 }) -> List(U8)
classes = |ranges, members|
	if ranges {
		FontBuild.classes2(members.keep_if(|m| m.class != 0).map(|m| { first: m.glyph, last: m.glyph, class: m.class }))
	} else {
		start = (members.first() ?? { glyph: 0, class: 0 }).glyph
		end = (members.last() ?? { glyph: 0, class: 0 }).glyph
		var $array = List.repeat(0, if (members.is_empty()) 0 else end - start + 1)
		for m in members {
			$array = $array.set(m.glyph - start, m.class) ?? []
		}
		FontBuild.classes1(start, $array)
	}

class_of : List({ glyph : U64, class : U64 }), U64 -> U64
class_of = |members, glyph| (members.keep_if(|m| m.glyph == glyph).first() ?? { glyph, class: 0 }).class

## The text: up to 24 glyphs of the smaller font (covered, following, or
## neither), as private-use characters.
text_of : Built, List(U8) -> Str
text_of = |built, picks| {
	n = picks.len().min(24)
	glyphs = FontBuild.counting(n).map(
		|k| {
			b = pick(picks, 2 * k + 1)
			match b % 3 {
				0 => built.covered.get(b % built.covered.len().max(1)) ?? 1
				1 => (built.second.get(b % built.second.len().max(1)) ?? { glyph: 1, class: 0 }).glyph
				_ => 1 + b % (built.glyphs - 1)
			}
		},
	)
	Str.from_utf8_lossy(glyphs.join_map(|g| utf8(0xE000 + g)))
}

utf8 : U64 -> List(U8)
utf8 = |cp|
	if cp < 0x10000 {
		[(0xE0 + cp.shr_zf_wrap(12)).to_u8_wrap(), (0x80 + cp.shr_zf_wrap(6).bitwise_and(0x3F)).to_u8_wrap(), (0x80 + cp.bitwise_and(0x3F)).to_u8_wrap()]
	} else {
		[(0xF0 + cp.shr_zf_wrap(18)).to_u8_wrap(), (0x80 + cp.shr_zf_wrap(12).bitwise_and(0x3F)).to_u8_wrap(), (0x80 + cp.shr_zf_wrap(6).bitwise_and(0x3F)).to_u8_wrap(), (0x80 + cp.bitwise_and(0x3F)).to_u8_wrap()]
	}

## The glyphs of the text before shaping: each character is one
## three-byte private-use character.
mapped : Str -> List(U32)
mapped = |text| {
	bytes = text.to_utf8()
	FontBuild.counting(bytes.len() // 3).map(
		|k| {
			at = 3 * k
			cp = (bytes.get(at) ?? 0).to_u64().bitwise_and(0x0F).shl_wrap(12) + (bytes.get(at + 1) ?? 0).to_u64().bitwise_and(0x3F).shl_wrap(6) + (bytes.get(at + 2) ?? 0).to_u64().bitwise_and(0x3F)
			(cp - 0xE000).to_u32_wrap()
		},
	)
}

check! : Built, Str => Font
check! = |built, text| {
	font = match Font.from_bytes(built.file, Font.ReadOptions.{ strict: True }) {
		Ok(f) => f
		Err(problems) => crash "a valid coverage font was rejected: ${Str.inspect(problems)}"
	}
	source = mapped(text)
	n = text.to_utf8().len()
	# Substitution alone.
	substituted = Font.shape(font, text, Font.ShapeOptions.{ features: [Font.Feature.{ tag: "kern", value: 0 }] })
	check_run!(n, substituted)
	want = source.map(
		|g| {
			var $s = g.to_u64()
			for i in 0..<built.covered.len() {
				if (built.covered.get(i) ?? 0) == g.to_u64() {
					$s = built.substitutes.get(i) ?? 0
				}
			}
			$s.to_u32_wrap()
		},
	)
	if substituted.glyphs != want {
		crash "single substitution gave ${Str.inspect(substituted.glyphs)}, but the coverage gives ${Str.inspect(want)}"
	}
	# Kerning alone.
	kerned = Font.shape(font, text, Font.ShapeOptions.{ features: [Font.Feature.{ tag: "liga", value: 0 }] })
	check_run!(n, kerned)
	if kerned.glyphs != source {
		crash "turning ligatures off still changed the glyphs"
	}
	var $width = 0
	for k in 0..<source.len() {
		g = (source.get(k) ?? 0).to_u64()
		$width = $width + 100 + (g % 400).to_i64_wrap()
		if k + 1 < source.len() and built.covered.contains(g) {
			next = (source.get(k + 1) ?? 0).to_u64()
			$width = $width + (built.values.get(class_of(built.first, g) * built.width + class_of(built.second, next)) ?? 0)
		}
	}
	got = kerned.advances.fold(0, |sum, a| sum + a.x.to_i64())
	if got != $width {
		crash "class kerning gave a width of ${got.to_str()}, but the classes give ${$width.to_str()}"
	}
	if Str.inspect(kerned) != Str.inspect(Font.shape(font, text, Font.ShapeOptions.{ features: [Font.Feature.{ tag: "liga", value: 0 }] })) {
		crash "shaping the same text twice gave different runs"
	}
	check_run!(n, Font.shape(font, text, Font.ShapeOptions.{ direction: RightToLeft }))
	font
}

## A run's lists are index-aligned and its clusters lie inside the text, in
## order (for either direction, the glyphs are in visual order).
check_run! : U64, Font.Run => {}
check_run! = |bytes, run| {
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
}

target = Fuzz.target_with!({
	name: "font-coverage",
	generator: Fuzz.raw_bytes,
	test!,
	show: |bytes| Str.inspect(bytes.take_first(33)),
})
