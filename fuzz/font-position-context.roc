app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import fuzz.Fuzz
import font.Font
import build.FontBuild
import "../tests/fonts/positioning/context-budget/many-8.ttf" as small : List(U8)
import "../tests/fonts/positioning/context-budget/many-64.ttf" as medium : List(U8)
import "../tests/fonts/positioning/context-budget/many-256.ttf" as large : List(U8)
import "../tests/fonts/positioning/context-budget/cycle-8192.ttf" as cycle : List(U8)
import "../tests/fonts/positioning/context-budget/fanout-8192.ttf" as fanout : List(U8)
import "../tests/fonts/positioning/context-budget/ignored-8192.ttf" as ignored : List(U8)
import "../tests/fonts/positioning/context-budget/context-3.ttf" as marked : List(U8)

import "../tests/fonts/positioning/context-budget/saturating-advance.ttf" as saturating_advance : List(U8)
import "../tests/fonts/positioning/context-budget/saturating-placement.ttf" as saturating_placement : List(U8)
import "../tests/fonts/positioning/context-budget/device-advance.ttf" as device_advance : List(U8)
import "../tests/fonts/positioning/context-budget/device-placement.ttf" as device_placement : List(U8)
import "../tests/fonts/positioning/context-budget/float-anchor.ttf" as float_anchor : List(U8)
import "../tests/fonts/positioning/context-budget/attachment-distance.ttf" as distance_file : List(U8)
import "../tests/fonts/positioning/context-budget/attachment-mixed-advances.ttf" as mixed_file : List(U8)

import "../tests/fonts/positioning/context-budget/pair-absolute.ttf" as pair_absolute : List(U8)

## Isolate contextual record count at 8/64/256 while keeping matched
## positions and glyph count fixed. Huge valid cyclic/fanout fonts exercise
## the explicit depth and operations bounds without materialising calls.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = (bytes.first() ?? 0).to_u64()
	direction = if (choice.bitwise_and(8) == 0) LeftToRight else RightToLeft
	settings = Font.ShapeOptions.{ script: "Latn", language: "en", direction, limits: Font.ShapeLimits.{ growth: if (choice % 12 == 10) 1 else 256, operations: if (choice % 12 == 10) 1 else 4096 } }
	a = read(small, 64)
	b = read(medium, 64)
	c = read(large, 64)
	pa = Font.plan(a, settings)
	pb = Font.plan(b, settings)
	pc = Font.plan(c, settings)
	x = Fuzz.measure_allocs!(|{}| Font.shape_planned(a, pa, "a"))
	y = Fuzz.measure_allocs!(|{}| Font.shape_planned(b, pb, "a"))
	z = Fuzz.measure_allocs!(|{}| Font.shape_planned(c, pc, "a"))
	if y.allocations > x.allocations + 8 or z.allocations > y.allocations + 8 {
		crash "context record count grew shaping allocations"
	}
	if x.value.advances != [{ x: 518, y: 0 }] or y.value.advances != [{ x: 574, y: 0 }] or z.value.advances != [{ x: 766, y: 0 }] {
		crash "lazy contextual records were skipped or reordered"
	}
	branch = choice % 12
	file = match branch {
		0 => cycle
		1 => fanout
		2 => ignored
		3 => marked
		4 => saturating_advance
		5 => saturating_placement
		6 => device_advance
		7 => device_placement
		8 => float_anchor
		9 => mixed_file
		10 => distance_file
		_ => pair_absolute
	}
	depth = if (branch >= 4) 64.U32 else match (choice / 12) % 5 {
		0 => 0
		1 => 1
		2 => 2
		3 => 3
		_ => 64
	}
	coordinate = (bytes.get(1) ?? 255).to_u64().to_dec() / 255
	original = read(file, depth)
	font = if ((branch >= 6 and branch <= 8) or branch == 11) Font.at(original, Font.Variation.{ axes: [{ tag: "wght", value: coordinate }] }) else original
	distance = 32767 + (bytes.get(1) ?? 0).to_u64() % 3
	text = match branch {
		0 | 1 | 2 => "a"
		3 => "a\u(301)b"
		4 | 5 => Str.join_with(List.repeat("a", 64), "")
		6 | 7 => Str.join_with(List.repeat("a", 32), "")
		8 => "a\u(301)"
		9 => "a\u(301)${Str.join_with(List.repeat(" ", 30), "")}"
		10 => "a${Str.join_with(List.repeat("b", distance - 1), "")}\u(301)"
		_ => "ab"
	}
	plan = Font.plan(font, settings)
	run = Font.shape_planned(font, plan, text)
	check(font, plan, text, run)
	if branch == 4 or branch == 5 {
		values = if (branch == 4) run.advances else run.offsets
		if !values.any(|p| p.x == -268435457) or !values.any(|p| p.x == 806354943) {
			crash "per-operation saturation lost overflow cancellation"
		}
	}
	if coordinate == 1 and (branch == 6 or branch == 7) {
		values = if (branch == 6) run.advances else run.offsets
		if !values.any(|p| p.x == 2147450879) {
			crash "stored and device corrections were combined before saturation"
		}
	}
	if coordinate == 1 and branch == 8 and !run.offsets.any(|p| p.x == -510) {
		crash "anchor float32 rounding was replaced by integer arithmetic"
	}
	if branch == 9 and !run.offsets.any(|p| p.x == 2147483646) {
		crash "mixed-sign advances were summed before saturation"
	}
	if branch == 10 {
		for i in 0..<run.glyphs.len() {
			if (run.glyphs.get(i) ?? 0) == 3 {
				expected = if (direction == LeftToRight and distance <= 32768) { x: -410, y: 700 } else { x: 0, y: 0 }
				if (run.offsets.get(i) ?? { x: 0, y: 0 }) != expected {
					crash "attachment parent distance escaped signed16 bounds"
				}
			}
		}
	}
	if branch == 11 and coordinate == 1 and direction == LeftToRight and !run.advances.any(|p| p.x == 2147450879) {
		crash "pair-only positioning saturated deltas rather than absolute advances"
	}
	Fuzz.expect_no_leaks!(|{}| Font.shape_planned(font, plan, text))
	if branch == 9 {
		mixed = read(mixed_file, 64)
		mp = Font.plan(mixed, settings)
		first = "a\u(301)${Str.join_with(List.repeat(" ", 8), "")}"
		second = "a\u(301)${Str.join_with(List.repeat(" ", 64), "")}"
		third = "a\u(301)${Str.join_with(List.repeat(" ", 256), "")}"
		u = Fuzz.measure_allocs!(|{}| Font.shape_planned(mixed, mp, first))
		v = Fuzz.measure_allocs!(|{}| Font.shape_planned(mixed, mp, second))
		w = Fuzz.measure_allocs!(|{}| Font.shape_planned(mixed, mp, third))
		if v.allocations > u.allocations + 32 or w.allocations > v.allocations + 32 {
			crash "mixed-sign attachment summaries allocated per glyph"
		}
		check(mixed, mp, first, u.value)
		check(mixed, mp, second, v.value)
		check(mixed, mp, third, w.value)
	}
	damaged = FontBuild.fuzz_font(bytes, file)
	match Font.from_bytes(damaged, Font.ReadOptions.{}) {
		Ok(f) => check(f, Font.plan(f, settings), text, Font.shape(f, text, settings))
		Err(_) => {}
	}
	Fuzz.expect_no_leaks!(|{}| Font.from_bytes(damaged, Font.ReadOptions.{}))
	Fuzz.keep
}

read = |bytes, depth| match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True, limits: Font.Limits.{ max_depth: depth } }) {
	Ok(f) => f
	Err(_) => crash "generated context fixture rejected"
}

check = |font, plan, text, run| {
	if run != Font.shape_planned(font, plan, text) {
		crash "nondeterministic context positioning"
	}
	n = run.glyphs.len()
	if n != run.advances.len() or n != run.offsets.len() or n != run.clusters.len() or n != run.flags.len() {
		crash "context positioning lost index alignment"
	}
	glyph_count = Font.glyph_count(font)
	if run.glyphs.any(|g| g >= glyph_count) or run.clusters.any(|i| i >= text.to_utf8().len()) {
		crash "context positioning escaped input"
	}
	var $scalars = 0.U64
	for byte in text.to_utf8() {
		if byte.bitwise_and(0xc0) != 0x80 {
			$scalars = $scalars + 1
		}
	}
	if n > (256 * $scalars).max(65536) {
		crash "GPOS grew output"
	}
	{}
}

target = Fuzz.target_with!({ name: "font-position-context", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(16)) })
