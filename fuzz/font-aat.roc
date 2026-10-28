app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import font.Font
import fuzz.Fuzz
import build.FontBuild
import "../tests/fonts/aat/direct-logical.ttf" as direct : List(U8)
import "../tests/fonts/aat/rearrange-logical.ttf" as rearrange : List(U8)
import "../tests/fonts/aat/context-logical.ttf" as context : List(U8)
import "../tests/fonts/aat/ligature-logical.ttf" as ligature : List(U8)
import "../tests/fonts/aat/insertion-logical.ttf" as insertion : List(U8)
import "../tests/fonts/aat/language.ttf" as language : List(U8)
import "../tests/fonts/aat/tracking-1--65536.ttf" as tracking : List(U8)
import "../tests/fonts/aat/NotoSansTamilMN.ttf" as tamil : List(U8)

## The modern Apple stages through the public bundle: three isolated
## lookup sizes, original state programs, a real family, language and
## tracking data, then arbitrary byte corruption and shaping arguments.
recipe = |n| {
	lookup = FontBuild.u16(8).concat(FontBuild.u16(1)).concat(FontBuild.u16(n)).concat(FontBuild.counting(n).join_map(|i| FontBuild.u16(n - i)))
	sub = FontBuild.u32(12 + lookup.len()).concat(FontBuild.u32(0x30000004)).concat(FontBuild.u32(1)).concat(lookup)
	length = ((16 + sub.len() + 3) // 4) * 4
	chain = FontBuild.u32(1).concat(FontBuild.u32(length)).concat(FontBuild.u32(0)).concat(FontBuild.u32(1)).concat(sub)
	data = FontBuild.u32(0x00020000).concat(FontBuild.u32(1)).concat(chain).concat(List.repeat(0, length - chain.len()))
	cmap = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 0xE001, last: 0xE000 + n, delta: 65536 - 0xE000, glyphs: [] }]) }])
	FontBuild.glyphs_font(List.repeat(600, n + 1), cmap, [{ tag: "morx", data }])
}

check = |font, text, options| {
	plan = Font.plan(font, options)
	run = Font.shape_planned(font, plan, text)
	n = run.glyphs.len()
	if n != run.advances.len() or n != run.offsets.len() or n != run.clusters.len() or n != run.flags.len() {
		crash "Apple run columns lost alignment"
	}
	if n > (256 * text.to_utf8().len()).max(65536) or run.glyphs.any(|g| g >= Font.glyph_count(font)) {
		crash "Apple output escaped its glyph or growth bounds"
	}
	if run.clusters.any(|c| c.to_u64() >= text.to_utf8().len()) {
		crash "Apple cluster escaped the original text"
	}
	if Str.inspect(run) != Str.inspect(Font.shape_planned(font, plan, text)) {
		crash "Apple shaping is not deterministic"
	}
	match Font.shape_traced(font, plan, text) {
		Ok(trace) => if trace.origins.len() != n or Str.inspect(trace.run) != Str.inspect(run) {
			crash "Apple trace differs from ordinary shaping"
		}
		Err(OverBudget(trace)) => if trace.origins.len() != n or Str.inspect(trace.run) != Str.inspect(run) {
			crash "Apple budget trace differs"
		}
		Err(ProgramAborted(trace)) => if !trace.run.glyphs.is_empty() or !run.glyphs.is_empty() {
			crash "aborted program exposed a run"
		}
	}
}

test! = |bytes| {
	var $previous = 0.U64
	var $previous_tracking = 0.U64
	tracking_font = Font.from_bytes(tracking, Font.ReadOptions.{ strict: True }) ?? crash "valid tracking font rejected"
	for n in [16.U64, 64, 256] {
		file = recipe(n)
		measured = Fuzz.measure_allocs!(|{}| Font.from_bytes(file, Font.ReadOptions.{ strict: True }))
		if n > 16 and measured.allocations > 5 * $previous + 64 {
			crash "Apple lookup preparation allocation scaling"
		}
		$previous = measured.allocations
		font = Font.from_bytes(file, Font.ReadOptions.{ strict: True }) ?? crash "valid generated Apple lookup rejected"
		if Font.shape(font, "\u(E001)", Font.ShapeOptions.{}).glyphs != [n.to_u32_wrap()] {
			crash "Apple lookup result is not input aligned"
		}
		Fuzz.expect_no_leaks!(|{}| Font.from_bytes(file, Font.ReadOptions.{}))
		tracking_text = Str.join_with(List.repeat("a\u(0301)b", n), "")
		tracking_cost = Fuzz.measure_allocs!(|{}| Font.shape(tracking_font, tracking_text, Font.ShapeOptions.{ point_size: 24 }))
		if n > 16 and tracking_cost.allocations > 5 * $previous_tracking + 64 {
			crash "Apple tracking allocation scaling"
		}
		$previous_tracking = tracking_cost.allocations
		Fuzz.expect_no_leaks!(|{}| Font.shape(tracking_font, tracking_text, Font.ShapeOptions.{ point_size: 24 }))
	}
	seed = match (bytes.first() ?? 0) % 8 {
		0 => direct
		1 => rearrange
		2 => context
		3 => ligature
		4 => insertion
		5 => language
		6 => tracking
		_ => tamil
	}
	file = if (bytes.take_first(4) == [0, 1, 0, 0]) bytes else FontBuild.mutate(seed, bytes.drop_first(1))
	match (Font.from_bytes(file, Font.ReadOptions.{}), Font.from_bytes(file, Font.ReadOptions.{})) {
		(Err(a), Err(b)) => if a != b {
			crash "Apple preparation diagnostics changed"
		}
		(Ok(font), Ok(_)) => {
			text = Str.from_utf8_lossy(bytes.take_first(24))
			for direction in [LeftToRight, RightToLeft, TopToBottom, BottomToTop] {
				check(font, text, Font.ShapeOptions.{ direction, language: "en-US", point_size: (bytes.get(1) ?? 12).to_dec(), features: [Font.Feature.{ tag: "liga", value: (bytes.get(2) ?? 1).to_u32() % 2, start: 1, end: 8 }] })
			}
			Fuzz.expect_no_leaks!(|{}| Font.shape(font, text, Font.ShapeOptions.{}))
		}
		_ => crash "Apple preparation changed"
	}
	Fuzz.keep
}

target = Fuzz.target_with!({ name: "font-aat", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(16)) })
