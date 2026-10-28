app [target] {
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import fuzz.Fuzz
import font.Font
import "../tests/fonts/complex/ComplexDevaSans.ttf" as sans_bytes : List(U8)
import "../tests/fonts/complex/ComplexDevaSerif.ttf" as serif_bytes : List(U8)

# Narrow Indic model target: real fonts, syllables, reph, matras, broken
# clusters and join controls. Arbitrary bytes choose shaping categories;
# selector0 also treats the remainder as literal UTF-8 real-font seeds.
# Growth, index alignment, monotone original clusters and complete flags
# are checked on both requested directions, with feature masks and tight
# work limits. The same target measures isolated Indic scaling at2sizes.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	selector = bytes.first() ?? 0
	font = if selector % 2 == 0 {
		sans
	} else {
		serif
	}
	parts = ["क", "ख", "ग", "न", "त", "य", "र", "ष", "़", "्", "ि", "ी", "ु", "ू", "े", "ै", "ो", "ौ", "ं", "ँ", "ः", "‌", "‍", " ", "◌", "᳐", "ऱ"]
	text = if selector == 0 {
		Str.from_utf8_lossy(bytes.drop_first(1))
	}
	else {
		Str.join_with(bytes.drop_first(1).take_first(512).map(|b| parts.get(b.to_u64() % parts.len()) ?? ""), "")
	}
	for rtl in [False, True] {
		direction = if rtl {
			RightToLeft
		} else {
			LeftToRight
		}
		features = if selector.bitwise_and(4) == 0 {
			[]
		} else {
			[Font.Feature.{ tag: "half", value: 0 }, Font.Feature.{ tag: "rphf", value: 0 }]
		}
		options = Font.ShapeOptions.{ script: "Deva", language: "hi", direction, features }
		plan = Font.plan(font, options)
		run = Font.shape_planned(font, plan, text)
		check_run!(text.to_utf8().len(), run, rtl)
		if Str.inspect(run) != Str.inspect(Font.shape(font, text, options)) or Str.inspect(run) != Str.inspect(Font.shape_planned(font, plan, text)) {
			crash "Indic shaping is not deterministic or direct/planned disagree"
		}
		checked = Font.shape_checked(font, plan, text)
		match checked {
			Ok(value) => if Str.inspect(run) != Str.inspect(value) {
				crash "Indic checked result differs"
			}
			Err(OverBudget(value)) => if value.budgets.is_empty() or Str.inspect(run) != Str.inspect(value.run) {
				crash "Indic budget result differs or omits reason"
			}
		}
		traced = match Font.shape_traced(font, plan, text) {
			Ok(value) => { run: value.run, origins: value.origins }
			Err(OverBudget(value)) => { run: value.run, origins: value.origins }
		}
		if Str.inspect(traced.run) != Str.inspect(run) or traced.origins.len() != run.glyphs.len() {
			crash "Indic trace is not aligned"
		}
		limited_plan = Font.plan(font, Font.ShapeOptions.{ script: "Deva", direction, limits: Font.ShapeLimits.{ operations: 0, growth: 0 } })
		limited = Font.shape_checked(font, limited_plan, text)
		if Str.inspect(limited) != Str.inspect(Font.shape_checked(font, limited_plan, text)) {
			crash "Indic limited shaping is not deterministic"
		}
		limited_run = match limited {
			Ok(value) => value
			Err(OverBudget(value)) => value.run
		}
		check_run!(text.to_utf8().len(), limited_run, rtl)
	}
	# Equal-position marks and long consonant/halant syllables are the
	# adversarial sort/reorder inputs, separate from ordinary short words.
	for piece in ["र्कि क्षिं हिन्दी ", "क्", "ि"] {
		plan = Font.plan(font, Font.ShapeOptions.{ script: "Deva" })
		small = Str.join_with(List.repeat(piece, 16), "")
		large = Str.join_with(List.repeat(piece, 128), "")
		small_cost = Fuzz.measure_allocs!(|{}| checksum(Font.shape_planned(font, plan, small)))
		large_cost = Fuzz.measure_allocs!(|{}| checksum(Font.shape_planned(font, plan, large)))
		Fuzz.expect_no_leaks!(|{}| checksum(Font.shape_planned(font, plan, large)))
		if large_cost.allocations > 10 * small_cost.allocations + 256 {
			crash "Indic allocations grow faster than text"
		}
	}
	Fuzz.keep
}

sans : Font
sans = match Font.from_bytes(sans_bytes, Font.ReadOptions.{}) {
	Ok(font) => font
	Err(problems) => crash Str.inspect(problems)
}

serif : Font
serif = match Font.from_bytes(serif_bytes, Font.ReadOptions.{}) {
	Ok(font) => font
	Err(problems) => crash Str.inspect(problems)
}

checksum : Font.Run -> U64
checksum = |run| run.glyphs.fold(0, |sum, glyph| sum.plus_wrap(glyph.to_u64()))

check_run! : U64, Font.Run, Bool => {}
check_run! = |bytes, run, rtl| {
	n = run.glyphs.len()
	if run.advances.len() != n or run.offsets.len() != n or run.clusters.len() != n or run.flags.len() != n {
		crash "Indic lists are not aligned"
	}
	if n > (64 * bytes).max(16384) {
		crash "Indic output exceeds growth limit"
	}
	if !run.clusters.all(|cluster| cluster < bytes) {
		crash "Indic cluster escaped original text"
	}
	var $i = 1
	while $i < n {
		a = run.clusters.get($i - 1) ?? 0
		b = run.clusters.get($i) ?? 0
		if if rtl {
			a < b
		} else {
			a > b
		} {
			crash "Indic clusters are not monotone"
		}
		$i = $i + 1
	}
	if !run.flags.all(|flag| flag <= 3) {
		crash "Indic flags contain private metadata"
	}
}

target = Fuzz.target_with!({ name: "font-indic", generator: Fuzz.raw_bytes, test!, show: Str.inspect })
