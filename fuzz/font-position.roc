app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import fuzz.Fuzz
import font.Font
import build.FontBuild
import PositionBuild
import "../tests/fonts/positioning/mark-mark.ttf" as real_seed : List(U8)

import "../tests/fonts/positioning/flags/variable-cancellation.ttf" as cancellation : List(U8)

## One full GPOS family per input, optionally through an extension. Two
## generated sizes (2 and 16 copies of the isolated lookup) measure reading
## allocations and ensure unused lookups do not affect shaping allocations
## or results. Input bytes also mutate a valid seeded font, or are a real
## font corpus input. Every accepted font must shape deterministically into
## finite integer positions, aligned lists, bounded glyph growth and text
## clusters, without leaking. This intentionally uses the package bundle.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = bytes.first() ?? 0
	values = bytes.drop_first(1).take_first(32)
	text = PositionBuild.text(values)
	small = PositionBuild.file(choice, values, 2)
	large = PositionBuild.file(choice, values, 16)
	small_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(small, Font.ReadOptions.{}))
	large_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(large, Font.ReadOptions.{}))
	if large_read.allocations > 10 * small_read.allocations + 256 {
		crash "positioning reading allocations grew faster than the isolated feature"
	}
	match (small_read.value, large_read.value) {
		(Ok(a), Ok(b)) => {
			pa = Font.plan(a, Font.ShapeOptions.{})
			pb = Font.plan(b, Font.ShapeOptions.{})
			x = Fuzz.measure_allocs!(|{}| Font.shape_planned(a, pa, text))
			y = Fuzz.measure_allocs!(|{}| Font.shape_planned(b, pb, text))
			if x.allocations + 16 < y.allocations {
				crash "unused positioning lookups increased shaping allocations"
			}
			if Str.inspect(x.value) != Str.inspect(y.value) {
				crash "unused positioning lookups changed the run"
			}
			check(a, text)
			Fuzz.expect_no_leaks!(|{}| Font.shape_planned(b, pb, text))
		}
		_ => crash "generated positioning fixture did not read"
	}
	mutated = FontBuild.fuzz_font(bytes, real_seed)
	match Font.from_bytes(mutated, Font.ReadOptions.{}) {
		Ok(font) => check(font, "a\u(0301)\u(0300) f\u(0301)i abc")
		Err(_) => {}
	}
	Fuzz.expect_no_leaks!(|{}| Font.from_bytes(mutated, Font.ReadOptions.{}))
	font = Font.from_bytes(cancellation, Font.ReadOptions.{}) ?? crash "variable pair flag fixture did not read"
	coordinate = 100 + choice.to_u64().to_dec() * 4
	varied = Font.at(font, Font.Variation.{ axes: [{ tag: "wght", value: coordinate }] })
	general = Font.shape(varied, "ab", Font.ShapeOptions.{})
	pair = Font.shape(varied, "ab", Font.ShapeOptions.{ features: [Font.Feature.{ tag: "dist", value: 0 }] })
	if Str.inspect(general) != Str.inspect(pair) {
		crash "pair positioning policies disagree after variable cancellation"
	}
	Fuzz.keep
}

check : Font, Str -> {}
check = |font, text| {
	plan = Font.plan(font, Font.ShapeOptions.{})
	run = Font.shape_planned(font, plan, text)
	if Str.inspect(run) != Str.inspect(Font.shape_planned(font, plan, text)) {
		crash "positioning is not deterministic"
	}
	n = run.glyphs.len()
	if n != run.advances.len() or n != run.offsets.len() or n != run.clusters.len() or n != run.flags.len() {
		crash "positioning lost index alignment"
	}
	if n > (256 * text.to_utf8().len()).max(65536) {
		crash "positioning exceeded glyph growth bound"
	}
	var $previous = 0.U64
	for c in run.clusters {
		if c < $previous or c >= text.to_utf8().len() {
			crash "positioning produced an invalid cluster"
		}
		$previous = c
	}
	{}
}

target = Fuzz.target_with!({
	name: "font-position",
	generator: Fuzz.raw_bytes,
	test!,
	show: |bytes| Str.inspect(bytes.take_first(65)),
})
