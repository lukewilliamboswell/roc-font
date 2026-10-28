app [target] {
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import fuzz.Fuzz
import font.Font
import "../tests/fonts/vertical/VerticalSansJP.ttf" as sans_jp : List(U8)
import "../tests/fonts/vertical/VerticalSerifJP.ttf" as serif_jp : List(U8)
import "../tests/fonts/vertical/gpos.ttf" as positioning : List(U8)

## Vertical forms, origins, marks, join controls and positioning
## in two real fonts. Two increasing text sizes isolate shaping work from
## font preparation and assert allocation growth no worse than linear.
## The whole-font malformed-input targets separately exercise these fonts.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = bytes.first() ?? 0
	original = choice.bitwise_and(8) != 0
	file = if (original) positioning else if (choice.bitwise_and(1) == 0) sans_jp else serif_jp
	font = match Font.from_bytes(file, Font.ReadOptions.{}) {
		Ok(value) => value
		Err(_) => crash "valid vertical seed font did not read"
	}
	direction = if (choice.bitwise_and(2) == 0) BottomToTop else TopToBottom
	clusters = if (choice.bitwise_and(4) == 0) Graphemes else Characters
	features = if (original) [Font.Feature.{ tag: "vkrn" }, Font.Feature.{ tag: "curs", value: if (choice.bitwise_and(16) == 0) 0 else 1 }] else []
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Hani", direction, clusters, features })
	alphabet = if (original) [0x61, 0x62, 0x63, 0x0301, 0x200C, 0x200D, 0x034F, 0x20] else [0x65E5, 0x672C, 0x8A9E, 0x3001, 0x3002, 0xFF08, 0xFF09, 0x2014, 0x2026, 0x0301, 0x200C, 0x200D, 0x034F, 0x20, 0x41]
	parts = bytes.drop_first(1).take_first(16).map(|b| alphabet.get(b.to_u64() % alphabet.len()) ?? 0x65E5)
	word = [if (original) 0x61 else 0x65E5].concat(parts).append(if (original) 0x62 else 0x672C)
	small = text_of(List.repeat(word, 2).join_map(|w| w))
	large = text_of(List.repeat(word, 16).join_map(|w| w))
	a = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, small))
	b = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, large))
	if b.allocations > 10 * a.allocations + 256 {
		crash "Vertical shaping allocation growth exceeded the input growth"
	}
	check(font, plan, small, direction == BottomToTop)
	check(font, plan, large, direction == BottomToTop)
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
		crash "Vertical shaping is not deterministic"
	}
	if run.advances.any(|advance| advance.x != 0) {
		crash "Vertical run has a horizontal advance"
	}
	n = run.glyphs.len()
	if n != run.advances.len() or n != run.offsets.len() or n != run.clusters.len() or n != run.flags.len() {
		crash "Vertical shaping lost index alignment"
	}
	if n > (256 * text.to_utf8().len()).max(65536) {
		crash "Vertical shaping exceeded its growth budget"
	}
	for i in 0..<n {
		cluster = run.clusters.get(i) ?? 0
		if cluster >= text.to_utf8().len() {
			crash "Vertical shaping produced a cluster outside the text"
		}
		if i > 0 {
			previous = run.clusters.get(i - 1) ?? 0
			if if (backward) previous < cluster else previous > cluster {
				crash "Vertical clusters lost monotonicity"
			}
		}
	}
	{}
}

target = Fuzz.target_with!({ name: "font-vertical", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(17)) })
