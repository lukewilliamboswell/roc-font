app [target] {
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import font.Font
import fuzz.Fuzz
import "../tests/fonts/graphite/delete-leaf/getter-ltr.ttf" as getter : List(U8)
import "../tests/fonts/graphite/delete-leaf/getter-detached-ltr.ttf" as detached : List(U8)
import "../tests/fonts/graphite-geometry/deleted-leaf-audit/collision-deleted-leaf-delete-da-ltr.ttf" as parent_first : List(U8)
import "../tests/fonts/graphite-geometry/deleted-leaf-audit/collision-deleted-leaf-delete-ad-ltr.ttf" as leaf_first : List(U8)

import "../tests/fonts/graphite/delete-leaf/star-delete-d-ltr.ttf" as star_tail : List(U8)
import "../tests/fonts/graphite/delete-leaf/star-delete-a-ltr.ttf" as star_first : List(U8)
import "../tests/fonts/graphite/delete-leaf/next-delete.ttf" as next_delete : List(U8)

# Font programs may delete input slots; every survivor stays index-aligned
# and associated with the caller's original text. Full results have cached oracles.
test! = |bytes| {
	choice = bytes.first() ?? 0
	files = [getter, detached, parent_first, leaf_first, star_tail, star_first, next_delete]
	font = Font.from_bytes(files.get(choice.to_u64() % files.len()) ?? getter, Font.ReadOptions.{}) ?? crash "deletion fixture rejected"
	plan = Font.plan(
		font,
		Font.ShapeOptions.{
			script: if (choice.bitwise_and(64) == 0) "Latn" else "Arab",
			direction: match choice.bitwise_and(12) {
				0 => LeftToRight
				4 => RightToLeft
				8 => TopToBottom
				_ => BottomToTop
			},
			clusters: if (choice.bitwise_and(16) == 0) Graphemes else Characters,
		},
	)
	if Font.shaping_engine(plan) != Graphite {
		crash "deletion target selected a different engine"
	}
	empty = Font.shape_checked(font, plan, "") ?? crash "empty direction run failed"
	if !empty.glyphs.is_empty() or !empty.advances.is_empty() or !empty.offsets.is_empty() or !empty.clusters.is_empty() or !empty.flags.is_empty() {
		crash "empty direction run retained columns"
	}
	word = Str.join_with(
		bytes.drop_first(1).take_first(8).map(
			|b| match b.bitwise_and(3) {
				0 => "a"
				1 => "b"
				2 => "c"
				_ => "d"
			},
		),
		"",
	)
	unit = "abcd".concat(word)
	var $previous = 0
	for copies in [1.U64, 4, 16] {
		text = Str.join_with(List.repeat(unit, copies), "")
		measured = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, text))
		if $previous != 0 and measured.allocations > 4 * $previous + 128 {
			crash "deletion allocations grew faster than input"
		}
		$previous = measured.allocations
		checked = Font.shape_checked(font, plan, text)
		if checked != Font.shape_checked(font, plan, text) {
			crash "deletion shaping is not deterministic"
		}
		run = match checked {
			Ok(value) => value
			Err(ProgramAborted(aborted)) => {
				if !aborted.run.glyphs.is_empty() {
					crash "aborted deletion retained partial output"
				}
				aborted.run
			}
			Err(OverBudget(_)) => crash "small deletion fixture exceeded its work budget"
		}
		if run != measured.value {
			crash "checked and unchecked direction runs differ"
		}
		n = text.to_utf8().len()
		out = run.glyphs.len()
		if out > n or run.advances.len() != out or run.offsets.len() != out or run.clusters.len() != out or run.flags.len() != out {
			crash "deletion lost slots or column alignment"
		}
		for cluster in run.clusters {
			if cluster >= n {
				crash "deletion cluster escaped original text"
			}
		}
		Fuzz.expect_no_leaks!(|{}| Font.shape_planned(font, plan, text))
	}
	Fuzz.keep
}

target = Fuzz.target_with!({ name: "font-graphite-delete", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(9)) })
