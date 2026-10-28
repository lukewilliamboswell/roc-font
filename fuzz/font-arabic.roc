app [target] {
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import fuzz.Fuzz
import font.Font
import "../tests/fonts/shaping/arabic/NotoNaskhArabic-Regular.ttf" as naskh : List(U8)
import "../tests/fonts/shaping/arabic/NotoSansArabic-Regular.ttf" as sans : List(U8)

## Joining forms, transparent marks, join controls and script-stage ordering
## in two real fonts. Two increasing text sizes isolate shaping work from
## font preparation and assert allocation growth no worse than linear.
## The whole-font malformed-input targets separately exercise these fonts.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = bytes.first() ?? 0
	file = if (choice.bitwise_and(1) == 0) naskh else sans
	font = match Font.from_bytes(file, Font.ReadOptions.{}) {
		Ok(value) => value
		Err(_) => crash "real Arabic seed font did not read"
	}
	direction = if (choice.bitwise_and(2) == 0) RightToLeft else LeftToRight
	clusters = if (choice.bitwise_and(4) == 0) Graphemes else Characters
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Arab", language: "ar", direction, clusters })
	alphabet = [0x0627, 0x0628, 0x062A, 0x062F, 0x0631, 0x0633, 0x0644, 0x0645, 0x0646, 0x0647, 0x0648, 0x064A, 0x064B, 0x064E, 0x0650, 0x0651, 0x0654, 0x0655, 0x200C, 0x200D, 0x034F, 0x20, 0x31]
	parts = bytes.drop_first(1).take_first(16).map(|b| alphabet.get(b.to_u64() % alphabet.len()) ?? 0x0628)
	word = [0x0628].concat(parts).append(0x0644)
	small = text_of(List.repeat(word, 2).join_map(|w| w))
	large = text_of(List.repeat(word, 16).join_map(|w| w))
	a = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, small))
	b = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, large))
	if b.allocations > 10 * a.allocations + 256 {
		crash "Arabic shaping allocation growth exceeded the input growth"
	}
	check(font, plan, small, direction == RightToLeft)
	check(font, plan, large, direction == RightToLeft)
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

target = Fuzz.target_with!({ name: "font-arabic", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(17)) })
