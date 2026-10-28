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

## Isolate contextual record count at8/64/256 while keeping matched
## positions and glyph count fixed. Huge valid cyclic/fanout fonts exercise
## the explicit depth and operations bounds without materialising calls.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = (bytes.first() ?? 0).to_u64()
	direction = if (choice.bitwise_and(8) == 0) LeftToRight else RightToLeft
	settings = Font.ShapeOptions.{ script: "Latn", language: "en", direction }
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
	file = match choice % 4 {
		0 => cycle
		1 => fanout
		2 => ignored
		_ => marked
	}
	depth = match (choice / 4) % 5 {
		0 => 0.U32
		1 => 1
		2 => 2
		3 => 3
		_ => 64
	}
	font = read(file, depth)
	text = if (choice % 4 == 3) "a\u(301)b" else "a"
	plan = Font.plan(font, settings)
	run = Font.shape_planned(font, plan, text)
	check(font, plan, text, run)
	Fuzz.expect_no_leaks!(|{}| Font.shape_planned(font, plan, text))
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
	if run.glyphs.any(|g| g >= Font.glyph_count(font)) or run.clusters.any(|i| i >= text.to_utf8().len()) {
		crash "context positioning escaped input"
	}
	if n > 65536 {
		crash "GPOS grew output"
	}
	{}
}

target = Fuzz.target_with!({ name: "font-position-context", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(16)) })
