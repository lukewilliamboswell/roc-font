app [target] {
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import font.Font
import fuzz.Fuzz
import "../tests/fonts/graphite/Charis5_eursub.ttf" as charis : List(U8)
import "../tests/fonts/graphite/Padauk.ttf" as padauk : List(U8)
import "../tests/fonts/graphite/Scheherazadegr.ttf" as scheherazade : List(U8)
import "../tests/fonts/graphite/AwamiNastaliq-Regular.ttf" as awami : List(U8)
import "../tests/fonts/graphite/divide-feature.ttf" as abort_font : List(U8)
import "../tests/fonts/graphite/stack-1024.ttf" as stack_font : List(U8)

test! = |bytes| {
	choice = bytes.first() ?? 0
	files = [charis, padauk, scheherazade, awami, abort_font, stack_font]
	which = choice.to_u64() % files.len()
	font = Font.from_bytes(files.get(which) ?? charis, Font.ReadOptions.{}) ?? crash "Graphite seed font rejected"
	script = if (which == 1) "Mymr" else if (which == 2 or which == 3) "Arab" else "Latn"
	plan = Font.plan(
		font,
		Font.ShapeOptions.{
			script,
			direction: match choice.bitwise_and(24) {
				0 => LeftToRight
				8 => RightToLeft
				16 => TopToBottom
				_ => BottomToTop
			},
			clusters: if (choice.bitwise_and(32) == 0) Graphemes else Characters,
			graphite_features: [Font.GraphiteFeature.{ id: 100, value: if (choice.bitwise_and(64) == 0) 0 else 1 }],
		},
	)
	if Font.shaping_engine(plan) != Graphite {
		crash "Graphite fuzz consumer selected another backend"
	}
	alphabet = if (which == 1) ["က", "င်္", "ေ", "ြ", "့", "‍", "‌", "͏", " "] else if (which == 2 or which == 3) ["ب", "ت", "ل", "م", "ا", "َ", "ّ", "‍", "‌", "͏", " "] else ["a", "b", "f", "i", "́", "̣", "‍", "‌", "͏", "😀", " "]
	word = Str.join_with(bytes.drop_first(1).take_first(12).map(|b| alphabet.get(b.to_u64() % alphabet.len()) ?? "a"), "")
	small = "a".concat(word)
	large = Str.join_with(List.repeat(small, 8), "")
	a = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, small))
	b = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, large))
	if b.allocations > 12 * a.allocations + 256 {
		crash "Graphite allocations grew faster than the shaped input"
	}
	check(font, plan, small)
	check(font, plan, large)
	Fuzz.expect_no_leaks!(|{}| Font.shape_planned(font, plan, large))
	Fuzz.keep
}

check : Font, Font.ShapePlan, Str -> {}
check = |font, plan, text| {
	checked = Font.shape_checked(font, plan, text)
	if checked != Font.shape_checked(font, plan, text) {
		crash "Graphite shaping is not deterministic"
	}
	run = match checked {
		Ok(run) => run
		Err(OverBudget(result)) => result.run
		Err(ProgramAborted(result)) => {
			if !result.run.glyphs.is_empty() {
				crash "Graphite program abort retained output"
			}
			result.run
		}
	}
	n = run.glyphs.len()
	if n != run.advances.len() or n != run.offsets.len() or n != run.clusters.len() or n != run.flags.len() {
		crash "Graphite run columns lost index alignment"
	}
	if n > (256 * text.to_utf8().len()).max(65536) {
		crash "Graphite output exceeded its growth bound"
	}
	for cluster in run.clusters {
		if cluster >= text.to_utf8().len() {
			crash "Graphite association escaped the input text"
		}
	}
}

target = Fuzz.target_with!({ name: "font-graphite", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(13)) })
