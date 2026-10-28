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
import "../tests/fonts/graphite-geometry/benchmark-prefix/prefix-changing.ttf" as changing : List(U8)
import "../tests/fonts/graphite-geometry/attachment-lifetime-audit/collision-attachment-lifetime-metrics-a0-d5000.ttf" as lifetime : List(U8)
import "../tests/fonts/graphite-geometry/kern-frame-audit/collision-kern-frame-sample--603.ttf" as framed : List(U8)
import "../tests/fonts/graphite-geometry/kern-eligibility-audit/collision-eligibility-lower-10--31.ttf" as eligible : List(U8)
import "../tests/fonts/graphite-geometry/deleted-leaf-audit/collision-deleted-leaf-delete-ad-ltr.ttf" as leaf : List(U8)
import "../tests/fonts/graphite-geometry/deleted-metric-audit/collision-deleted-metric-intermediate-8-1-ltr.ttf" as composite_metric : List(U8)
import "../tests/fonts/graphite-geometry/downstream-gap-audit/collision-empty-gap-ltr-finite-empty.ttf" as empty_gap : List(U8)

## Original attachment, sequencing, retry and advance-correction programs;
## deleted attachment intermediates and visited-slot sampling frames;
## real collision font and hostile mutation. Three increasing run sizes
## retain the geometry path independently of VM instruction-count targets.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = (bytes.first() ?? 0).to_u64()
	kind = choice % 12
	file = match kind {
		0 => attached
		1 => kerned
		2 => sequenced
		3 => retried
		4 => awami
		5 => changing
		6 => lifetime
		7 => framed
		8 => eligible
		9 => leaf
		10 => composite_metric
		_ => empty_gap
	}
	settings = Font.ShapeOptions.{ script: if (kind == 4 or kind == 5) "Arab" else "Latn", direction: if (choice.bitwise_and(32) == 0) LeftToRight else RightToLeft }
	font = Font.from_bytes(file, Font.ReadOptions.{}) ?? crash "original Graphite geometry font rejected"
	plan = Font.plan(font, settings)
	if Font.shaping_engine(plan) != Graphite {
		crash "geometry fixture escaped its font programs"
	}
	piece = if (kind == 6 or kind == 9 or kind == 10) "abcd" else if (kind == 5 or kind == 7 or kind == 11) "abc" else "ab"
	empty = Font.shape_range_checked(font, plan, "", Font.TextRange.{ start: 0, end: 0xFFFFFFFFFFFFFFFF })
	check("", empty)
	if empty != Font.shape_range_checked(font, plan, "", Font.TextRange.{ start: 0, end: 0xFFFFFFFFFFFFFFFF }) {
		crash "empty geometry output is nondeterministic"
	}
	text = if (kind == 4) "بِسْمِ اللَّهِ" else Str.join_with(List.repeat(piece, 1 + (bytes.get(1) ?? 0).to_u64() % 16), "")
	checked = Font.shape_range_checked(font, plan, text, Font.TextRange.{ start: 0, end: 0xFFFFFFFFFFFFFFFF })
	if checked != Font.shape_range_checked(font, plan, text, Font.TextRange.{ start: 0, end: 0xFFFFFFFFFFFFFFFF }) {
		crash "nondeterministic geometry result"
	}
	check(text, checked)
	Fuzz.expect_no_leaks!(|{}| Font.shape_range_checked(font, plan, text, Font.TextRange.{ start: 0, end: 0xFFFFFFFFFFFFFFFF }))

	# Interacting targets permit quadratic work. Doubling the run must not
	# produce an unbounded higher-order allocation curve; exact counts are
	# separately ratcheted by the native benchmark after reference replay.
	if kind != 4 {
		a_text = Str.join_with(List.repeat(piece, 4), "")
		b_text = "${a_text}${a_text}"
		c_text = "${b_text}${b_text}"
		a = Fuzz.measure_allocs!(|{}| Font.shape_range_checked(font, plan, a_text, Font.TextRange.{ start: 0, end: 0xFFFFFFFFFFFFFFFF }))
		b = Fuzz.measure_allocs!(|{}| Font.shape_range_checked(font, plan, b_text, Font.TextRange.{ start: 0, end: 0xFFFFFFFFFFFFFFFF }))
		c = Fuzz.measure_allocs!(|{}| Font.shape_range_checked(font, plan, c_text, Font.TextRange.{ start: 0, end: 0xFFFFFFFFFFFFFFFF }))
		if b.allocations > a.allocations * 4 + 128 or c.allocations > b.allocations * 4 + 128 {
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
