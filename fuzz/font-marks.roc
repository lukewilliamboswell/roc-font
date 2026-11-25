app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
}

import build.FontBuild
import font.Font
import fuzz.Fuzz
import src/MarkFixture
import "../tests/fonts/mark-attachment/DavidLibre-Regular.ttf" as david : List(U8)

## Mark-to-base, mark-to-ligature and mark-to-mark. Generated fonts share
## identical anchors for the text and differ by unused coverage rows.
## A separate seed shapes a real Hebrew run with caller-selected features.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = bytes.first() ?? 0
	if choice == 255 {
		font = read(david)
		text = Str.from_utf8_lossy(bytes.drop_first(2).take_first(256))
		setting = bytes.get(1) ?? 0
		features = match setting % 3 {
			0 => []
			1 => [Font.Feature.{ tag: "mark", value: 0 }]
			_ => [Font.Feature.{ tag: "mkmk", value: 0 }]
		}
		plan = Font.plan(font, Font.ShapeOptions.{ script: "Hebr", language: "he", direction: RightToLeft, features })
		run = Font.shape_planned(font, plan, text)
		check_run!(text, run)
		if Str.inspect(run) != Str.inspect(Font.shape_planned(font, plan, text)) {
			crash "repeating a marked run changed the result"
		}
	} else {
		kind = 4 + choice.to_u64() % 3
		extended = choice.bitwise_and(0x04) != 0
		x = (bytes.get(1) ?? 100).to_i64() - 128
		y = (bytes.get(2) ?? 150).to_i64() - 128
		repeats = 1 + (bytes.get(3) ?? 0).to_u64() % 64
		piece = if (kind == 6) "A\u(301)\u(300)" else "A\u(300)"
		text = Str.join_with(List.repeat(piece, repeats), "")
		small = MarkFixture.bytes(kind, extended, x, y, 16, Valid)
		large = MarkFixture.bytes(kind, extended, x, y, 128, Valid)
		small_read = Fuzz.measure!("small-read", || read(small))
		large_read = Fuzz.measure!("large-read", || read(large))
		if large_read.stats.allocs + large_read.stats.reallocs > 10 * (small_read.stats.allocs + small_read.stats.reallocs) + 64 {
			crash "eight times the mark anchors exceeded linear reading allocations"
		}
		options = Font.ShapeOptions.{ script: "Latn", clusters: Characters }
		small_plan = Font.plan(small_read.value, options)
		large_plan = Font.plan(large_read.value, options)
		small_shape = Fuzz.measure!("small-shape", || Font.shape_planned(small_read.value, small_plan, text))
		large_shape = Fuzz.measure!("large-shape", || Font.shape_planned(large_read.value, large_plan, text))
		Fuzz.expect_no_leaks!(|| Font.shape_planned(large_read.value, large_plan, text))
		if large_shape.stats.allocs + large_shape.stats.reallocs > small_shape.stats.allocs + small_shape.stats.reallocs + 8 {
			crash "unused mark anchors changed shaping allocation calls"
		}
		run = large_shape.value
		check_run!(text, run)
		if Str.inspect(small_shape.value) != Str.inspect(run) or Str.inspect(Font.shape_planned(large_read.value, large_plan, text)) != Str.inspect(run) {
			crash "unused mark anchors or repeated shaping changed the run"
		}
		wrap = if (kind == 6) 3 else 2
		want = { x: (x - 11 - (if (kind == 6) 0 else 610)).to_i32_wrap(), y: (y + 23).to_i32_wrap() }
		if run.glyphs.len() != wrap * repeats or !FontBuild.counting(repeats).all(|i| run.offsets.get(wrap * i + wrap - 1) == Ok(want)) {
			crash "the mark missed its selected anchor: ${Str.inspect(run)}"
		}
	}
	Fuzz.keep
}

read : List(U8) -> Font
read = |bytes| match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
	Ok(font) => font
	Err(problems) => crash "a valid attachment font failed to read: ${Str.inspect(problems)}"
}

check_run! : Str, Font.Run => {}
check_run! = |text, run| {
	n = run.glyphs.len()
	bytes = text.to_utf8().len()
	if run.advances.len() != n or run.offsets.len() != n or run.clusters.len() != n or run.flags.len() != n {
		crash "mark positioning produced misaligned lists"
	}
	if n > (64 * bytes).max(16384) or !run.clusters.all(|c| c < bytes) {
		crash "mark positioning exceeded its text bounds"
	}
}

target = Fuzz.target_with!({
	examples: [],
	name: "font-marks",
	generator: Fuzz.raw_bytes,
	test!,
	show: |bytes| Str.inspect(bytes.take_first(32)),
})
