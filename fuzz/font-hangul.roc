app [target] {
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import fuzz.Fuzz
import font.Font
import "../tests/fonts/shaping/hangul/NanumGothic-Regular.ttf" as gothic : List(U8)
import "../tests/fonts/shaping/hangul/NanumMyeongjo-Regular.ttf" as myeongjo : List(U8)
import "../tests/fonts/shaping/hangul-fixtures/all.ttf" as all_file : List(U8)
import "../tests/fonts/shaping/hangul-fixtures/decomposed.ttf" as decomposed : List(U8)
import "../tests/fonts/shaping/hangul-fixtures/no-jamo.ttf" as no_jamo : List(U8)
import "../tests/fonts/shaping/hangul-fixtures/zero-tone.ttf" as zero_tone : List(U8)
import "../tests/fonts/shaping/hangul-fixtures/no-circle.ttf" as no_circle : List(U8)

## Composition, Jamo masks and tone positioning
## in two real fonts. Two increasing text sizes isolate shaping work from
## font preparation and assert allocation growth no worse than linear.
## The whole-font malformed-input targets separately exercise these fonts.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = bytes.first() ?? 0
	file = match choice % 7 {
		0 => gothic
		1 => myeongjo
		2 => all_file
		3 => decomposed
		4 => no_jamo
		5 => zero_tone
		_ => no_circle
	}
	font = match Font.from_bytes(file, Font.ReadOptions.{}) {
		Ok(value) => value
		Err(_) => crash "real Hangul seed font did not read"
	}
	direction = LeftToRight
	clusters = if (choice.bitwise_and(4) == 0) Graphemes else Characters
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Hang", direction, clusters })
	alphabet = [0x1100, 0x1161, 0x11A8, 0xAC00, 0xAC01, 0x115F, 0x1160, 0xA960, 0xD7B0, 0xD7CB, 0x11FF, 0x302E, 0x302F, 0x200D, 0x200C, 0x034F, 0x20, 0x61]
	parts = bytes.drop_first(1).take_first(16).map(|b| alphabet.get(b.to_u64() % alphabet.len()) ?? 0x1100)
	word = [alphabet.first() ?? 0x1100].concat(parts).append(alphabet.get(9) ?? 0x1161)
	small = text_of(List.repeat(word, 2).join_map(|w| w))
	large = text_of(List.repeat(word, 16).join_map(|w| w))
	a = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, small))
	b = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, large))
	if b.allocations > 10 * a.allocations + 256 {
		crash "Hangul shaping allocation growth exceeded the input growth"
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
		crash "Hangul shaping is not deterministic"
	}
	n = run.glyphs.len()
	if n != run.advances.len() or n != run.offsets.len() or n != run.clusters.len() or n != run.flags.len() {
		crash "Hangul shaping lost index alignment"
	}
	if n > (64 * text.to_utf8().len()).max(16384) {
		crash "Hangul shaping exceeded its growth budget"
	}
	for i in 0..<n {
		cluster = run.clusters.get(i) ?? 0
		if cluster >= text.to_utf8().len() {
			crash "Hangul shaping produced a cluster outside the text"
		}
		if i > 0 {
			previous = run.clusters.get(i - 1) ?? 0
			if if (backward) previous < cluster else previous > cluster {
				crash "Hangul clusters lost monotonicity"
			}
		}
	}
	{}
}

target = Fuzz.target_with!({ name: "font-hangul", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(17)) })
