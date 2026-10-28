app [target] {
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import "../tests/fonts/shaping/myanmar/sort-8.ttf" as sorting : List(U8)
import fuzz.Fuzz
import font.Font
import "../tests/fonts/shaping/myanmar/NotoSansMyanmar-Regular.ttf" as sans : List(U8)
import "../tests/fonts/shaping/myanmar/NotoSerifMyanmar-Regular.ttf" as serif : List(U8)
import "../tests/fonts/shaping/myanmar/modern.ttf" as modern : List(U8)
import "../tests/fonts/shaping/myanmar/legacy.ttf" as legacy : List(U8)
import "../tests/fonts/shaping/myanmar/no-circle.ttf" as no_circle : List(U8)

## Narrow Myanmar syllable/reorder target. Font preparation and planning
## happen before allocation measurements at2/8/32 text repetitions. Real
## modern fonts and original modern/legacy/missing-circle fixtures cover
## both directions, cluster modes, joins, broken syllables and feature flags.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = (bytes.first() ?? 0).to_u64()
	file = match choice % 6 {
		0 => sans
		1 => serif
		2 => modern
		3 => legacy
		4 => no_circle
		_ => sorting
	}
	font = match Font.from_bytes(file, Font.ReadOptions.{}) {
		Ok(f) => f
		Err(_) => crash "licensed Myanmar fuzz font failed to read"
	}
	# The seeded modern-font branch fails if this artifact accidentally
	# exercises only the generic pipeline. The input keeps the check live.
	if choice % 6 == 2 {
		if Font.shape(font, "ကေ", Font.ShapeOptions.{ script: "Mymr" }).glyphs != [5, 19] {
			crash "Myanmar model is not active in the public bundle"
		}
	}

	direction = if (choice.bitwise_and(8) == 0) LeftToRight else RightToLeft
	clusters = if (choice.bitwise_and(16) == 0) Graphemes else Characters
	features = if (choice.bitwise_and(32) == 0) [] else [Font.Feature.{ tag: "pref", value: 0 }]
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Mymr", direction, clusters, features })
	alphabet = [0x1000.U64, 0x1004, 0x1005, 0x1009, 0x1014, 0x1019, 0x101b, 0x1025, 0x1026, 0x102d, 0x102e, 0x102f, 0x1030, 0x1031, 0x1032, 0x1036, 0x1037, 0x1038, 0x1039, 0x103a, 0x103b, 0x103c, 0x103d, 0x103e, 0x1040, 0x1050, 0x1060, 0x1070, 0x1080, 0x1090, 0xaa60, 0xaa7b, 0xaa7c, 0xaa7d, 0x200c, 0x200d, 0xfe00, 0xfe01, 0x034f, 0x25cc, 0x116d0, 0x20]
	parts = bytes.drop_first(1).take_first(24).map(|b| alphabet.get(b.to_u64() % alphabet.len()) ?? 0x1000)
	word = [0x1000].concat(parts).append(0x1031)
	small = text_of(List.repeat(word, 2).join_map(|w| w))
	medium = text_of(List.repeat(word, 8).join_map(|w| w))
	large = text_of(List.repeat(word, 32).join_map(|w| w))
	a = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, small))
	b = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, medium))
	c = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, large))
	if b.allocations > 5 * a.allocations + 256 or c.allocations > 5 * b.allocations + 512 {
		crash "Myanmar shaping allocation growth exceeded generated feature size"
	}
	check(font, plan, small, direction == RightToLeft, a.value)
	check(font, plan, medium, direction == RightToLeft, b.value)
	check(font, plan, large, direction == RightToLeft, c.value)
	# Long uninterrupted left-vowel runs cross byte-sized provenance and
	# unsafe-flag thresholds. Variation selectors stay with their left vowel.
	if choice.bitwise_and(64) != 0 {
		long = text_of([0x1000].concat(List.repeat([0x1031, 0xfe00], 160).join_map(|w| w)))
		check(font, plan, long, direction == RightToLeft, Font.shape_planned(font, plan, long))
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
				[0xc0 + cp.shr_zf_wrap(6), 0x80 + cp.bitwise_and(63)].map(|b| b.to_u8_wrap())
			}
			else if cp < 65536 {
				[0xe0 + cp.shr_zf_wrap(12), 0x80 + cp.shr_zf_wrap(6).bitwise_and(63), 0x80 + cp.bitwise_and(63)].map(|b| b.to_u8_wrap())
			}
			else {
				[0xf0 + cp.shr_zf_wrap(18), 0x80 + cp.shr_zf_wrap(12).bitwise_and(63), 0x80 + cp.shr_zf_wrap(6).bitwise_and(63), 0x80 + cp.bitwise_and(63)].map(|b| b.to_u8_wrap())
			}
		},
	),
) ?? ""

check : Font, Font.ShapePlan, Str, Bool, Font.Run -> {}
check = |font, plan, text, backward, run| {
	again = Font.shape_planned(font, plan, text)
	if run != again {
		crash "Myanmar shaping is nondeterministic"
	}
	n = run.glyphs.len()
	if n != run.advances.len() or n != run.offsets.len() or n != run.clusters.len() or n != run.flags.len() {
		crash "Myanmar glyph facts lost index alignment"
	}
	var $scalar_count = 0.U64
	for byte in text.to_utf8() {
		if byte.bitwise_and(0xc0) != 0x80 {
			$scalar_count = $scalar_count + 1
		}
	}
	if n > (256 * $scalar_count).max(65536) {
		crash "Myanmar shaping exceeded growth bound"
	}
	if run.glyphs.any(|g| g >= Font.glyph_count(font)) {
		crash "Myanmar shaping returned a glyph outside the font"
	}
	for i in 0..<n {
		cluster = run.clusters.get(i) ?? 0
		if cluster >= text.to_utf8().len() {
			crash "Myanmar cluster escaped input"
		}
		if i > 0 {
			previous = run.clusters.get(i - 1) ?? 0
			if if (backward) previous < cluster else previous > cluster {
				crash "Myanmar clusters lost monotonicity"
			}
		}
	}
	{}
}

target = Fuzz.target_with!({ name: "font-myanmar", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(25)) })
