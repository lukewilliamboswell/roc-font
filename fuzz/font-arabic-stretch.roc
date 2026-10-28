app [target] {
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import fuzz.Fuzz
import font.Font
import "../tests/fonts/shaping/arabic-fallback/presentation.ttf" as presentation : List(U8)
import "../tests/fonts/shaping/arabic-fallback/win1256.ttf" as windows : List(U8)
import "../tests/fonts/shaping/arabic-stretch/normal.ttf" as normal : List(U8)
import "../tests/fonts/shaping/arabic-stretch/small.ttf" as small_tiles : List(U8)
import "../tests/fonts/shaping/arabic-stretch/zero.ttf" as zero_tiles : List(U8)
import "../tests/fonts/shaping/arabic-extra/NotoSansSyriac[wght].ttf" as syriac : List(U8)
import "../tests/fonts/shaping/arabic-extra/NotoNastaliqUrdu[wght].ttf" as urdu : List(U8)

## Prepared fallback and stch work at two increasing sizes, seeded with
## original bounded/adversarial fonts and two unmodified real families.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = bytes.first() ?? 0
	file = match choice % 7 {
		0 => presentation
		1 => normal
		2 => small_tiles
		3 => zero_tiles
		4 => syriac
		5 => urdu
		_ => windows
	}
	font = Font.from_bytes(file, Font.ReadOptions.{}) ?? crash "valid Arabic fallback/stretch seed did not read"
	if !Font.dropped(font).is_empty() {
		crash "valid fallback/stretch seed dropped an optional table"
	}
	if choice % 7 >= 1 and choice % 7 <= 3 {
		probe = Font.shape(font, "\u(070F)ܐ", Font.ShapeOptions.{ script: "Syrc" })
		if probe.glyphs.len() < 6 or !probe.advances.drop_first(1).all(|a| a.x == 0) {
			crash "stretch target did not enter the prepared tile stage"
		}
	}
	if choice % 7 == 6 and Font.shape(font, "بلا", Font.ShapeOptions.{ script: "Arab" }).glyphs != [170, 4] {
		crash "Windows fallback target did not use its compatibility lookups"
	}

	direction = if (choice.bitwise_and(8) == 0) RightToLeft else LeftToRight
	clusters = if (choice.bitwise_and(16) == 0) Graphemes else Characters
	script = if (choice % 7 == 0 or choice % 7 >= 5) "Arab" else "Syrc"
	plan = Font.plan(font, Font.ShapeOptions.{ script, direction, clusters })
	alphabet = [0x0710, 0x0712, 0x0715, 0x072A, 0x0730, 0x070F, 0x0628, 0x0644, 0x0627, 0x064E, 0x0651, 0x200D, 0x200C, 0x034F, 0x20, 0x61]
	parts = bytes.drop_first(1).take_first(16).map(|b| alphabet.get(b.to_u64() % alphabet.len()) ?? 0x0710)
	word = if (script == "Arab") [0x0628, 0x0644].concat(parts).append(0x0627) else [0x070F, 0x0710, 0x0712].concat(parts).append(0x0715)
	small = text_of(List.repeat(word, 2).join_map(|w| w))
	large = text_of(List.repeat(word, 16).join_map(|w| w))
	a = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, small))
	b = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, large))
	if b.allocations > 10 * a.allocations + 512 {
		crash "fallback/stretch allocation growth exceeded linear input growth"
	}
	check(font, plan, small, direction == RightToLeft)
	check(font, plan, large, direction == RightToLeft)
	traced = Font.shape_traced(font, plan, large)
	match traced {
		Ok(result) => if result.run.glyphs.len() != result.origins.len() {
			crash "stretch tracing lost index alignment"
		}
		Err(OverBudget(result)) => if result.run.glyphs.len() != result.origins.len() {
			crash "budgeted stretch tracing lost index alignment"
		}
	}
	checked = Font.shape_checked(font, plan, large)
	match checked {
		Ok(run) => if run != Font.shape_planned(font, plan, large) {
			crash "checked stretch changed a successful run"
		}
		Err(OverBudget(result)) => if result.run != Font.shape_planned(font, plan, large) {
			crash "checked stretch changed a budgeted run"
		}
	}
	Fuzz.expect_no_leaks!(|{}| Font.shape_planned(font, plan, large))
	Fuzz.keep
}

text_of : List(U64) -> Str
text_of = |cps| Str.from_utf8(
	cps.join_map(
		|cp| {
			if cp < 128 {
				[cp.to_u8_wrap()]
			}
			else if cp < 2048 {
				[0xC0 + cp.shr_zf_wrap(6), 0x80 + cp.bitwise_and(63)].map(|b| b.to_u8_wrap())
			}
			else {
				[0xE0 + cp.shr_zf_wrap(12), 0x80 + cp.shr_zf_wrap(6).bitwise_and(63), 0x80 + cp.bitwise_and(63)].map(|b| b.to_u8_wrap())
			}
		},
	),
) ?? ""

check : Font, Font.ShapePlan, Str, Bool -> {}
check = |font, plan, text, backward| {
	run = Font.shape_planned(font, plan, text)
	again = Font.shape_planned(font, plan, text)
	if run.glyphs != again.glyphs or run.advances != again.advances or run.offsets != again.offsets or run.clusters != again.clusters or run.flags != again.flags {
		crash "Arabic shaping is not deterministic"
	}
	n = run.glyphs.len()
	if n != run.advances.len() or n != run.offsets.len() or n != run.clusters.len() or n != run.flags.len() {
		crash "Arabic shaping lost index alignment"
	}
	if n > (256 * text.to_utf8().len()).max(65536) {
		crash "Arabic shaping exceeded its growth budget"
	}
	for i in 0..<n {
		cluster = run.clusters.get(i) ?? 0
		if cluster >= text.to_utf8().len() {
			crash "Arabic shaping produced a cluster outside the text"
		}
		if i > 0 {
			previous = run.clusters.get(i - 1) ?? 0
			if if (backward) previous < cluster else previous > cluster {
				crash "Arabic clusters lost monotonicity"
			}
		}
	}
	{}
}

target = Fuzz.target_with!({ name: "font-arabic-stretch", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(17)) })
