app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import fuzz.Fuzz
import font.Font
import build.FontBuild

## Pair kerning, one table format at a time. The first input byte picks the
## format (`GPOS` pair adjustment by glyph pairs, format 1; by classes,
## format 2; or a TrueType `kern` table, by its value modulo 3) and, for
## classes, how many there are (bits 2 to 5). Every further byte chooses the
## pairs of one first glyph: which second glyphs follow it and the values.
## The same choices build a font at two sizes, with 2 and 16 copies of the
## first glyphs; every pair of the smaller font is kerned the same in the
## larger. The text uses glyphs of the smaller font.
##
## Contract: both fonts read; the glyphs are the text's; the width (the sum
## of the advances) is the sum of the glyphs' advances plus the kerning of
## every adjacent pair the recipe kerns; both fonts give the same run, and
## shaping twice gives the same run; runs are index-aligned with clusters
## in range and in order. Reading the larger font takes at most `10 × small
## + 256` allocations (linear), shaping the same text with a plan costs no
## more allocations in the larger font (constant per call), and nothing
## leaks.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = bytes.first() ?? 0
	picks = bytes.drop_first(1).take_first(32)
	small = recipe(choice, picks, 2)
	large = recipe(choice, picks, 16)
	glyphs = text_glyphs(small, picks)
	text = Str.from_utf8_lossy(glyphs.join_map(utf8))
	small_font = check!(small, text, glyphs)
	large_font = check!(large, text, glyphs)
	small_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(small.file, Font.ReadOptions.{}))
	large_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(large.file, Font.ReadOptions.{}))
	Fuzz.expect_no_leaks!(|{}| Font.from_bytes(large.file, Font.ReadOptions.{}))
	if large_read.allocations > 10 * small_read.allocations + 256 {
		crash "reading 8 times the kerning pairs took ${large_read.allocations.to_str()} allocations, against ${small_read.allocations.to_str()}"
	}
	small_plan = Font.plan(small_font, Font.ShapeOptions.{})
	large_plan = Font.plan(large_font, Font.ShapeOptions.{})
	small_shape = Fuzz.measure_allocs!(|{}| Font.shape_planned(small_font, small_plan, text))
	large_shape = Fuzz.measure_allocs!(|{}| Font.shape_planned(large_font, large_plan, text))
	Fuzz.expect_no_leaks!(|{}| Font.shape_planned(large_font, large_plan, text))
	if large_shape.allocations > small_shape.allocations + 8 {
		crash "kerning one text with 8 times the pairs took ${large_shape.allocations.to_str()} allocations, against ${small_shape.allocations.to_str()}"
	}
	if Str.inspect(small_shape.value) != Str.inspect(large_shape.value) {
		crash "pairs the text does not use changed its run"
	}
	Fuzz.keep
}

## A font a recipe builds and its kerning: per first glyph (ascending),
## its second glyphs (ascending) and values; or, by classes, the first
## glyphs' classes, every glyph's second class, and the class values.
Built : { file : List(U8), glyphs : U64, format : U64, firsts : List(U64), seconds : List(List({ second : U64, value : I64 })), width : U64, values : List(I64), choice : U64 }

pick : List(U8), U64 -> U64
pick = |bytes, i| if (bytes.is_empty()) 0 else (bytes.get(i % bytes.len()) ?? 0).to_u64()

## Second glyphs follow from 1 to 20, so the smaller font has them all.
second_class : U64, U64, U64 -> U64
second_class = |choice, width, g| (5 * g + choice) % width

first_class : U64, U64 -> U64
first_class = |height, j| 1 + j % (height - 1)

recipe : U8, List(U8), U64 -> Built
recipe = |choice, picks, copies| {
	format = choice.to_u64() % 3
	count = picks.len().max(1) * copies
	glyphs = 2 * count + 24
	firsts = FontBuild.counting(count).map(|j| 2 + 2 * j)
	seconds = FontBuild.counting(count).map(
		|j| {
			b = pick(picks, j)
			var $out = []
			for s in 1..=20 {
				# Each first glyph kerns a handful of seconds.
				if (b * 7 + s * 13 + j) % 5 == 0 {
					$out = $out.append({ second: s, value: (b + s).to_i64_wrap() % 97 - 48 })
				}
			}
			$out
		},
	)
	height = 2 + choice.shr_zf_wrap(2).to_u64() % 3
	width = 1 + choice.shr_zf_wrap(4).to_u64() % 4
	values = FontBuild.counting(height * width).map(|k| pick(picks, k + 1).to_i64_wrap() - 128)
	table =
		match format {
			0 => { tag: "GPOS", data: FontBuild.layout("latn", [{ tag: "kern", lookups: [0] }], [{ kind: 2, subtables: [FontBuild.pair1(4, 0, FontBuild.counting(count).map(|j| { glyph: 2 + 2 * j, pairs: (seconds.get(j) ?? []).map(|p| { second: p.second, values: [p.value] }) }))] }]) }
			1 => {
				class1 = FontBuild.classes2(firsts.map_with_index(|f, j| { first: f, last: f, class: first_class(height, j) }))
				class2 = FontBuild.classes1(1, FontBuild.counting(glyphs - 1).map(|k| second_class(choice.to_u64(), width, k + 1)))
				{ tag: "GPOS", data: FontBuild.layout("latn", [{ tag: "kern", lookups: [0] }], [{ kind: 2, subtables: [FontBuild.pair2(4, 0, FontBuild.coverage1(firsts), class1, class2, height, width, values)] }]) }
			}
			_ => { tag: "kern", data: FontBuild.kern_searchable(FontBuild.counting(count).join_map(|j| (seconds.get(j) ?? []).map(|p| { left: 2 + 2 * j, right: p.second, value: p.value }))) }
		}
	characters = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 0xE000, last: 0xE000 + glyphs - 1, delta: 65536 - 0xE000, glyphs: [] }]) }])
	file = FontBuild.glyphs_font(FontBuild.counting(glyphs).map(|g| 100 + g % 400), characters, [table])
	{ file, glyphs, format, firsts, seconds, width, values, choice: choice.to_u64() }
}

## The kerning the recipe gives a pair.
kerning : Built, U64, U64 -> I64
kerning = |built, left, right|
	if left < 2 or left % 2 != 0 or (left - 2) // 2 >= built.firsts.len() {
		0
	} else {
		j = (left - 2) // 2
		if built.format == 1 {
			height = 2 + built.choice.shr_zf_wrap(2) % 3
			# Glyph 0 is in no class definition: class 0.
			class2 = if (right == 0) 0 else second_class(built.choice, built.width, right)
			built.values.get(first_class(height, j) * built.width + class2) ?? 0
		} else {
			((built.seconds.get(j) ?? []).keep_if(|p| p.second == right).first() ?? { second: right, value: 0 }).value
		}
	}

## Up to 24 glyphs of the smaller font: kerned first glyphs, seconds, or
## glyphs that are never first (glyph 0 and odd glyphs).
text_glyphs : Built, List(U8) -> List(U64)
text_glyphs = |built, picks|
	FontBuild.counting(picks.len().min(24)).map(
		|k| {
			b = pick(picks, 2 * k + 1)
			match b % 3 {
				0 => built.firsts.get(b % built.firsts.len().max(1)) ?? 2
				# Odd: even seconds are first glyphs of the larger font.
				1 => 1 + 2 * (b % 10)
				# Odd glyphs are never first glyphs, in either font.
				_ => if (b % 7 == 0) 0 else 1 + 2 * (b % 12)
			}
		},
	)

## A private-use character's UTF-8 bytes: glyph `g` is U+E000 + `g`.
utf8 : U64 -> List(U8)
utf8 = |g| {
	cp = 0xE000 + g
	[(0xE0 + cp.shr_zf_wrap(12)).to_u8_wrap(), (0x80 + cp.shr_zf_wrap(6).bitwise_and(0x3F)).to_u8_wrap(), (0x80 + cp.bitwise_and(0x3F)).to_u8_wrap()]
}

check! : Built, Str, List(U64) => Font
check! = |built, text, glyphs| {
	font = match Font.from_bytes(built.file, Font.ReadOptions.{ strict: True }) {
		Ok(f) => f
		Err(problems) => crash "a valid kerning font was rejected: ${Str.inspect(problems)}"
	}
	n = text.to_utf8().len()
	run = Font.shape(font, text, Font.ShapeOptions.{})
	check_run!(n, run, False)
	# Glyph 0 (U+E000) is the missing glyph; the font maps it all the same.
	if run.glyphs.map(|g| g.to_u64()) != glyphs {
		crash "kerning changed the glyphs"
	}
	var $want = 0
	for k in 0..<glyphs.len() {
		g = glyphs.get(k) ?? 0
		$want = $want + 100 + (g % 400).to_i64_wrap()
		if k + 1 < glyphs.len() {
			$want = $want + kerning(built, g, glyphs.get(k + 1) ?? 0)
		}
	}
	got = run.advances.fold(0, |sum, a| sum + a.x.to_i64())
	if got != $want {
		crash "the kerned width is ${got.to_str()}, but the pairs give ${$want.to_str()}"
	}
	if Font.width(font, text).to_i64() != got {
		crash "the width is not the sum of the advances"
	}
	if Str.inspect(run) != Str.inspect(Font.shape(font, text, Font.ShapeOptions.{})) {
		crash "shaping the same text twice gave different runs"
	}
	check_run!(n, Font.shape(font, text, Font.ShapeOptions.{ direction: RightToLeft }), True)
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
	name: "font-gpos",
	generator: Fuzz.raw_bytes,
	test!,
	show: |bytes| Str.inspect(bytes.take_first(33)),
})
