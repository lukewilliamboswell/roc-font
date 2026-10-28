app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import fuzz.Fuzz
import font.Font
import build.FontBuild
import "../tests/fonts/graphite-geometry/attach-forward-ltr.ttf" as attached : List(U8)
import "../tests/fonts/graphite-geometry/kerning-audit/collision-kern-audit-base-ltr.ttf" as kerned : List(U8)
import "../tests/fonts/graphite-geometry/sequencing-audit/collision-sequence-audit-canonical-ltr.ttf" as sequenced : List(U8)
import "../tests/fonts/graphite-geometry/retry-audit/collision-retry-audit-fractional-prior-pass-100-ltr.ttf" as retried : List(U8)
import "../tests/fonts/graphite/AwamiNastaliq-Regular.ttf" as awami : List(U8)

## Original attachment, sequencing, retry and advance-correction programs;
## real collision font; hostile font mutation. Three increasing run sizes
## retain the geometry path independently of VM instruction-count targets.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = (bytes.first() ?? 0).to_u64()
	file = match choice % 5 {
		0 => attached
		1 => kerned
		2 => sequenced
		3 => retried
		_ => awami
	}
	settings = Font.ShapeOptions.{ script: if (choice % 5 == 4) "Arab" else "Latn", direction: if (choice.bitwise_and(8) == 0) LeftToRight else RightToLeft }
	font = Font.from_bytes(file, Font.ReadOptions.{}) ?? crash "original Graphite geometry font rejected"
	plan = Font.plan(font, settings)
	if Font.shaping_engine(plan) != Graphite {
		crash "geometry fixture escaped its font programs"
	}
	text = if (choice % 5 == 4) "بِسْمِ اللَّهِ" else Str.join_with(List.repeat("ab", 1 + (bytes.get(1) ?? 0).to_u64() % 16), "")
	checked = Font.shape_range_checked(font, plan, text, Font.TextRange.{ start: 0, end: 0xFFFFFFFFFFFFFFFF })
	if checked != Font.shape_range_checked(font, plan, text, Font.TextRange.{ start: 0, end: 0xFFFFFFFFFFFFFFFF }) {
		crash "nondeterministic geometry result"
	}
	check(text, checked)
	Fuzz.expect_no_leaks!(|{}| Font.shape_range_checked(font, plan, text, Font.TextRange.{ start: 0, end: 0xFFFFFFFFFFFFFFFF }))

	# Interacting targets permit quadratic work. Doubling the run must not
	# produce an unbounded higher-order allocation curve; exact counts are
	# separately ratcheted by the native benchmark after reference replay.
	if choice % 5 != 4 {
		a_text = "abababab"
		b_text = "${a_text}${a_text}"
		c_text = "${b_text}${b_text}"
		a = Fuzz.measure_allocs!(|{}| Font.shape_range_checked(font, plan, a_text, Font.TextRange.{ start: 0, end: 0xFFFFFFFFFFFFFFFF }))
		b = Fuzz.measure_allocs!(|{}| Font.shape_range_checked(font, plan, b_text, Font.TextRange.{ start: 0, end: 0xFFFFFFFFFFFFFFFF }))
		c = Fuzz.measure_allocs!(|{}| Font.shape_range_checked(font, plan, c_text, Font.TextRange.{ start: 0, end: 0xFFFFFFFFFFFFFFFF }))
		if b.allocations > a.allocations * 8 + 128 or c.allocations > b.allocations * 8 + 128 {
			crash "geometry allocations grew faster than interacting glyph pairs"
		}
		check(a_text, a.value)
		check(b_text, b.value)
		check(c_text, c.value)
	}

	damaged = FontBuild.fuzz_font(bytes, file)
	match Font.from_bytes(damaged, Font.ReadOptions.{}) {
		Err(_) => {}
		Ok(mutated) => {
			mutated_plan = Font.plan(mutated, settings)
			result = Font.shape_range_checked(mutated, mutated_plan, text, Font.TextRange.{ start: 0, end: 0xFFFFFFFFFFFFFFFF })
			check(text, result)
			if result != Font.shape_range_checked(mutated, mutated_plan, text, Font.TextRange.{ start: 0, end: 0xFFFFFFFFFFFFFFFF }) {
				crash "hostile geometry font is nondeterministic"
			}
		}
	}
	Fuzz.expect_no_leaks!(|{}| Font.from_bytes(damaged, Font.ReadOptions.{}))
	Fuzz.keep
}

check = |text, checked| {
	run = match checked {
		Ok(result) => result
		Err(OverBudget(result)) => result.run
		Err(ProgramAborted(result)) => result.run
	}
	n = run.glyphs.len()
	if n != run.advances.len() or n != run.offsets.len() or n != run.clusters.len() or n != run.flags.len() {
		crash "geometry output lost index alignment"
	}
	if n > text.count_utf8_bytes() * 256 + 65536 {
		crash "geometry output escaped growth budget"
	}
	if run.clusters.any(|cluster| cluster >= text.count_utf8_bytes()) {
		crash "geometry cluster escaped caller text"
	}
}

target = Fuzz.target_with!({ name: "font-graphite-geometry", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(32)) })
