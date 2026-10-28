app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	mort: "../tests/fonts/aat-mort/main.roc",
}
import font.Font
import build.FontBuild
import mort.MortBuild
import fuzz.Fuzz
import "../tests/fonts/aat-mort/direct-logical.ttf" as direct_file : List(U8)
import "../tests/fonts/aat-mort/rearrange-logical.ttf" as rearrange_file : List(U8)
import "../tests/fonts/aat-mort/context-logical.ttf" as context_file : List(U8)
import "../tests/fonts/aat-mort/ligature-logical.ttf" as ligature_file : List(U8)
import "../tests/fonts/aat-mort/insertion-logical.ttf" as insertion_file : List(U8)
import "../tests/fonts/aat-mort/context-negative.ttf" as signed_file : List(U8)
import "../tests/fonts/aat-mort/ligature-multistore.ttf" as multistore_file : List(U8)
import "../tests/fonts/aat-mort/body-sans.ttf" as real_file : List(U8)

## All legacy morphing types, real font-body corruption, bounded looping,
## deterministic results and aligned runs. Isolated16/64/192-state programs
## share overlapping signed-offset substitution pools and must scale linearly
## in preparation/query allocation calls, without leaking their output.
aligned = |run| run.glyphs.len() == run.advances.len() and run.glyphs.len() == run.offsets.len() and run.glyphs.len() == run.clusters.len() and run.glyphs.len() == run.flags.len()

shape = |font, text| Font.shape(font, text, Font.ShapeOptions.{ script: "Latn" })

test! = |bytes| {
	choice = (bytes.first() ?? 0).to_u64()
	var $read_cost = 0.U64
	var $shape_cost = 0.U64
	for n in [16.U64, 64, 192] {
		file = MortBuild.file(n, choice)
		font = match Font.from_bytes(file, Font.ReadOptions.{ strict: True }) {
			Ok(ready) => ready
			Err(problems) => crash Str.inspect(problems)
		}
		text = Str.join_with(List.repeat("A", n), "")
		run = shape(font, text)
		if !aligned(run) or run.glyphs.len() != n or !run.glyphs.map_with_index(|glyph, i| glyph == 2 + ((i + choice) % 2).to_u32_wrap()).all(|ok| ok) {
			crash "mort overlapping lookup normalization changed output"
		}
		if run != shape(font, text) {
			crash "mort output nondeterministic"
		}
		reading = Fuzz.measure_allocs!(|{}| Font.from_bytes(file, Font.ReadOptions.{}))
		shaping = Fuzz.measure_allocs!(|{}| shape(font, text))
		if n > 16 and (reading.allocations > 5 * $read_cost + 128 or shaping.allocations > 5 * $shape_cost + 128) {
			crash "mort state/pool allocation scaling"
		}
		$read_cost = reading.allocations
		$shape_cost = shaping.allocations
		Fuzz.expect_no_leaks!(|{}| Font.from_bytes(file, Font.ReadOptions.{}))
		Fuzz.expect_no_leaks!(|{}| shape(font, text))
	}
	seed = match choice % 8 {
		0 => direct_file
		1 => rearrange_file
		2 => context_file
		3 => ligature_file
		4 => insertion_file
		5 => signed_file
		6 => multistore_file
		_ => real_file
	}
	file = FontBuild.fuzz_font(bytes.drop_first(1), seed)
	match Font.from_bytes(file, Font.ReadOptions.{}) {
		Err(problems) => match Font.from_bytes(file, Font.ReadOptions.{}) {
			Err(again) => if problems != again {
				crash "mort read problems nondeterministic"
			}
			Ok(_) => crash "mort read changed result"
		}
		Ok(font) => {
			for text in ["", "ab", "aab", Str.join_with(List.repeat("ab", 129), ""), "áb"] {
				plan = Font.plan(font, Font.ShapeOptions.{ script: "Latn" })
				run = match Font.shape_checked(font, plan, text) {
					Ok(value) => value
					Err(OverBudget({ run: partial, budgets })) => {
						if budgets.is_empty() {
							crash "mort unreported budget stop"
						}
						partial
					}
					Err(ProgramAborted({ run: partial })) => partial
				}
				if !aligned(run) or run.glyphs.len() > (256 * text.count_utf8_bytes()).max(65536) or !run.glyphs.all(|glyph| glyph < Font.glyph_count(font)) {
					crash "mort output growth/alignment/glyph domain"
				}
				if run != shape(font, text) {
					crash "mort checked/default output differs"
				}
			}
		}
	}
	Fuzz.keep
}

target = Fuzz.target_with!({ name: "font-mort", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(16)) })
