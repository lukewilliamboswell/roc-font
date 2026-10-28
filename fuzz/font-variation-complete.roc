app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import fuzz.Fuzz
import font.Font
import build.FontBuild
import "../tests/fonts/variation-complete/phantom-sparse-4.ttf" as small_file : List(U8)
import "../tests/fonts/variation-complete/phantom-sparse-64.ttf" as middle_file : List(U8)
import "../tests/fonts/variation-complete/phantom-sparse-512.ttf" as large_file : List(U8)
import "../tests/fonts/variation-complete/phantom-all-512.ttf" as all_file : List(U8)
import "../tests/fonts/variation-complete/axes-8.ttf" as axes_small : List(U8)
import "../tests/fonts/variation-complete/axes-32.ttf" as axes_middle : List(U8)
import "../tests/fonts/variation-complete/axes-128.ttf" as axes_large : List(U8)
import "../tests/fonts/variation-complete/avar-cross.ttf" as cross_file : List(U8)
import "../tests/fonts/variation-complete/avar-first-cache.ttf" as cache_file : List(U8)
import "../tests/fonts/variation-complete/phantom-last-metrics.ttf" as composite_file : List(U8)
import "../tests/fonts/variation-complete/vertical-large.ttf" as vertical_file : List(U8)
import "../tests/fonts/variation-complete/Amstelvar-avar2.ttf" as real_file : List(U8)

## Sparse phantom metrics at4/64/512 contour points allocate independently
## of contour size. Axis normalization at8/32/128 axes scales linearly.
## Real/corrupt bytes exercise complete validation before total queries

## duplicate tags, tiny avar2 scalars and composite metrics retain order.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	small = ready(small_file)
	middle = ready(middle_file)
	large = ready(large_file)
	settings = Font.Variation.{ axes: [{ tag: "wght", value: 1 }] }
	a = Fuzz.measure_allocs!(|{}| Font.advance(Font.at(small, settings), 1))
	b = Fuzz.measure_allocs!(|{}| Font.advance(Font.at(middle, settings), 1))
	c = Fuzz.measure_allocs!(|{}| Font.advance(Font.at(large, settings), 1))
	if a.value != 610 or b.value != 610 or c.value != 610 {
		crash "phantom advance changed"
	}
	if b.allocations > a.allocations + 2 or c.allocations > a.allocations + 2 {
		crash "phantom query allocated in contour size"
	}
	ax = ready(axes_small)
	bx = ready(axes_middle)
	cx = ready(axes_large)
	move = Font.Variation.{ axes: [{ tag: "0000", value: 0.5 }] }
	aa = Fuzz.measure_allocs!(|{}| Font.coordinates(Font.at(ax, move)))
	bb = Fuzz.measure_allocs!(|{}| Font.coordinates(Font.at(bx, move)))
	cc = Fuzz.measure_allocs!(|{}| Font.coordinates(Font.at(cx, move)))
	if bb.allocations > aa.allocations * 4 + 32 or cc.allocations > bb.allocations * 4 + 32 {
		crash "axis normalization allocations grew superlinearly"
	}
	if aa.value.len() != 8 or bb.value.len() != 32 or cc.value.len() != 128 {
		crash "axis output lost alignment"
	}
	Fuzz.expect_no_leaks!(|{}| Font.advance(Font.at(ready(large_file), Font.Variation.{ axes: [{ tag: "wght", value: 1 }] }), 1))
	choice = (bytes.first() ?? 0).to_u64()
	candidate = if bytes.take_first(4) == [0, 1, 0, 0] {
		bytes
	} else {
		seed = match choice % 7 {
			0 => real_file
			1 => cross_file
			2 => cache_file
			3 => composite_file
			4 => vertical_file
			5 => all_file
			_ => axes_large
		}
		FontBuild.mutate(seed, bytes.drop_first(1))
	}
	match Font.from_bytes(candidate, Font.ReadOptions.{}) {
		Ok(f) => {
			again = ready(candidate)
			for value in [-16384.Dec, 0, 0.00006103515625, 0.5, 1, 400, 16384] {
				probe = Font.Variation.{ axes: [{ tag: "wght", value }, { tag: "wdth", value }, { tag: "AX01", value }, { tag: "AX02", value }, { tag: "AX03", value: 0.0625 }] }
				moved = Font.at(f, probe)
				repeated = Font.at(again, probe)
				if Font.coordinates(moved) != Font.coordinates(repeated) or Font.coordinates(moved).len() != Font.axes(f).len() {
					crash "axis normalization lost determinism/alignment"
				}
				for glyph in [0.U32, 1, 2, 3, Font.glyph_count(f), 4294967295] {
					if Font.advance(moved, glyph) != Font.advance(repeated, glyph) or Font.vertical_advance(moved, glyph) != Font.vertical_advance(repeated, glyph) or Font.vertical_origin(moved, glyph) != Font.vertical_origin(repeated, glyph) or Font.extents(moved, glyph) != Font.extents(repeated, glyph) {
						crash "variable metric query nondeterministic"
					}
				}
			}
		}
		Err(_) => {}
	}
	Fuzz.keep
}

ready : List(U8) -> Font
ready = |bytes| match Font.from_bytes(bytes, Font.ReadOptions.{}) {
	Ok(f) => f
	Err(ps) => crash Str.inspect(ps)
}

target = Fuzz.target_with!({ name: "font-variation-complete", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(32)) })
