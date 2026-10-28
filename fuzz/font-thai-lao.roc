app [target] {
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import fuzz.Fuzz
import font.Font
import "../tests/fonts/shaping/thai/NotoSerifThai-Regular.ttf" as serif : List(U8)
import "../tests/fonts/shaping/lao/NotoSansLao-Regular.ttf" as lao : List(U8)

import "../tests/fonts/shaping/thai-legacy/windows.ttf" as windows : List(U8)
import "../tests/fonts/shaping/thai-legacy/macintosh.ttf" as macintosh : List(U8)

## Sara Am decomposition and above-base mark reordering
## in two real fonts. Two increasing text sizes isolate shaping work from
## font preparation and assert allocation growth no worse than linear.
## The whole-font malformed-input targets separately exercise these fonts.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = bytes.first() ?? 0
	is_thai = choice.bitwise_and(1) == 0 or choice.bitwise_and(8) != 0
	file = if choice.bitwise_and(8) != 0 {
		if (choice.bitwise_and(1) == 0) windows else macintosh
	} else if (is_thai) serif else lao
	font = match Font.from_bytes(file, Font.ReadOptions.{}) {
		Ok(value) => value
		Err(_) => crash "real Thai/Lao seed font did not read"
	}
	direction = LeftToRight
	clusters = if (choice.bitwise_and(4) == 0) Graphemes else Characters
	plan = Font.plan(font, Font.ShapeOptions.{ script: if (is_thai) "Thai" else "Laoo", direction, clusters })
	alphabet = if (is_thai) [0xE01, 0xE0D, 0xE10, 0xE0E, 0xE0F, 0xE1B, 0xE1D, 0xE1F, 0xE31, 0xE33, 0xE34, 0xE37, 0xE38, 0xE39, 0xE3A, 0xE47, 0xE48, 0xE4B, 0xE4D, 0x200D, 0x20] else [0xE81, 0xEB1, 0xEB3, 0xEB4, 0xEB7, 0xEBB, 0xEC8, 0xECB, 0xECD, 0x200D, 0x20]
	parts = bytes.drop_first(1).take_first(16).map(|b| alphabet.get(b.to_u64() % alphabet.len()) ?? 0xE01)
	word = [alphabet.first() ?? 0xE01].concat(parts).append(alphabet.get(9) ?? 0xE33)
	small = text_of(List.repeat(word, 2).join_map(|w| w))
	large = text_of(List.repeat(word, 16).join_map(|w| w))
	a = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, small))
	b = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, large))
	if b.allocations > 10 * a.allocations + 256 {
		crash "Thai/Lao shaping allocation growth exceeded the input growth"
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
		crash "Thai/Lao shaping is not deterministic"
	}
	n = run.glyphs.len()
	if n != run.advances.len() or n != run.offsets.len() or n != run.clusters.len() or n != run.flags.len() {
		crash "Thai/Lao shaping lost index alignment"
	}
	if n > (256 * text.to_utf8().len()).max(65536) {
		crash "Thai/Lao shaping exceeded its growth budget"
	}
	for i in 0..<n {
		cluster = run.clusters.get(i) ?? 0
		if cluster >= text.to_utf8().len() {
			crash "Thai/Lao shaping produced a cluster outside the text"
		}
		if i > 0 {
			previous = run.clusters.get(i - 1) ?? 0
			if if (backward) previous < cluster else previous > cluster {
				crash "Thai/Lao clusters lost monotonicity"
			}
		}
	}
	{}
}

target = Fuzz.target_with!({ name: "font-thai-lao", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(17)) })
