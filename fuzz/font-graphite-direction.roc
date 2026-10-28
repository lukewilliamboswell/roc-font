app [target] {
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import font.Font
import fuzz.Fuzz
import "../tests/fonts/graphite/nsm/nsm-1-16-1-32.ttf" as native_ltr : List(U8)
import "../tests/fonts/graphite/nsm/nsm-2-16-1-32.ttf" as native_rtl : List(U8)
import "../tests/fonts/graphite/nsm-noop/noop-0.ttf" as identity : List(U8)
import "../tests/fonts/graphite/nsm-noop/noop-32.ttf" as reverse_identity : List(U8)

# These original programs change glyphs or copy input, preserving its length.
# Reference positioning disagreements are tested separately in the oracle gate.
test! = |bytes| {
	choice = bytes.first() ?? 0
	files = [native_ltr, native_rtl, identity, reverse_identity]
	font = Font.from_bytes(files.get(choice.to_u64() % 4) ?? native_ltr, Font.ReadOptions.{}) ?? crash "direction fixture rejected"
	plan = Font.plan(
		font,
		Font.ShapeOptions.{
			script: if (choice.bitwise_and(64) == 0) "Latn" else "Arab",
			direction: match choice.bitwise_and(12) {
				0 => LeftToRight
				4 => RightToLeft
				8 => TopToBottom
				_ => BottomToTop
			},
			clusters: if (choice.bitwise_and(16) == 0) Graphemes else Characters,
		},
	)
	if Font.shaping_engine(plan) != Graphite {
		crash "direction target selected a different engine"
	}
	empty = Font.shape_checked(font, plan, "") ?? crash "empty direction run failed"
	if !empty.glyphs.is_empty() or !empty.advances.is_empty() or !empty.offsets.is_empty() or !empty.clusters.is_empty() or !empty.flags.is_empty() {
		crash "empty direction run retained columns"
	}
	word = Str.join_with(bytes.drop_first(1).take_first(8).map(|b| if (b.bitwise_and(1) == 0) "a" else "b"), "")
	unit = "b".concat(word)
	var $previous = 0
	for copies in [1.U64, 4, 16] {
		text = Str.join_with(List.repeat(unit, copies), "")
		measured = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, text))
		if $previous != 0 and measured.allocations > 4 * $previous + 128 {
			crash "direction allocations grew faster than input"
		}
		$previous = measured.allocations
		checked = Font.shape_checked(font, plan, text)
		if checked != Font.shape_checked(font, plan, text) {
			crash "direction shaping is not deterministic"
		}
		run = checked ?? crash "bounded direction fixture failed"
		if run != measured.value {
			crash "checked and unchecked direction runs differ"
		}
		n = text.to_utf8().len()
		if run.glyphs.len() != n or run.advances.len() != n or run.offsets.len() != n or run.clusters.len() != n or run.flags.len() != n {
			crash "direction lost slots or column alignment"
		}
		for cluster in run.clusters {
			if cluster >= n {
				crash "direction cluster escaped original text"
			}
		}
		Fuzz.expect_no_leaks!(|{}| Font.shape_planned(font, plan, text))
	}
	Fuzz.keep
}

target = Fuzz.target_with!({ name: "font-graphite-direction", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(9)) })
